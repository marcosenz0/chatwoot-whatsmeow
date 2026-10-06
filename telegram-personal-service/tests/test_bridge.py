import asyncio
import base64
import json
import subprocess
import time
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock

import httpx
import pytest
from telethon import errors, types

from bridge.app import app, Manager
from bridge.session import Session, BridgeError, random_id
from bridge.store import Store


@pytest.fixture
def store(tmp_path):
    result = Store(tmp_path / 'bridge.sqlite3')
    yield result
    result.db.close()


@pytest.fixture
def session(tmp_path, store):
    factory = MagicMock()
    factory.return_value.is_connected.return_value = True
    result = Session('1:7', {'phone_number': '+5563992157585', 'ignore_groups': True}, store, tmp_path, 123, 'hash', factory=factory)
    result.state = {'status': 'connected'}
    result.client.get_input_entity = AsyncMock(return_value=types.InputPeerUser(42, 123))
    result.client.upload_file = AsyncMock(return_value=types.InputFile(id=1, parts=1, name='test', md5_checksum=''))
    return result


def test_store_survives_restart_and_isolates_equal_ids(tmp_path):
    path = tmp_path / 'state.sqlite3'
    store = Store(path)
    store.configure('1:7', {'phone_number': '+1234567890'})
    store.remember('1:7', 25, 42)
    store.remember('1:7', 25, -1007)
    store.remember('2:7', 25, 900)
    store.enqueue('1:7', {'event': 'message', 'source_id': '42:25'})
    store.save_sent('1:7', '1', {'source_id': '42:25', 'message_ids': [25], 'complete': True})
    store.db.close()
    reopened = Store(path)
    assert reopened.deleted_sources('1:7', [25]) == ['42:25']
    assert reopened.deleted_sources('1:7', [25], -1007) == ['-1007:25']
    assert reopened.deleted_sources('2:7', [25]) == ['900:25']
    assert reopened.origin('1:7', 25, 42) == {'request_id': '1', 'complete': True}
    assert reopened.origin('1:7', 25, -1007) is None
    assert len(reopened.pending()) == 1
    assert reopened.sessions() == [('1:7', {'phone_number': '+1234567890'})]
    reopened.db.close()


@pytest.mark.asyncio
async def test_callback_failure_keeps_order_and_retries_without_deleting_media(tmp_path):
    manager = Manager(tmp_path, 's' * 32, 'http://rails', 123, 'hash')
    media = tmp_path / 'media'
    media.write_bytes(b'photo')
    manager.store.add_file('1:7', 'a' * 32, media)
    manager.store.enqueue('1:7', {'event': 'message', 'attachments': [{'id': 'a' * 32}]})
    manager.store.enqueue('1:7', {'event': 'edit'})
    manager.store.enqueue('2:7', {'event': 'message'})
    attempts = []

    def handler(request):
        attempts.append(request.url.path)
        return httpx.Response(500 if request.url.path.endswith('/1/7') else 200)

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        await manager.deliver_once(client)
    assert len(attempts) == 2
    assert media.exists()
    assert manager.store.db.execute('SELECT COUNT(*) FROM outbox').fetchone()[0] == 2
    manager.store.db.execute('UPDATE outbox SET next_at=0')
    manager.store.db.commit()
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda request: httpx.Response(200))) as client:
        await manager.deliver_once(client)
    assert not media.exists()
    assert len(manager.store.pending()) == 1
    manager.store.db.close()


@pytest.mark.asyncio
async def test_text_retry_uses_same_random_id_and_sends_once(session):
    session.client.__call__ = AsyncMock()
    # Special methods are looked up on the type; use an async callable adapter.
    client = AsyncMock(return_value=types.UpdateShortSentMessage(id=70, pts=1, pts_count=1, date=datetime.now(timezone.utc), out=True))
    client.get_input_entity = session.client.get_input_entity
    session.client = client
    payload = {'request_id': '9', 'chat_id': '42', 'content': 'Hello', 'attachments': [], 'reply_to': '50'}
    first = await session.send(payload)
    second = await session.send(payload)
    assert first == second
    assert client.await_count == 1
    request = client.call_args.args[0]
    assert request.random_id == random_id('1:7', '9', 0)
    assert request.reply_to.reply_to_msg_id == 50
    assert request.message == 'Hello'
    assert first['source_id'] == '42:70'


