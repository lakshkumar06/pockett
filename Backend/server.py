#!/usr/bin/env python3
"""Pocket's local test backend. Python standard library + SQLite only."""
import argparse
import hashlib
import hmac
import json
import re
import secrets
import sqlite3
import time
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit, parse_qs

sys.path.insert(0, str(Path(__file__).parent))
from web_api import WebAPI, APIError, MIGRATION_WEB, cleanup, revoke

SCHEMA = """
PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS users(username TEXT PRIMARY KEY, salt TEXT NOT NULL, password TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS sessions(token TEXT PRIMARY KEY, username TEXT NOT NULL REFERENCES users, expires REAL NOT NULL);
CREATE TABLE IF NOT EXISTS apps(id TEXT PRIMARY KEY, owner TEXT NOT NULL REFERENCES users, name TEXT NOT NULL, url TEXT NOT NULL, summary TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS shares(app TEXT REFERENCES apps ON DELETE CASCADE, username TEXT REFERENCES users, PRIMARY KEY(app, username));
"""

# Versioned, transactional migrations preserve all pre-existing accounts and listings.
# Experience snapshots follow the agreed Developer/Contracts API.
MIGRATIONS = [(1, (
    "CREATE TABLE IF NOT EXISTS schema_migrations(version INTEGER PRIMARY KEY, applied_at REAL NOT NULL)",
)), (2, (
    "CREATE TABLE experiences(app_id TEXT PRIMARY KEY REFERENCES apps(id) ON DELETE CASCADE, owner TEXT NOT NULL REFERENCES users(username), creator_key TEXT NOT NULL, revision INTEGER NOT NULL, configuration TEXT NOT NULL, source_url TEXT, UNIQUE(owner, creator_key))",
    "CREATE TABLE experience_snapshots(app_id TEXT NOT NULL REFERENCES experiences(app_id) ON DELETE CASCADE, revision INTEGER NOT NULL, configuration TEXT NOT NULL, PRIMARY KEY(app_id, revision))",
)), (3, MIGRATION_WEB)]


def migrate(db):
    db.executescript(SCHEMA)
    db.execute("CREATE TABLE IF NOT EXISTS schema_migrations(version INTEGER PRIMARY KEY, applied_at REAL NOT NULL)")
    for version, statements in MIGRATIONS:
        with db:
            db.execute('BEGIN IMMEDIATE')
            if db.execute("SELECT 1 FROM schema_migrations WHERE version=?", (version,)).fetchone():
                continue
            for statement in statements:
                db.execute(statement)
            db.execute("INSERT INTO schema_migrations VALUES (?, ?)", (version, time.time()))




def password_hash(password, salt):
    return hashlib.scrypt(password.encode(), salt=bytes.fromhex(salt), n=16384, r=8, p=1).hex()


