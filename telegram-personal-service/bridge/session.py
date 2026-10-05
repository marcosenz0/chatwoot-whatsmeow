import asyncio
import base64
import hashlib
import io
import mimetypes
import os
import time
import uuid
from pathlib import Path

import qrcode
from telethon import TelegramClient, events, errors, functions, types
from .media import prepare

MAX_FILE_BYTES = 50 * 1024 * 1024


class BridgeError(Exception):
    def __init__(self, code):
        self.code = code


def random_id(key, request_id, part):
    return int.from_bytes(hashlib.sha256(f'{key}:{request_id}:{part}'.encode()).digest()[:8], 'big', signed=True)


def message_id(result):
    if isinstance(result, types.UpdateShortSentMessage):
        return result.id
    for update in getattr(result, 'updates', []):
        if isinstance(update, types.UpdateMessageID):
            return update.id
        if isinstance(update, (types.UpdateNewMessage, types.UpdateNewChannelMessage)):
            return update.message.id
    raise BridgeError('delivery_unconfirmed')


class Session:
    def __init__(self, key, config, store, directory, api_id, api_hash, factory=TelegramClient):
        self.key, self.config, self.store = key, config, store
        self.directory = Path(directory) / key.replace(':', '-')
        self.directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.client = factory(str(self.directory / 'telegram'), api_id, api_hash,
                              device_model='Chatwoot Telegram', app_version='1.0', catch_up=True,
                              sequential_updates=True, flood_sleep_threshold=0)
        self.state = {'status': 'disconnected'}
        self.task = None
        self.password_ready = asyncio.Event()
        self.password_value = None
        self.send_lock = asyncio.Lock()
        self.client.add_event_handler(self.on_message, events.NewMessage())
        self.client.add_event_handler(self.on_edit, events.MessageEdited())
        self.client.add_event_handler(self.on_delete, events.MessageDeleted())
        self.client.add_event_handler(self.on_read, events.MessageRead())

    def public_state(self):
        state = dict(self.state)
        if state.get('expires_at', 0) < time.time():
            state.pop('qr_code', None)
        if state['status'] == 'connected' and not self.client.is_connected():
            state['status'] = 'connecting'
        return state

    def start(self, pairing=True):
        if self.task and not self.task.done():
            return
        self.task = asyncio.create_task(self.run(pairing))

    async def run(self, pairing):
        try:
            self.state = {'status': 'connecting'}
            await self.client.connect()
            if not await self.client.is_user_authorized():
                if not pairing:
                    raise BridgeError('session_expired')
                await self.pair()
            me = await self.client.get_me()
            if me.bot:
                raise BridgeError('personal_account_required')
            if '+' + (me.phone or '') != self.config['phone_number']:
                await self.client.log_out()
                raise BridgeError('wrong_account')
            self.state = {'status': 'connected', 'telegram_user_id': str(me.id), 'username': me.username or ''}
            self.store.configure(self.key, self.config)
            self.store.enqueue(self.key, {'event': 'session', **self.state})
            # Populate entity cache so incoming short updates and replies resolve access hashes.
            await self.client.get_dialogs(limit=None)
            await self.client.catch_up()
            await self.client.disconnected
            if self.state['status'] == 'connected':
                self.state = {'status': 'disconnected', 'error': 'session_expired'}
                self.store.enqueue(self.key, {'event': 'session', 'status': 'disconnected'})
        except asyncio.CancelledError:
            raise
        except Exception as error:
            code = error.code if isinstance(error, BridgeError) else ('session_expired' if isinstance(error, errors.UnauthorizedError) else 'connection_failed')
            self.state = {'status': 'error', 'error': code}
            self.store.enqueue(self.key, {'event': 'session', 'status': 'error'})
            await self.client.disconnect()

    async def pair(self):
        deadline = time.monotonic() + 300
        qr = await self.client.qr_login()
        while time.monotonic() < deadline:
            image = io.BytesIO()
            qrcode.make(qr.url).save(image, format='PNG')
            self.state = {'status': 'qr', 'qr_code': 'data:image/png;base64,' + base64.b64encode(image.getvalue()).decode(),
                          'expires_at': qr.expires.timestamp()}
            try:
                await qr.wait(timeout=max(1, qr.expires.timestamp() - time.time()))
                return
            except asyncio.TimeoutError:
                await qr.recreate()
            except errors.SessionPasswordNeededError:
                self.state = {'status': 'password'}
                while True:
                    self.password_ready.clear()
                    await asyncio.wait_for(self.password_ready.wait(), timeout=300)
                    password, self.password_value = self.password_value, None
                    try:
                        await self.client.sign_in(password=password)
                        return
                    except errors.PasswordHashInvalidError:
                        self.state = {'status': 'password', 'error': 'invalid_password'}
                    finally:
                        password = None
        raise BridgeError('qr_expired')

    async def password(self, password):
        if self.state['status'] != 'password':
            raise BridgeError('password_not_required')
        self.password_value = password
        self.password_ready.set()
        return {'status': 'password'}

    async def disconnect(self, logout=True):
        self.state = {'status': 'disconnected'}
        if self.task:
            self.task.cancel()
            await asyncio.gather(self.task, return_exceptions=True)
        if logout:
            if self.client.is_connected() and await self.client.is_user_authorized():
                await self.client.log_out()
            self.store.configure(self.key, self.config, enabled=False)
            self.store.enqueue(self.key, {'event': 'session', 'status': 'disconnected'})
        await self.client.disconnect()
        return dict(self.state)

    async def allowed(self, event):
        if self.state['status'] != 'connected':
            return False
        if self.config.get('ignore_channels', True) and event.is_channel and not event.is_group:
            return False
        if self.config['ignore_groups'] and event.is_group:
            return False
        chat = await event.get_chat()
        return not getattr(chat, 'bot', False)  # Raven and BotFather remain outside this inbox.

    async def on_message(self, event):
        if not await self.allowed(event):
            return
        async with self.send_lock:
            await self.import_message(event)

    async def import_message(self, event):
        msg, chat = event.message, await event.get_chat()
        chat_id = event.chat_id
        self.store.remember(self.key, msg.id, chat_id)
        attributes = {}
        if msg.reply_to and msg.reply_to.reply_to_msg_id:
            attributes['in_reply_to_external_id'] = f'{chat_id}:{msg.reply_to.reply_to_msg_id}'
        if event.is_group:
            sender = await event.get_sender()
            attributes['telegram_sender_name'] = ' '.join(filter(None, [getattr(sender, 'first_name', ''), getattr(sender, 'last_name', '')]))
        payload = {'event': 'message', 'source_id': f'{chat_id}:{msg.id}', 'chat_id': str(chat_id),
                   'chat_name': getattr(chat, 'title', None) or ' '.join(filter(None, [getattr(chat, 'first_name', ''), getattr(chat, 'last_name', '')])) or str(chat_id),
                   'contact_attributes': {'social_telegram_user_id': str(chat.id), 'social_telegram_user_name': getattr(chat, 'username', '')},
                   'group': bool(event.is_group), 'channel': bool(event.is_channel and not event.is_group),
                   'outgoing': bool(msg.out), 'date': int(msg.date.timestamp()),
                   'content': msg.message or '', 'content_attributes': attributes, 'attachments': []}
        origin = self.store.origin(self.key, msg.id, chat_id) if msg.out else None
        if origin:
            # A partial send must remain retryable in Chatwoot, even after its first part echoes back.
            if not origin['complete']:
                return
            payload['chatwoot_message_id'] = origin['request_id']
        elif msg.media:
            # Persist before downloading: temporary Telegram/network failures must not lose the message.
            payload['_media_message_id'] = msg.id
        self.store.enqueue(self.key, payload)

    async def add_media(self, payload, msg):
        if getattr(msg.media, 'ttl_seconds', None):
            payload['content'] += '\n[Temporary media: open in the Telegram app]'
            return
        if isinstance(msg.media, (types.MessageMediaGeo, types.MessageMediaGeoLive, types.MessageMediaVenue)):
            payload['location'] = {'lat': msg.media.geo.lat, 'long': msg.media.geo.long}
        elif isinstance(msg.media, types.MessageMediaContact):
            payload['content'] += '\n' + ' '.join(filter(None, [msg.media.first_name, msg.media.last_name, msg.media.phone_number]))
        elif msg.file:
            if (msg.file.size or 0) > MAX_FILE_BYTES:
                payload['content'] += '\n[File exceeds 50 MB: open in Telegram]'
                return
            media_id = uuid.uuid4().hex
            path = self.directory / (media_id + '.bin')
            await self.client.download_media(msg, file=str(path))
            os.chmod(path, 0o600)
            self.store.add_file(self.key, media_id, path)
            payload['attachments'] = [{'id': media_id, 'filename': Path(msg.file.name or ('telegram' + (msg.file.ext or '.bin'))).name,
                                       'content_type': msg.file.mime_type or 'application/octet-stream'}]
        elif not payload['content']:
            payload['content'] = '[Unsupported message: open in Telegram]'

    async def on_edit(self, event):
        if not await self.allowed(event):
            return
        self.store.enqueue(self.key, {'event': 'edit', 'source_id': f'{event.chat_id}:{event.message.id}',
                                      'content': event.message.message or '', 'date': int((event.message.edit_date or event.message.date).timestamp())})

    async def on_delete(self, event):
        sources = self.store.deleted_sources(self.key, event.deleted_ids, event.chat_id)
        if sources:
            self.store.enqueue(self.key, {'event': 'delete', 'source_ids': sources})

    async def on_read(self, event):
        if event.outbox:
            self.store.enqueue(self.key, {'event': 'read', 'chat_id': str(event.chat_id), 'max_id': event.max_id})

    async def send(self, payload):
        if self.state['status'] != 'connected':
            raise BridgeError('not_connected')
        async with self.send_lock:
            request_id = payload['request_id']
            previous = self.store.sent(self.key, request_id)
            if previous and previous.get('complete'):
                return previous
            peer = await self.client.get_input_entity(int(payload['chat_id']))
            reply = types.InputReplyToMessage(reply_to_msg_id=int(payload['reply_to'])) if payload.get('reply_to') else None
            ids = (previous or {}).get('message_ids', [])
            attachments = payload.get('attachments', [])
            content = payload.get('content', '')
            parts = attachments or [None]
            if not attachments and not content:
                raise BridgeError('empty_message')
            for index, attachment in enumerate(parts):
                if index < len(ids):
                    continue
                rid = random_id(self.key, request_id, index)
                if attachment is not None:
                    media = await self.upload(attachment)
                    result = await self.client(functions.messages.SendMediaRequest(peer=peer, media=media, message=content if index == 0 else '',
                                                                                random_id=rid, reply_to=reply))
                else:
                    result = await self.client(functions.messages.SendMessageRequest(peer=peer, message=content, random_id=rid, reply_to=reply))
                ids.append(message_id(result))
                self.store.remember(self.key, ids[-1], int(payload['chat_id']))
                self.store.save_sent(self.key, request_id, {'source_id': f"{payload['chat_id']}:{ids[0]}", 'message_ids': ids, 'complete': False})
            saved = {'source_id': f"{payload['chat_id']}:{ids[0]}", 'message_ids': ids, 'complete': True}
            self.store.save_sent(self.key, request_id, saved)
            return saved

    async def upload(self, attachment):
        encoded = attachment['data']
        if len(encoded) > (MAX_FILE_BYTES * 4 // 3 + 8):
            raise BridgeError('file_too_large')
        try:
            data = base64.b64decode(encoded, validate=True)
        except ValueError:
            raise BridgeError('invalid_file')
        if len(data) > MAX_FILE_BYTES:
            raise BridgeError('file_too_large')
        filename = Path(attachment['filename']).name
        mime = attachment.get('content_type') or mimetypes.guess_type(filename)[0] or 'application/octet-stream'
        prepared = await prepare(data, filename, mime, bool(attachment.get('voice')))
        if prepared is None:
            raise BridgeError('invalid_file')
        data, filename, mime, attributes = prepared
        uploaded = await self.client.upload_file(data, file_name=filename)
        if mime in ('image/jpeg', 'image/png'):
            return types.InputMediaUploadedPhoto(file=uploaded)
        return types.InputMediaUploadedDocument(file=uploaded, mime_type=mime, attributes=attributes)