@pytest.mark.asyncio
async def test_attachment_upload_converts_recording_to_telegram_voice(session, tmp_path):
    recording = tmp_path / 'voice.webm'
    subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'sine=frequency=440:duration=0.1', '-c:a', 'libopus', str(recording)], check=True)
    media = await session.upload({'filename': '../voice.webm', 'content_type': 'audio/webm', 'voice': True, 'data': base64.b64encode(recording.read_bytes()).decode()})
    assert isinstance(media, types.InputMediaUploadedDocument)
    assert media.attributes[0].file_name == 'voice.ogg'
    assert media.attributes[1].voice
    assert session.client.upload_file.call_args.kwargs['file_name'] == 'voice.ogg'


@pytest.mark.asyncio
async def test_partial_media_send_resumes_only_remaining_part(session):
    calls = 0

    async def send(request):
        nonlocal calls
        calls += 1
        if calls == 2:
            raise errors.FloodWaitError(request=request, capture=5)
        return types.UpdateShortSentMessage(id=70 + calls, pts=1, pts_count=1, date=datetime.now(timezone.utc), out=True)

    client = AsyncMock(side_effect=send)
    client.get_input_entity = session.client.get_input_entity
    session.client = client
    session.upload = AsyncMock(return_value=types.InputMediaUploadedPhoto(file=types.InputFile(1, 1, 'photo', '')))
    payload = {'request_id': '10', 'chat_id': '42', 'content': 'Two photos', 'attachments': [{}, {}]}
    with pytest.raises(errors.FloodWaitError):
        await session.send(payload)
    assert session.store.sent('1:7', '10')['message_ids'] == [71]
    result = await session.send(payload)
    assert result['message_ids'] == [71, 73]
    assert client.call_args.args[0].random_id == random_id('1:7', '10', 1)
    assert session.upload.await_count == 3


@pytest.mark.asyncio
async def test_sales_bots_and_broadcast_channels_do_not_enter_inbox(session):
    event = SimpleNamespace(is_group=False, is_channel=False, get_chat=AsyncMock(return_value=SimpleNamespace(bot=True)))
    assert not await session.allowed(event)
    event.is_channel = True
    event.get_chat = AsyncMock(return_value=SimpleNamespace(bot=False))
    assert not await session.allowed(event)
    event.is_group = True
    assert not await session.allowed(event)
    session.config['ignore_groups'] = False
    assert await session.allowed(event)


@pytest.mark.asyncio
async def test_own_outgoing_echo_matches_original_chatwoot_message(session):
    session.store.save_sent('1:7', '9', {'source_id': '42:70', 'message_ids': [70], 'complete': True})
    msg = SimpleNamespace(id=70, out=True, date=datetime.now(timezone.utc), message='Hello', reply_to=None, media=None)
    chat = SimpleNamespace(id=42, first_name='Test', last_name=None, username='test')
    event = SimpleNamespace(message=msg, chat_id=42, is_group=False, is_channel=False, get_chat=AsyncMock(return_value=chat))
    await session.import_message(event)
    payload = json.loads(session.store.pending()[0]['payload'])
    assert payload['chatwoot_message_id'] == '9'
    assert payload['source_id'] == '42:70'


@pytest.mark.asyncio
async def test_channels_and_groups_can_be_enabled_independently(session):
    event = SimpleNamespace(is_group=False, is_channel=True, get_chat=AsyncMock(return_value=SimpleNamespace(bot=False)))
    assert not await session.allowed(event)
    session.config['ignore_channels'] = False
    assert await session.allowed(event)
    event.is_group = True
    assert not await session.allowed(event)
    session.config['ignore_groups'] = False
    assert await session.allowed(event)
    event.get_chat.return_value.bot = True
    assert not await session.allowed(event)


@pytest.mark.asyncio
async def test_partial_send_echo_does_not_complete_failed_message(session):
    session.store.save_sent('1:7', '9', {'source_id': '42:70', 'message_ids': [70], 'complete': False})
    msg = SimpleNamespace(id=70, out=True, date=datetime.now(timezone.utc), message='Hello', reply_to=None, media=None)
    event = SimpleNamespace(message=msg, chat_id=42, is_group=False, is_channel=False,
                            get_chat=AsyncMock(return_value=SimpleNamespace(id=42, first_name='Test')))
    await session.import_message(event)
    assert session.store.pending() == []