def field(data, key, maximum, minimum=1):
    value = data.get(key)
    if not isinstance(value, str) or not minimum <= len(value.strip()) <= maximum:
        raise APIError(400, f'{key} must contain {minimum}–{maximum} characters.')
    return value.strip()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass  # Do not log account data or session headers.

    def do_GET(self): self.handle_api()
    def do_POST(self): self.handle_api()
    def do_DELETE(self): self.handle_api()

    def handle_api(self):
        try:
            data = {}
            if self.command == 'POST':
                try:
                    length = int(self.headers.get('Content-Length', '0'))
                    maximum = 4096 if urlsplit(self.path).path == '/notification-events' else 16384
                    if not 0 < length <= maximum:
                        raise APIError(400, 'JSON request exceeds the endpoint limit.')
                    data = json.loads(self.rfile.read(length), parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
                    if not isinstance(data, dict): raise ValueError()
                except (ValueError, UnicodeDecodeError, RecursionError):
                    raise APIError(400, 'Invalid JSON body.')
            with sqlite3.connect(self.server.db) as db:
                db.row_factory = sqlite3.Row
                db.execute('PRAGMA foreign_keys=ON')
                if self.command in ('POST', 'DELETE'): db.execute('BEGIN IMMEDIATE')
                cleanup(db)
                result = self.route(db, urlsplit(self.path).path.strip('/').split('/'), data)
            self.reply(200, result)
        except APIError as error:
            self.reply(error.status, {'error': error.message})
        except sqlite3.IntegrityError:
            self.reply(409, {'error': 'That username already exists.'})
        except Exception:
            self.reply(500, {'error': 'Server error. Try again.'})

    def reply(self, status, data):
        body = json.dumps(data, ensure_ascii=False, separators=(',', ':'), allow_nan=False).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def route(self, db, path, data):
        method = self.command
        if path == ['health'] and method == 'GET': return {'ok': True}
        if path in (['signup'], ['login']) and method == 'POST':
            username = field(data, 'username', 32).lower()
            if not re.fullmatch(r'[a-z0-9_-]{3,32}', username):
                raise APIError(400, 'Username: 3–32 letters, numbers, underscores or hyphens.')
            password = field(data, 'password', 128, 8)
            if path == ['signup']:
                salt = secrets.token_hex(16)
                db.execute('INSERT INTO users VALUES (?, ?, ?)', (username, salt, password_hash(password, salt)))
            else:
                row = db.execute('SELECT * FROM users WHERE username=?', (username,)).fetchone()
                candidate = password_hash(password, row['salt'] if row else '00' * 16)
                if row is None or not hmac.compare_digest(candidate, row['password']):
                    raise APIError(401, 'Incorrect username or password.')
            token = secrets.token_urlsafe(32)
            db.execute('DELETE FROM sessions WHERE expires < ?', (time.time(),))
            db.execute('INSERT INTO sessions VALUES (?, ?, ?)', (hashlib.sha256(token.encode()).hexdigest(), username, time.time() + 604800))
            return {'token': token, 'username': username}
        token = self.headers.get('Authorization', '').removeprefix('Bearer ')
        if path in (['notification-pairings','redeem'], ['notification-events']):
            return WebAPI(db,method,path,data).creator(token)
        digest = hashlib.sha256(token.encode()).hexdigest()
        session = db.execute('SELECT username FROM sessions WHERE token=? AND expires>?', (digest, time.time())).fetchone()
        if session is None: raise APIError(401, 'Please sign in again.')
        username = session['username']
        web_result = WebAPI(db,method,path,data,parse_qs(urlsplit(self.path).query,keep_blank_values=True)).account(username,digest)
        if web_result is not None: return web_result
        if path == ['me'] and method == 'GET': return {'username': username}
        if path == ['logout'] and method == 'POST':
            db.execute('DELETE FROM sessions WHERE token=?', (digest,))
            return {'ok': True}
        if path and path[0]=='experiences': raise APIError(410, 'Native experiences are retired. Existing records are preserved; register a hosted web app instead.')
        if path == ['apps'] and method == 'GET':
            rows = db.execute('SELECT * FROM apps WHERE owner=? OR id IN (SELECT app FROM shares WHERE username=?) ORDER BY rowid DESC', (username, username)).fetchall()
            return {'apps': [self.app_json(db, row, username) for row in rows]}
        if path == ['apps'] and method == 'POST':
            name, url = field(data, 'name', 60), field(data, 'url', 2048)
            summary = field(data, 'summary', 160, 0)
            try:
                parsed = urlsplit(url)
                if parsed.scheme not in ('http', 'https') or not parsed.hostname or parsed.username or parsed.password or any(c.isspace() for c in url): raise ValueError()
                parsed.port
            except ValueError: raise APIError(400, 'Use an HTTP or HTTPS website URL without credentials.')
            app_id = secrets.token_hex(12)
            db.execute('INSERT INTO apps VALUES (?, ?, ?, ?, ?)', (app_id, username, name, url, summary))
            return self.app_json(db, db.execute('SELECT * FROM apps WHERE id=?', (app_id,)).fetchone(), username)
        if len(path) >= 2 and path[0] == 'apps':
            row = db.execute('SELECT * FROM apps WHERE id=?', (path[1],)).fetchone()
            shared = db.execute('SELECT 1 FROM shares WHERE app=? AND username=?', (path[1], username)).fetchone()
            if row is None or (row['owner'] != username and not shared): raise APIError(404, 'App unavailable.')
            if len(path) == 2 and method == 'GET': return self.app_json(db, row, username)
            if row['owner'] != username: raise APIError(403, 'Only the owner can change access.')
            if len(path) == 2 and method == 'DELETE':
                db.execute('DELETE FROM apps WHERE id=?', (path[1],))
                return {'ok': True}
            if len(path) == 3 and path[2] == 'shares' and method == 'POST':
                recipient = field(data, 'username', 32).lower()
                if not db.execute('SELECT 1 FROM users WHERE username=?', (recipient,)).fetchone(): raise APIError(404, 'That account does not exist yet.')
                if recipient == username: raise APIError(400, 'You already own this app.')
                db.execute('INSERT OR IGNORE INTO shares VALUES (?, ?)', (path[1], recipient))
                return {'ok': True}
            if len(path) == 4 and path[2] == 'shares' and method == 'DELETE':
                db.execute('DELETE FROM shares WHERE app=? AND username=?', (path[1], path[3]))
                revoke(db,path[1],path[3])
                return {'ok': True}
        raise APIError(404, 'Route not found.')

    def app_json(self, db, row, username):
        result = dict(row)
        native = db.execute('SELECT creator_key, revision FROM experiences WHERE app_id=?', (row['id'],)).fetchone()
        result['kind'] = 'native' if native else 'web'
        if native: result.update(url=None, creatorKey=native['creator_key'], revision=native['revision'], supported=False)
        web=db.execute('SELECT * FROM web_apps WHERE app_id=?',(row['id'],)).fetchone()
        if web: result.update(manifest=json.loads(web['manifest']),revision=web['revision'],creatorKey=web['creator_key'])
        result['sharedWith'] = [r[0] for r in db.execute('SELECT username FROM shares WHERE app=? ORDER BY username', (row['id'],))] if row['owner'] == username else []
        return result


def make_server(host, port, db_path):
    with sqlite3.connect(db_path) as db: migrate(db)
    server = ThreadingHTTPServer((host, port), Handler)
    server.db = str(db_path)
    return server

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--host', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8787)
    parser.add_argument('--db', default=str(Path(__file__).with_name('pocket.sqlite3')))
    args = parser.parse_args()
    server = make_server(args.host, args.port, args.db)
    from push import start_worker, delivery_mode
    stop=threading.Event(); worker=start_worker(args.db,stop)
    print('Notification adapter: '+delivery_mode()+(' (inbox only; no push delivery)' if delivery_mode()=='local' else ' (provider acceptance is not device delivery)'),flush=True)
    print(f'Pocket backend listening on {args.host}:{args.port}', flush=True)
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally: stop.set(); server.server_close(); worker.join(timeout=15)
