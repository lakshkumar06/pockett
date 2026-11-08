"""Hosted-web notification lifecycle against actual handlers/SQLite (use --http for sockets)."""
import copy
import json
import os
from pathlib import Path
import sqlite3
import time
import unittest
from unittest.mock import patch
import test_backend as harness
from push import process_pending, LocalAdapter, APNsAdapter

class WebTests(unittest.TestCase):
    setUp=harness.BackendTests.setUp; start=harness.BackendTests.start; stop=harness.BackendTests.stop
    tearDown=harness.BackendTests.tearDown; request=harness.BackendTests.request
    def prepare(self):
        a=self.request('signup','POST',{'username':'alice','password':'test-password-a'})['token']
        b=self.request('signup','POST',{'username':'bob','password':'test-password-b'})['token']
        fixture=json.loads((Path(__file__).parents[1]/'Developer/Contracts/web-v1/fixtures/flow.json').read_text())
        m=fixture['manifest']; registration=self.request('web-apps','POST',{'manifest':m},a); app=registration['appId']
        key=self.request('apps/'+app+'/notification-credential','POST',{},a)['credential']
        self.request('apps/'+app+'/shares','POST',{'username':'bob'},a)
        code=self.request('apps/'+app+'/pairings','POST',{'consent':True},b)['pairingCode']
        sid=self.request('notification-pairings/redeem','POST',{'pairingCode':code},key)['subscriptionId']
        return a,b,m,app,key,sid
    def event(self,sid,key='event-1',target='/notes/42?view=full#content'):
        return {'idempotencyKey':key,'subscriptionId':sid,'title':'Ready','body':'Open your note.','target':target}
    def test_two_accounts_events_revocation_and_updates(self):
        a,b,m,app,key,sid=self.prepare()
        self.request('notification-events','POST',self.event(sid),a,401)
        self.request('apps',token=key,status=401)
        result=self.request('notification-events','POST',self.event(sid),key)
        self.assertTrue(self.request('notification-events','POST',self.event(sid),key)['duplicate'])
        changed=self.event(sid);changed['body']='Different'
        self.request('notification-events','POST',changed,key,409)
        eid=result['eventId'];path='notification-inbox/'+eid
        self.assertEqual(self.request('notification-inbox',token=a)['entries'],[])
        self.request(path+'/launch',token=a,status=404)
        launch=self.request(path+'/launch',token=b)
        self.assertEqual(launch['url'],'https://notes.example/notes/42?view=full#content')
        self.assertEqual(launch['deepLink'],'pocket://app/'+app+'?event='+eid)
        self.request(path+'/read','POST',{},b)
        self.assertEqual(self.request('notification-inbox',token=b)['unreadCount'],0)
        self.request('notification-subscriptions/'+sid+'/preferences','POST',{'notificationsEnabled':False},b)
        self.request('notification-events','POST',self.event(sid,'new'),key,409)
        self.assertTrue(self.request('notification-events','POST',self.event(sid),key)['duplicate'])
        self.request('notification-subscriptions/'+sid+'/preferences','POST',{'notificationsEnabled':True},b)
        m['version']='2';m['entryURL']='https://notes.example/new'
        update=self.request('web-apps','POST',{'manifest':m},a)
        self.assertEqual(update['appId'],app);self.assertEqual(update['revision'],2)
        self.assertEqual(self.request(path+'/launch',token=b)['url'],launch['url'])
        self.request('apps/'+app+'/shares/bob','DELETE',token=a)
        self.request('notification-events','POST',self.event(sid,'revoked'),key,404)
        self.request(path+'/launch',token=b,status=404)
        self.assertEqual(self.request('notification-inbox',token=b)['entries'],[])
    def test_pairing_consent_expiry_scope_and_rotation(self):
        a,b,m,app,key,sid=self.prepare()
        self.request('apps/'+app+'/pairings','POST',{'consent':False},b,400)
        code=self.request('apps/'+app+'/pairings','POST',{'consent':True},b)['pairingCode']
        self.request('notification-pairings/redeem','POST',{'pairingCode':code},b,401)
        m['creatorKey']='other';other=self.request('web-apps','POST',{'manifest':m},a)['appId']
        otherkey=self.request('apps/'+other+'/notification-credential','POST',{},a)['credential']
        self.request('notification-pairings/redeem','POST',{'pairingCode':code},otherkey,404)
        self.request('notification-pairings/redeem','POST',{'pairingCode':code},key)
        self.request('notification-pairings/redeem','POST',{'pairingCode':code},key,404)
        self.request('notification-events','POST',self.event(sid),key,404) # re-pair revoked old subscription
        code=self.request('apps/'+app+'/pairings','POST',{'consent':True},b)['pairingCode']
        with sqlite3.connect(self.db) as db: db.execute('UPDATE pairings SET expires=0')
        self.request('notification-pairings/redeem','POST',{'pairingCode':code},key,404)
        code=self.request('apps/'+app+'/pairings','POST',{'consent':True},b)['pairingCode']
        newkey=self.request('apps/'+app+'/notification-credential','POST',{},a)['credential']
        self.request('notification-pairings/redeem','POST',{'pairingCode':code},key,401)
        self.request('notification-pairings/redeem','POST',{'pairingCode':code},newkey,404)
        self.request('apps/'+app+'/notification-credential','DELETE',token=a)
        self.request('notification-events','POST',self.event(sid),newkey,401)
    def test_shared_fixtures_unsafe_targets_and_origin_change(self):
        a,b,m,app,key,sid=self.prepare()
        targets=json.loads((Path(__file__).parents[1]/'Developer/Contracts/web-v1/fixtures/targets.json').read_text())
        for i,t in enumerate(targets['invalid'] + ['/a%3f/../escape', '/%E2%80%A8hidden']): self.request('notification-events','POST',self.event(sid,'bad-'+str(i),t),key,400)
        for i,t in enumerate(targets['valid']): self.request('notification-events','POST',self.event(sid,'good-'+str(i),t),key)
        for bad in [dict(m,script='code'),dict(m,entryURL='javascript:evil'),dict(m,entryURL='https://user:pass@notes.example')]: self.request('web-apps','POST',{'manifest':bad},a,400)
        m['entryURL']='https://new.example/app'
        self.request('web-apps','POST',{'manifest':m},a)
        self.request('notification-events','POST',self.event(sid),key,401)
        self.assertEqual(self.request('notification-inbox',token=b)['entries'],[])
        self.assertEqual(self.request('notification-subscriptions',token=b)['subscriptions'],[])
    def test_pagination_rate_retention_and_idempotency(self):
        a,b,m,app,key,sid=self.prepare()
        ids=[]
        for i in range(20): ids.append(self.request('notification-events','POST',self.event(sid,'event-'+str(i)),key)['eventId'])
        self.request('notification-events','POST',self.event(sid,'over-limit'),key,429)
        self.assertTrue(self.request('notification-events','POST',self.event(sid,'event-0'),key)['duplicate'])
        page=self.request('notification-inbox?limit=7&appId='+app,token=b)
        self.assertEqual(len(page['entries']),7);self.assertEqual(page['unreadCount'],20)
        self.assertEqual([e['eventId'] for e in page['entries']],list(reversed(ids))[:7])
        other=self.request('notification-inbox?before='+page['nextCursor']+'&limit=7',token=b)
        self.assertFalse(set(e['eventId'] for e in other['entries']) & set(e['eventId'] for e in page['entries']))
        self.request('notification-inbox?before='+page['nextCursor'],token=a,status=400)
        self.request('notification-inbox?limit=101',token=b,status=400)
        with sqlite3.connect(self.db) as db:
            db.execute('DELETE FROM inbox WHERE event_id=?',(ids[0],))
        self.assertTrue(self.request('notification-events','POST',self.event(sid,'event-0'),key)['duplicate'])
        with sqlite3.connect(self.db) as db: db.execute('UPDATE notification_events SET created=?',(time.time()-31*86400,))
        self.assertEqual(self.request('notification-inbox',token=b)['entries'],[])
    def test_inbox_cap_preserves_idempotency_and_revocation_cancels_delivery(self):
        a,b,m,app,key,sid=self.prepare()
        device={'deviceId':'550e8400-e29b-41d4-a716-446655440000','token':'b'*64,'environment':'sandbox'}
        self.request('notification-devices','POST',device,b)
        first=self.request('notification-events','POST',self.event(sid),key)['eventId']
        # Seed history directly to exercise the retention boundary without bypassing API rate tests.
        with sqlite3.connect(self.db) as db:
            for i in range(999):
                eid='seed-'+str(i)
                payload=json.dumps(self.event(sid,eid),sort_keys=True,separators=(',',':'))
                db.execute('INSERT INTO notification_events VALUES (?,?,?,?,?,?)',(eid,app,sid,eid,payload,time.time()))
                db.execute('INSERT INTO inbox(event_id,username) VALUES (?,?)',(eid,'bob'))
        newest=self.request('notification-events','POST',self.event(sid,'latest'),key)['eventId']
        with sqlite3.connect(self.db) as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM inbox').fetchone()[0],1000)
            self.assertIsNone(db.execute('SELECT 1 FROM inbox WHERE event_id=?',(first,)).fetchone())
        self.assertTrue(self.request('notification-events','POST',self.event(sid),key)['duplicate'])
        self.request('notification-inbox/'+first+'/launch',token=b,status=404)
        sent=[]
        class Recorder:
            def send(self,device,event): sent.append(event['id']); return 'local-only'
        process_pending(self.db,Recorder())
        self.assertEqual(sent,[newest]) # pruned history is not sent later
        self.request('notification-events','POST',self.event(sid,'queued'),key)
        self.request('apps/'+app+'/shares/bob','DELETE',token=a)
        process_pending(self.db,Recorder())
        self.assertEqual(sent,[newest])
        self.assertEqual(self.request('notification-inbox',token=b)['entries'],[])
    def test_devices_logout_and_local_adapter(self):
        a,b,m,app,key,sid=self.prepare()
        device={'deviceId':'550e8400-e29b-41d4-a716-446655440000','token':'a'*64,'environment':'sandbox'}
        with patch.dict(os.environ,{'POCKET_PUSH_ADAPTER':'local'}):
            self.assertEqual(self.request('notification-devices','POST',device,b),{'ok':True,'deliveryMode':'local'})
        self.request('notification-events','POST',self.event(sid),key)
        process_pending(self.db,LocalAdapter())
        with sqlite3.connect(self.db) as db: self.assertEqual(db.execute('SELECT status FROM delivery_outbox').fetchone()[0],'local-only')
        self.request('notification-events','POST',self.event(sid,'second'),key)
        self.request('notification-devices','POST',device,a) # same installation transferred; old queued sends cascade away
        with sqlite3.connect(self.db) as db:
            self.assertEqual(db.execute('SELECT COUNT(*) FROM delivery_outbox').fetchone()[0],0)
            self.assertEqual(db.execute('SELECT username FROM notification_devices').fetchone()[0],'alice')
        self.request('logout','POST',{},a)
        with sqlite3.connect(self.db) as db: self.assertEqual(db.execute('SELECT COUNT(*) FROM notification_devices').fetchone()[0],0)
        with patch.dict(os.environ,{},clear=True): self.assertEqual(APNsAdapter().send(device,{'id':'event','app_id':app}),'configuration-error')
    def test_migration_from_native_database(self):
        old=Path(self.temp.name)/'old.sqlite3'
        original=harness.server.MIGRATIONS
        try:
            harness.server.MIGRATIONS=original[:2]
            with sqlite3.connect(old) as db:
                harness.server.migrate(db)
                db.execute("INSERT INTO users VALUES ('old','salt','hash')")
                db.execute("INSERT INTO apps VALUES ('old-web','old','Existing','https://example.com','')")
                db.execute("INSERT INTO apps VALUES ('old-native','old','Native','','')")
                db.execute("INSERT INTO experiences VALUES ('old-native','old','old-key',1,'{}',NULL)")
                db.execute("INSERT INTO experience_snapshots VALUES ('old-native',1,'{}')")
                db.execute("INSERT INTO sessions VALUES ('hash','old',9999999999)")
                db.execute("INSERT INTO shares VALUES ('old-web','old')")
        finally: harness.server.MIGRATIONS=original
        with sqlite3.connect(old) as db:
            harness.server.migrate(db);harness.server.migrate(db)
            for table,count in [('apps',2),('experience_snapshots',1),('sessions',1),('shares',1)]: self.assertEqual(db.execute('SELECT COUNT(*) FROM '+table).fetchone()[0],count)

if __name__=='__main__': unittest.main()
