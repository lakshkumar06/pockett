"""Exercise request handlers and SQLite. Add --http to test through a real socket."""
import importlib.util
import io
import sqlite3
import sys
from types import SimpleNamespace
import json
from pathlib import Path
import tempfile
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen

spec = importlib.util.spec_from_file_location('server', Path(__file__).parents[1] / 'Backend/server.py')
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)

LIVE_HTTP = "--http" in sys.argv
if LIVE_HTTP: sys.argv.remove("--http")

class BackendTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.db = Path(self.temp.name) / 'test.sqlite3'
        self.start()

    def start(self):
        if not LIVE_HTTP:
            with sqlite3.connect(self.db) as db: server.migrate(db)
            return
        self.server = server.make_server('127.0.0.1', 0, self.db)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base = f'http://127.0.0.1:{self.server.server_port}'

    def stop(self):
        if not LIVE_HTTP: return
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def tearDown(self):
        self.stop()
        self.temp.cleanup()

    def request(self, path, method='GET', body=None, token=None, status=200):
        headers = {'Content-Type': 'application/json'}
        if token: headers['Authorization'] = 'Bearer ' + token
        if not LIVE_HTTP:
            payload = json.dumps(body).encode() if body is not None else b''
            headers['Content-Length'] = str(len(payload))
            handler = object.__new__(server.Handler)
            handler.server = SimpleNamespace(db=str(self.db))
            handler.command, handler.path, handler.headers = method, '/' + path, headers
            handler.rfile, handler.wfile = io.BytesIO(payload), io.BytesIO()
            codes = []
            handler.send_response = codes.append
            handler.send_header = lambda *args: None
            handler.end_headers = lambda: None
            handler.handle_api()
            data = json.loads(handler.wfile.getvalue())
            self.assertEqual(codes[0], status, data)
            return data
        req = Request(self.base + '/' + path, method=method, headers=headers, data=json.dumps(body).encode() if body is not None else None)
        try:
            with urlopen(req) as response: code, data = response.status, json.load(response)
        except HTTPError as error: code, data = error.code, json.load(error)
        self.assertEqual(code, status, data)
        return data

    def test_two_accounts(self):
        a = self.request('signup', 'POST', {'username': 'alice', 'password': 'test-password-a'})['token']
        b = self.request('signup', 'POST', {'username': 'bob', 'password': 'test-password-b'})['token']
        self.request('signup', 'POST', {'username': 'ALICE', 'password': 'test-password-a'}, status=409)
        self.request('login', 'POST', {'username': 'alice', 'password': 'wrong-password'}, status=401)
        self.request('apps', status=401)
        self.request('apps', 'POST', {'name': 'Bad', 'url': 'javascript:alert(1)', 'summary': ''}, a, 400)
        for url in ['file:///tmp/index.html', 'ftp://example.com', 'http://user:password@example.com', 'not-a-url']:
            self.request('apps', 'POST', {'name': 'Bad', 'url': url, 'summary': ''}, a, 400)
        app = self.request('apps', 'POST', {'name': 'Test app', 'url': 'http://test-mac.local:8080', 'summary': 'Shared test'}, a)
        path = 'apps/' + app['id']
        self.assertEqual(self.request('apps', token=b)['apps'], [])
        self.request(path, token=b, status=404)
        self.request(path + '/shares', 'POST', {'username': 'missing'}, a, 404)
        self.request(path + '/shares', 'POST', {'username': 'bob'}, a)
        self.request(path + '/shares', 'POST', {'username': 'bob'}, a)
        self.assertEqual(len(self.request('apps', token=b)['apps']), 1)
        self.assertEqual(self.request(path, token=b)['url'], 'http://test-mac.local:8080')
        self.request(path + '/shares', 'POST', {'username': 'alice'}, b, 403)
        self.request(path, 'DELETE', token=b, status=403)
        self.stop(); self.start()
        self.assertEqual(self.request('me', token=a)['username'], 'alice')
        self.assertEqual(len(self.request('apps', token=b)['apps']), 1)
        self.request(path + '/shares/bob', 'DELETE', token=a)
        self.assertEqual(self.request('apps', token=b)['apps'], [])
        self.request(path, token=b, status=404)
        self.request('logout', 'POST', {}, b)
        self.request('apps', token=b, status=401)
        self.request('login', 'POST', {'username': 'bob', 'password': 'test-password-b'})
        self.request(path, 'DELETE', token=a)
        self.assertEqual(self.request('apps', token=a)['apps'], [])

    def test_native_retirement_preserves_records(self):
        token = self.request('signup', 'POST', {'username': 'alice', 'password': 'test-password-a'})['token']
        config = json.loads((Path(__file__).parents[1] / 'Developer/Contracts/fixtures/valid/morning-walk.json').read_text())
        with sqlite3.connect(self.db) as db:
            db.execute("INSERT INTO apps VALUES ('native-old','alice','Walk','','Old native record')")
            db.execute("INSERT INTO experiences VALUES ('native-old','alice','morning-walk',1,?,NULL)", (json.dumps(config),))
            db.execute("INSERT INTO experience_snapshots VALUES ('native-old',1,?)", (json.dumps(config),))
        self.stop(); self.start()
        self.request('experiences', 'POST', {'configuration': config}, token, 410)
        self.request('experiences/native-old', token=token, status=410)
        listing = self.request('apps/native-old', token=token)
        self.assertEqual(listing['kind'], 'native'); self.assertFalse(listing['supported'])
        with sqlite3.connect(self.db) as db:
            self.assertEqual(json.loads(db.execute('SELECT configuration FROM experience_snapshots').fetchone()[0]), config)

    def test_migration_preserves_legacy(self):
        legacy = Path(self.temp.name) / 'legacy.sqlite3'
        with sqlite3.connect(legacy) as db:
            db.executescript(server.SCHEMA)
            db.execute("INSERT INTO users VALUES ('legacy', 'salt', 'hash')")
            db.execute("INSERT INTO sessions VALUES ('session', 'legacy', 9999999999)")
            db.execute("INSERT INTO apps VALUES ('old', 'legacy', 'Original', 'https://example.com', '')")
            db.execute("INSERT INTO shares VALUES ('old', 'legacy')")
            db.commit()
            server.migrate(db); server.migrate(db)
            self.assertEqual(db.execute('SELECT COUNT(*) FROM schema_migrations').fetchone()[0], 3)
            self.assertEqual(db.execute('SELECT url FROM apps').fetchone()[0], 'https://example.com')
            self.assertEqual(db.execute('SELECT COUNT(*) FROM sessions').fetchone()[0], 1)
            self.assertEqual(db.execute('SELECT COUNT(*) FROM shares').fetchone()[0], 1)
            original = server.MIGRATIONS
            try:
                server.MIGRATIONS = original + [(4, ('CREATE TABLE rollback_probe(id INTEGER)', 'INVALID SQL'))]
                with self.assertRaises(sqlite3.OperationalError): server.migrate(db)
                self.assertIsNone(db.execute("SELECT name FROM sqlite_master WHERE name='rollback_probe'").fetchone())
                self.assertEqual(db.execute('SELECT COUNT(*) FROM schema_migrations').fetchone()[0], 3)
            finally: server.MIGRATIONS = original

if __name__ == '__main__': unittest.main()