@pytest.mark.asyncio
async def test_incoming_media_is_durable_before_download_and_resumes_after_failure(session, tmp_path):
    manager = Manager(tmp_path / 'manager', 's' * 32, 'http://rails', 123, 'hash')
    manager.store.db.close()
    manager.store = session.store
    manager.sessions[session.key] = session
    msg = SimpleNamespace(id=80, out=False, date=datetime.now(timezone.utc), message='Photo', reply_to=None,
                          media=SimpleNamespace(), file=SimpleNamespace(size=5, name='image.jpg', ext='.jpg', mime_type='image/jpeg'))
    event = SimpleNamespace(message=msg, chat_id=42, is_group=False, is_channel=False,
                            get_chat=AsyncMock(return_value=SimpleNamespace(id=42, first_name='Test')))
    await session.import_message(event)
    session.client.get_messages = AsyncMock(return_value=msg)
    session.client.download_media = AsyncMock(side_effect=OSError('temporary network failure'))
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda request: httpx.Response(200))) as http:
        await manager.deliver_once(http)
        assert session.store.db.execute('SELECT COUNT(*) FROM outbox').fetchone()[0] == 1
        session.store.db.execute('UPDATE outbox SET next_at=0')
        session.store.db.commit()
        async def download(message, file):
            from pathlib import Path
            # Telethon changes extensionless filenames. Our opaque path must have an extension.
            assert Path(file).suffix
            Path(file).write_bytes(b'photo')
            return file
        session.client.download_media.side_effect = download
        await manager.deliver_once(http)
    assert session.store.pending() == []
    assert session.store.db.execute('SELECT COUNT(*) FROM files').fetchone()[0] == 0


@pytest.mark.asyncio
async def test_qr_refresh_and_password_retry_clear_secrets(session):
    qr = SimpleNamespace(url='tg://login?token=test', expires=datetime.now(timezone.utc) + timedelta(seconds=20),
                         wait=AsyncMock(side_effect=[asyncio.TimeoutError(), errors.SessionPasswordNeededError(request=None)]), recreate=AsyncMock())
    session.client.qr_login = AsyncMock(return_value=qr)
    session.client.sign_in = AsyncMock(side_effect=[errors.PasswordHashInvalidError(request=None), None])
    task = asyncio.create_task(session.pair())
    for _ in range(30):
        await asyncio.sleep(0)
        if session.state['status'] == 'password':
            break
    assert session.state == {'status': 'password'}
    assert qr.recreate.await_count == 1
    await session.password('incorrect')
    for _ in range(30):
        await asyncio.sleep(0)
        if session.state.get('error') == 'invalid_password':
            break
    assert session.state['error'] == 'invalid_password'
    await session.password('correct')
    await asyncio.wait_for(task, 1)
    assert session.password_value is None
    assert 'qr_code' not in session.public_state()


@pytest.mark.asyncio
async def test_wrong_number_is_rejected_and_new_session_logged_out(session):
    session.client.connect = AsyncMock()
    session.client.disconnect = AsyncMock()
    session.client.is_user_authorized = AsyncMock(return_value=True)
    session.client.get_me = AsyncMock(return_value=SimpleNamespace(bot=False, phone='1234567890'))
    session.client.log_out = AsyncMock()
    await session.run(True)
    assert session.state == {'status': 'error', 'error': 'wrong_account'}
    session.client.log_out.assert_awaited_once()


def test_expired_qr_is_not_returned(session):
    session.state = {'status': 'qr', 'qr_code': 'secret-qr', 'expires_at': time.time() - 1}
    assert 'qr_code' not in session.public_state()


@pytest.mark.asyncio
async def test_service_requires_secret_and_isolates_attachment_namespace(tmp_path):
    manager = Manager(tmp_path, 's' * 32, 'http://rails', 123, 'hash')
    app.state.manager = manager
    media = tmp_path / 'media'
    media.write_bytes(b'safe')
    manager.store.add_file('1:7', 'a' * 32, media)
    endpoint = '/sessions/1/7/media/' + 'a' * 32
    headers = {'Authorization': 'Bearer ' + 's' * 32}
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url='http://service') as client:
        assert (await client.get(endpoint)).status_code == 401
        response = await client.get(endpoint, headers=headers)
        assert response.content == b'safe'
        assert response.headers['Cache-Control'] == 'no-store'
        assert (await client.get(endpoint.replace('/1/7/', '/2/7/'), headers=headers)).status_code == 404
        assert (await client.get('/sessions/2/7', headers=headers)).json() == {'status': 'disconnected'}
    manager.store.db.close()


@pytest.mark.asyncio
async def test_temporary_media_is_never_downloaded(session):
    payload = {'content': '', 'attachments': []}
    msg = SimpleNamespace(media=SimpleNamespace(ttl_seconds=20))
    session.client.download_media = AsyncMock()
    await session.add_media(payload, msg)
    assert 'Temporary media' in payload['content']
    session.client.download_media.assert_not_awaited()
