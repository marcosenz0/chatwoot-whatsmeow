import asyncio
import hmac
import json
import os
from contextlib import asynccontextmanager
from pathlib import Path

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, FileResponse
from pydantic import BaseModel, Field
from telethon import errors

from .session import Session, BridgeError
from .store import Store


class Config(BaseModel):
    phone_number: str = Field(pattern=r'^\+[1-9]\d{7,14}$')
    ignore_groups: bool = True
    ignore_channels: bool = True


class Password(BaseModel):
    password: str = Field(min_length=1, max_length=256)


class Settings(BaseModel):
    ignore_groups: bool
    ignore_channels: bool


class Attachment(BaseModel):
    filename: str = Field(min_length=1, max_length=255)
    content_type: str = Field(max_length=100)
    file_type: str = Field(max_length=20)
    voice: bool = False
    data: str = Field(max_length=69905076)


class Message(BaseModel):
    request_id: str = Field(pattern=r'^\d+$')
    chat_id: str = Field(pattern=r'^-?\d+$')
    content: str = Field(default='', max_length=4096)
    reply_to: str | None = Field(default=None, pattern=r'^\d+$')
    attachments: list[Attachment] = Field(default_factory=list, max_length=10)


class Manager:
    def __init__(self, directory, secret, callback_url, api_id, api_hash):
        self.directory = Path(directory)
        self.directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.secret, self.callback_url, self.api_id, self.api_hash = secret, callback_url.rstrip('/'), api_id, api_hash
        self.store = Store(self.directory / 'bridge.sqlite3')
        os.chmod(self.directory / 'bridge.sqlite3', 0o600)
        self.sessions = {}

    def get(self, account, inbox):
        return self.sessions.get(f'{account}:{inbox}')

    def connect(self, account, inbox, config):
        if not self.api_id or not self.api_hash:
            raise BridgeError('application_not_configured')
        key = f'{account}:{inbox}'
        session = self.sessions.get(key)
        if session and session.config['phone_number'] != config['phone_number']:
            raise BridgeError('disconnect_before_changing_number')
        if not session:
            session = self.sessions[key] = Session(key, config, self.store, self.directory, self.api_id, self.api_hash)
        session.config = config
        self.store.configure(key, config)
        session.start()
        return session

    def restore(self):
        for key, config in self.store.sessions():
            session = self.sessions[key] = Session(key, config, self.store, self.directory, self.api_id, self.api_hash)
            session.start(pairing=False)

    async def deliver_once(self, http):
        for row in self.store.pending():
            account, inbox = row['key'].split(':')
            payload = json.loads(row['payload'])
            try:
                if '_media_message_id' in payload:
                    session = self.sessions.get(row['key'])
                    if not session or session.state['status'] != 'connected':
                        self.store.retry(row['id'], row['attempts'] + 1)
                        continue
                    msg = await session.client.get_messages(int(payload['chat_id']), ids=payload['_media_message_id'])
                    if msg:
                        await session.add_media(payload, msg)
                    else:
                        payload['content'] += '\n[Attachment deleted on Telegram before retrieval]'
                    del payload['_media_message_id']
                    self.store.update_payload(row['id'], payload)
                response = await http.post(f'{self.callback_url}/webhooks/telegram_personal/{account}/{inbox}',
                                           json={'payload': payload}, headers={'Authorization': 'Bearer ' + self.secret})
                response.raise_for_status()
            except (httpx.HTTPError, OSError, asyncio.TimeoutError, errors.RPCError):
                self.store.retry(row['id'], row['attempts'] + 1)
                continue
            self.store.ack(row['id'])
            for attachment in payload.get('attachments', []):
                path = self.store.file(row['key'], attachment['id'])
                if path:
                    Path(path).unlink(missing_ok=True)
                    self.store.remove_file(attachment['id'])

    async def dispatch(self):
        async with httpx.AsyncClient(timeout=120, follow_redirects=False) as http:
            while True:
                await self.deliver_once(http)
                await asyncio.sleep(1)


