import json
import sqlite3
import time


class Store:
    def __init__(self, path):
        self.db = sqlite3.connect(path)
        self.db.row_factory = sqlite3.Row
        self.db.executescript('''
          PRAGMA journal_mode=WAL;
          CREATE TABLE IF NOT EXISTS sessions (key TEXT PRIMARY KEY, config TEXT NOT NULL, enabled INTEGER NOT NULL);
          CREATE TABLE IF NOT EXISTS outbox (id INTEGER PRIMARY KEY, key TEXT NOT NULL, payload TEXT NOT NULL, attempts INTEGER DEFAULT 0, next_at REAL DEFAULT 0);
          CREATE TABLE IF NOT EXISTS sent (key TEXT NOT NULL, request_id TEXT NOT NULL, result TEXT NOT NULL, PRIMARY KEY(key, request_id));
          CREATE TABLE IF NOT EXISTS messages (key TEXT NOT NULL, id INTEGER NOT NULL, chat_id INTEGER NOT NULL, PRIMARY KEY(key,id,chat_id));
          CREATE TABLE IF NOT EXISTS files (id TEXT PRIMARY KEY, key TEXT NOT NULL, path TEXT NOT NULL);
        ''')

    def configure(self, key, config, enabled=True):
        with self.db:
            self.db.execute('INSERT OR REPLACE INTO sessions VALUES (?,?,?)', (key, json.dumps(config), enabled))

    def sessions(self):
        return [(r['key'], json.loads(r['config'])) for r in self.db.execute('SELECT * FROM sessions WHERE enabled=1')]

    def enqueue(self, key, payload):
        with self.db:
            self.db.execute('INSERT INTO outbox(key,payload) VALUES (?,?)', (key, json.dumps(payload)))

    def pending(self):
        # Preserve event order per session, even when a callback is temporarily failing.
        return self.db.execute('SELECT * FROM outbox WHERE id IN (SELECT MIN(id) FROM outbox GROUP BY key) AND next_at<=?', (time.time(),)).fetchall()

    def ack(self, event_id):
        with self.db:
            self.db.execute('DELETE FROM outbox WHERE id=?', (event_id,))

    def update_payload(self, event_id, payload):
        with self.db:
            self.db.execute('UPDATE outbox SET payload=? WHERE id=?', (json.dumps(payload), event_id))

    def retry(self, event_id, attempts):
        with self.db:
            self.db.execute('UPDATE outbox SET attempts=?, next_at=? WHERE id=?', (attempts, time.time() + min(60, 2 ** min(attempts, 6)), event_id))

    def save_sent(self, key, request_id, result):
        with self.db:
            self.db.execute('INSERT OR REPLACE INTO sent VALUES (?,?,?)', (key, request_id, json.dumps(result)))

    def sent(self, key, request_id):
        row = self.db.execute('SELECT result FROM sent WHERE key=? AND request_id=?', (key, request_id)).fetchone()
        return json.loads(row['result']) if row else None

    def origin(self, key, message_id, chat_id):
        # Recorded before outgoing update delivery acquires the session's send lock.
        for row in self.db.execute('SELECT request_id,result FROM sent WHERE key=?', (key,)):
            result = json.loads(row['result'])
            if result['source_id'].split(':')[0] == str(chat_id) and message_id in result['message_ids']:
                return {'request_id': row['request_id'], 'complete': result.get('complete', False)}
        return None

    def remember(self, key, message_id, chat_id):
        with self.db:
            self.db.execute('INSERT OR REPLACE INTO messages VALUES (?,?,?)', (key, message_id, chat_id))

    def deleted_sources(self, key, ids, chat_id=None):
        if chat_id is not None:
            return [f'{chat_id}:{message_id}' for message_id in ids]
        result = []
        for message_id in ids:
            row = self.db.execute('SELECT chat_id FROM messages WHERE key=? AND id=? AND chat_id>0', (key, message_id)).fetchone()
            if row:
                result.append(f'{row[0]}:{message_id}')
        return result

    def add_file(self, key, media_id, path):
        with self.db:
            self.db.execute('INSERT INTO files VALUES (?,?,?)', (media_id, key, str(path)))

    def file(self, key, media_id):
        row = self.db.execute('SELECT path FROM files WHERE key=? AND id=?', (key, media_id)).fetchone()
        return row[0] if row else None

    def remove_file(self, media_id):
        with self.db:
            self.db.execute('DELETE FROM files WHERE id=?', (media_id,))