@asynccontextmanager
async def lifespan(app):
    secret = os.environ['TELEGRAM_PERSONAL_SHARED_SECRET']
    if len(secret) < 32:
        raise RuntimeError('TELEGRAM_PERSONAL_SHARED_SECRET must have at least 32 characters')
    manager = Manager(os.getenv('TELEGRAM_PERSONAL_DATA_DIR', '/data'), secret,
                      os.environ['CHATWOOT_INTERNAL_URL'], int(os.getenv('TELEGRAM_API_ID', '0')), os.getenv('TELEGRAM_API_HASH', ''))
    app.state.manager = manager
    manager.restore()
    dispatch = asyncio.create_task(manager.dispatch())
    try:
        yield
    finally:
        dispatch.cancel()
        await asyncio.gather(dispatch, return_exceptions=True)
        await asyncio.gather(*(session.disconnect(logout=False) for session in manager.sessions.values()))
        manager.store.db.close()


app = FastAPI(lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)


@app.middleware('http')
async def authenticate(request: Request, call_next):
    if request.url.path != '/health':
        expected = 'Bearer ' + request.app.state.manager.secret
        if not hmac.compare_digest(request.headers.get('Authorization', ''), expected):
            return JSONResponse({'error': 'unauthorized'}, status_code=401)
    response = await call_next(request)
    response.headers['Cache-Control'] = 'no-store'
    return response


@app.exception_handler(BridgeError)
async def bridge_error(request, error):
    return JSONResponse({'error': error.code}, status_code=422)


@app.exception_handler(errors.RPCError)
async def telegram_error(request, error):
    if isinstance(error, errors.FloodWaitError):
        return JSONResponse({'error': 'flood_wait', 'retry_after': error.seconds}, status_code=429)
    return JSONResponse({'error': 'telegram_rejected_message'}, status_code=422)


@app.get('/health')
async def health(request: Request):
    m = request.app.state.manager
    return {'status': 'healthy', 'configured': bool(m.api_id and m.api_hash), 'sessions': len(m.sessions),
            'pending_events': m.store.db.execute('SELECT COUNT(*) FROM outbox').fetchone()[0]}


@app.post('/sessions/{account}/{inbox}')
async def connect(account: int, inbox: int, config: Config, request: Request):
    return request.app.state.manager.connect(account, inbox, config.model_dump()).public_state()


@app.get('/sessions/{account}/{inbox}')
async def status(account: int, inbox: int, request: Request):
    session = request.app.state.manager.get(account, inbox)
    return session.public_state() if session else {'status': 'disconnected'}


@app.post('/sessions/{account}/{inbox}/password')
async def password(account: int, inbox: int, body: Password, request: Request):
    session = request.app.state.manager.get(account, inbox)
    if not session:
        raise BridgeError('not_connected')
    return await session.password(body.password)


@app.delete('/sessions/{account}/{inbox}')
async def disconnect(account: int, inbox: int, request: Request):
    manager = request.app.state.manager
    session = manager.get(account, inbox)
    if not session:
        return {'status': 'disconnected'}
    result = await session.disconnect()
    del manager.sessions[session.key]
    return result


@app.post('/sessions/{account}/{inbox}/messages')
async def send(account: int, inbox: int, body: Message, request: Request):
    session = request.app.state.manager.get(account, inbox)
    if not session:
        raise BridgeError('not_connected')
    return await session.send(body.model_dump())


@app.get('/sessions/{account}/{inbox}/media/{media_id}')
async def media(account: int, inbox: int, media_id: str, request: Request):
    path = request.app.state.manager.store.file(f'{account}:{inbox}', media_id)
    if not path:
        return JSONResponse({'error': 'media_unavailable'}, status_code=404)
    return FileResponse(path, media_type='application/octet-stream')


@app.patch('/sessions/{account}/{inbox}/settings')
async def settings(account: int, inbox: int, body: Settings, request: Request):
    manager = request.app.state.manager
    session = manager.get(account, inbox)
    if session:
        session.config.update(body.model_dump())
        manager.store.configure(session.key, session.config)
    return {'saved': True}
