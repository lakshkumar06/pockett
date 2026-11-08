"""Metadata-only hosted web registration, opt-in notification inbox and delivery outbox."""
import hashlib
import json
import re
import secrets
import time
import uuid
from pathlib import Path
from urllib.parse import urlsplit, unquote
from validation import validate_schema

class APIError(Exception):
    def __init__(self, status, message): self.status, self.message = status, message

MIGRATION_WEB = (
    'CREATE TABLE web_apps(app_id TEXT PRIMARY KEY REFERENCES apps(id) ON DELETE CASCADE, owner TEXT NOT NULL, creator_key TEXT NOT NULL, revision INTEGER NOT NULL, manifest TEXT NOT NULL, origin TEXT NOT NULL, UNIQUE(owner,creator_key))',
    'CREATE TABLE creator_credentials(app_id TEXT PRIMARY KEY REFERENCES apps(id) ON DELETE CASCADE, digest TEXT UNIQUE NOT NULL)',
    'CREATE TABLE pairings(digest TEXT PRIMARY KEY, app_id TEXT NOT NULL REFERENCES apps(id) ON DELETE CASCADE, username TEXT NOT NULL REFERENCES users(username), expires REAL NOT NULL)',
    'CREATE TABLE subscriptions(id TEXT PRIMARY KEY, app_id TEXT NOT NULL REFERENCES apps(id) ON DELETE CASCADE, username TEXT NOT NULL REFERENCES users(username), enabled INTEGER NOT NULL DEFAULT 1, UNIQUE(app_id,username))',
    'CREATE TABLE notification_events(id TEXT PRIMARY KEY, app_id TEXT NOT NULL REFERENCES apps(id) ON DELETE CASCADE, subscription_id TEXT NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE, idempotency_key TEXT NOT NULL, payload TEXT NOT NULL, created REAL NOT NULL, UNIQUE(app_id,idempotency_key))',
    'CREATE TABLE inbox(seq INTEGER PRIMARY KEY AUTOINCREMENT, event_id TEXT UNIQUE NOT NULL REFERENCES notification_events(id) ON DELETE CASCADE, username TEXT NOT NULL REFERENCES users(username), read INTEGER NOT NULL DEFAULT 0)',
    'CREATE INDEX inbox_account ON inbox(username,seq DESC)',
    'CREATE TABLE notification_devices(id TEXT PRIMARY KEY, username TEXT NOT NULL REFERENCES users(username), session_digest TEXT NOT NULL REFERENCES sessions(token) ON DELETE CASCADE, token TEXT NOT NULL UNIQUE, environment TEXT NOT NULL, updated REAL NOT NULL)',
    'CREATE TABLE delivery_outbox(event_id TEXT NOT NULL REFERENCES notification_events(id) ON DELETE CASCADE, device_id TEXT NOT NULL REFERENCES notification_devices(id) ON DELETE CASCADE, attempts INTEGER NOT NULL DEFAULT 0, next_attempt REAL NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT "pending", PRIMARY KEY(event_id,device_id))',
    'CREATE TABLE rate_limits(bucket TEXT NOT NULL, window INTEGER NOT NULL, count INTEGER NOT NULL, PRIMARY KEY(bucket,window))',
)

def digest(value): return hashlib.sha256(value.encode()).hexdigest()
def exact(data, required, optional=()):
    if not isinstance(data, dict) or set(data)-set(required)-set(optional) or set(required)-set(data): raise APIError(400, 'Invalid request fields.')
def text(data, key, maximum):
    value = data.get(key)
    if not isinstance(value, str) or not value.strip() or len(value)>maximum or any(ord(c)<32 or ord(c)==127 for c in value): raise APIError(400, 'Invalid '+key+'.')
    return value

def origin(value, strict=False, icon=False):
    if not isinstance(value,str) or len(value)>2048 or re.search(r'[\s\\\x00-\x1f\x7f]',value): raise APIError(400,'Invalid website URL.')
    try:
        u=urlsplit(value)
        if u.scheme not in ('http','https') or not u.hostname or u.username is not None or u.password is not None: raise ValueError()
        if strict and u.scheme=='http' and u.hostname not in ('localhost','127.0.0.1','::1'): raise ValueError()
        if icon and u.fragment: raise ValueError()
        host=u.hostname.lower()
        host='['+host+']' if ':' in host else host
        port=u.port
        return u.scheme+'://'+host+((':'+str(port)) if port and port != (443 if u.scheme=='https' else 80) else '')
    except ValueError: raise APIError(400,'Use an HTTPS URL without credentials (HTTP loopback for development).')

def target(value):
    if not isinstance(value,str) or not 1<=len(value)<=2048 or not value.startswith('/') or value.startswith('//') or re.search(r'[\s\\\x00-\x1f\x7f]',value): raise APIError(400,'Invalid notification target.')
    if re.search(r'%(?![0-9a-fA-F]{2})|%(?:0[0-9a-f]|1[0-9a-f]|20|7f|5c|2f|25)',value,re.I): raise APIError(400,'Unsafe encoded target.')
    decoded=unquote(value)
    if any(c.isspace() or ord(c)<32 or ord(c)==127 for c in decoded): raise APIError(400,'Unsafe decoded target.')
    if any(x in ('.','..') for x in unquote(urlsplit(value).path).split('/')): raise APIError(400,'Unsafe target path.')
    return value

def manifest(value):
    try:
        if len(json.dumps(value,ensure_ascii=False,separators=(',',':'),allow_nan=False).encode())>8192: raise ValueError()
        schema=json.loads((Path(__file__).parents[1]/'Developer/Contracts/web-v1/manifest.schema.json').read_text())
        validate_schema(value,schema)
        for key in ('name','summary','version'): text(value,key,{'name':60,'summary':160,'version':32}[key])
        origin(value['entryURL'],True); origin(value['iconURL'],True,True)
    except (ValueError,TypeError,RecursionError): raise APIError(400,'Invalid web manifest.')
    return value

def access(db, app_id, user):
    row=db.execute('SELECT * FROM apps WHERE id=? AND (owner=? OR id IN (SELECT app FROM shares WHERE username=?))',(app_id,user,user)).fetchone()
    if row is None: raise APIError(404,'App unavailable.')
    return row

def cleanup(db):
    now=time.time()
    db.execute('DELETE FROM pairings WHERE expires<=?',(now,))
    db.execute('DELETE FROM notification_events WHERE created<?',(now-30*86400,))
    db.execute('DELETE FROM rate_limits WHERE window<?',(int(now)-7200,))
    db.execute('DELETE FROM notification_devices WHERE updated<?',(now-90*86400,))
    db.execute('DELETE FROM subscriptions WHERE NOT EXISTS (SELECT 1 FROM apps WHERE apps.id=subscriptions.app_id AND (apps.owner=subscriptions.username OR EXISTS (SELECT 1 FROM shares WHERE shares.app=apps.id AND shares.username=subscriptions.username)))')

def rate(db,bucket,limit,seconds=60):
    window=int(time.time())//seconds*seconds
    row=db.execute('SELECT count FROM rate_limits WHERE bucket=? AND window=?',(bucket,window)).fetchone()
    if row and row[0]>=limit: raise APIError(429,'Too many requests. Try again later.')
    db.execute('INSERT INTO rate_limits VALUES (?,?,1) ON CONFLICT(bucket,window) DO UPDATE SET count=count+1',(bucket,window))

def revoke(db,app_id,user=None):
    for table in ('pairings','subscriptions'):
        db.execute('DELETE FROM '+table+' WHERE app_id=?'+(' AND username=?' if user else ''),(app_id,user) if user else (app_id,))
    if user is None: db.execute('DELETE FROM creator_credentials WHERE app_id=?',(app_id,))

def subscription_json(row): return {'subscriptionId':row['id'],'appId':row['app_id'],'notificationsEnabled':bool(row['enabled'])}

class WebAPI:
    def __init__(self,db,method,path,data,query=None): self.db,self.method,self.path,self.data,self.query=db,method,path,data,query or {}
    def creator(self,credential):
        db,p,d=self.db,self.path,self.data
        row=db.execute('SELECT app_id FROM creator_credentials WHERE digest=?',(digest(credential),)).fetchone()
        if row is None: raise APIError(401,'Invalid app credential.')
        app=row['app_id']
        if p==['notification-pairings','redeem'] and self.method=='POST':
            exact(d,['pairingCode']); code=text(d,'pairingCode',128)
            pair=db.execute('SELECT * FROM pairings WHERE digest=? AND app_id=? AND expires>?',(digest(code),app,time.time())).fetchone()
            if pair is None: raise APIError(404,'Pairing unavailable or expired.')
            access(db,app,pair['username'])
            db.execute('DELETE FROM subscriptions WHERE app_id=? AND username=?',(app,pair['username']))
            sid=secrets.token_hex(16)
            db.execute('INSERT INTO subscriptions VALUES (?,?,?,1)',(sid,app,pair['username']))
            db.execute('DELETE FROM pairings WHERE digest=?',(pair['digest'],))
            return {'subscriptionId':sid,'appId':app,'notificationsEnabled':True}
        if p==['notification-events'] and self.method=='POST':
            exact(d,['idempotencyKey','subscriptionId','title','body','target'])
            key=text(d,'idempotencyKey',64); sid=text(d,'subscriptionId',128)
            if not re.fullmatch(r'[A-Za-z0-9_-]+',key) or not re.fullmatch(r'[A-Za-z0-9_-]+',sid): raise APIError(400,'Invalid identifier.')
            text(d,'title',80);text(d,'body',240);target(d['target'])
            sub=db.execute('SELECT * FROM subscriptions WHERE id=? AND app_id=?',(sid,app)).fetchone()
            if sub is None: raise APIError(404,'Subscription unavailable.')
            access(db,app,sub['username'])
            payload=json.dumps(d,sort_keys=True,separators=(',',':'),ensure_ascii=False)
            prior=db.execute('SELECT id,payload FROM notification_events WHERE app_id=? AND idempotency_key=?',(app,key)).fetchone()
            if prior:
                if prior['payload']!=payload: raise APIError(409,'Idempotency key already used with different content.')
                return {'eventId':prior['id'],'duplicate':True}
            if not sub['enabled']: raise APIError(409,'Notifications disabled.')
            rate(db,'events:'+app,60);rate(db,'subscription:'+sid,20)
            eid=secrets.token_hex(16)
            db.execute('INSERT INTO notification_events VALUES (?,?,?,?,?,?)',(eid,app,sid,key,payload,time.time()))
            db.execute('INSERT INTO inbox(event_id,username) VALUES (?,?)',(eid,sub['username']))
            db.execute('DELETE FROM inbox WHERE username=? AND seq NOT IN (SELECT seq FROM inbox WHERE username=? ORDER BY seq DESC LIMIT 1000)',(sub['username'],sub['username']))
            db.execute('INSERT INTO delivery_outbox(event_id,device_id) SELECT ?,id FROM notification_devices WHERE username=?',(eid,sub['username']))
            return {'eventId':eid,'duplicate':False}
        raise APIError(404,'Route not found.')

    def account(self,user,session_digest):
        db,p,d,method=self.db,self.path,self.data,self.method
        if p==['web-apps'] and method=='POST':
            exact(d,['manifest']); m=manifest(d['manifest']); new_origin=origin(m['entryURL'])
            old=db.execute('SELECT * FROM web_apps WHERE owner=? AND creator_key=?',(user,m['creatorKey'])).fetchone()
            aid,revision=(old['app_id'],old['revision']+1) if old else (secrets.token_hex(12),1)
            encoded=json.dumps(m,ensure_ascii=False,separators=(',',':'))
            if old:
                if old['origin']!=new_origin: revoke(db,aid)
                db.execute('UPDATE apps SET name=?,url=?,summary=? WHERE id=?',(m['name'],m['entryURL'],m['summary'],aid))
                db.execute('UPDATE web_apps SET revision=?,manifest=?,origin=? WHERE app_id=?',(revision,encoded,new_origin,aid))
            else:
                db.execute('INSERT INTO apps VALUES (?,?,?,?,?)',(aid,user,m['name'],m['entryURL'],m['summary']))
                db.execute('INSERT INTO web_apps VALUES (?,?,?,?,?,?)',(aid,user,m['creatorKey'],revision,encoded,new_origin))
            return {'appId':aid,'revision':revision,'deepLink':'pocket://app/'+aid}
        if len(p)==2 and p[0]=='web-apps' and method=='GET':
            access(db,p[1],user)
            row=db.execute('SELECT * FROM web_apps WHERE app_id=?',(p[1],)).fetchone()
            if row is None: raise APIError(404,'Web registration unavailable.')
            return {'appId':p[1],'revision':row['revision'],'manifest':json.loads(row['manifest'])}
        if len(p)==3 and p[0]=='apps' and p[2] in ('notification-credential','pairings') and method=='POST':
            listing=access(db,p[1],user)
            if not db.execute('SELECT 1 FROM web_apps WHERE app_id=?',(p[1],)).fetchone(): raise APIError(404,'This listing has no notification integration.')
            if p[2]=='notification-credential':
                exact(d,[])
                if listing['owner']!=user: raise APIError(403,'Only the owner can issue credentials.')
                rate(db,'credential:'+p[1],10,3600)
                db.execute('DELETE FROM pairings WHERE app_id=?',(p[1],))
                credential=secrets.token_urlsafe(32)
                db.execute('INSERT INTO creator_credentials VALUES (?,?) ON CONFLICT(app_id) DO UPDATE SET digest=excluded.digest',(p[1],digest(credential)))
                return {'appId':p[1],'credential':credential}
            exact(d,['consent'])
            if d['consent'] is not True: raise APIError(400,'Explicit consent is required.')
            rate(db,'pairing:'+user+':'+p[1],5)
            code=secrets.token_urlsafe(24); expires=int(time.time())+300
            db.execute('DELETE FROM pairings WHERE app_id=? AND username=?',(p[1],user))
            db.execute('INSERT INTO pairings VALUES (?,?,?,?)',(digest(code),p[1],user,expires))
            return {'pairingCode':code,'expiresAt':expires}
        if p==['notification-subscriptions'] and method=='GET':
            return {'subscriptions':[subscription_json(r) for r in db.execute('SELECT * FROM subscriptions WHERE username=? ORDER BY id',(user,))]}
        if len(p)>=2 and p[0]=='notification-subscriptions':
            sub=db.execute('SELECT * FROM subscriptions WHERE id=? AND username=?',(p[1],user)).fetchone()
            if sub is None: raise APIError(404,'Subscription unavailable.')
            access(db,sub['app_id'],user)
            if len(p)==2 and method=='DELETE':
                revoke(db,sub['app_id'],user);return {'ok':True}
            if len(p)==3 and p[2]=='preferences' and method=='POST':
                exact(d,['notificationsEnabled'])
                if type(d['notificationsEnabled']) is not bool: raise APIError(400,'Expected a notification preference.')
                db.execute('UPDATE subscriptions SET enabled=? WHERE id=?',(int(d['notificationsEnabled']),p[1]))
                if not d['notificationsEnabled']: db.execute('DELETE FROM delivery_outbox WHERE event_id IN (SELECT id FROM notification_events WHERE subscription_id=?)',(p[1],))
                return {'subscriptionId':p[1],'appId':sub['app_id'],'notificationsEnabled':d['notificationsEnabled']}
        if len(p)==3 and p[0]=='apps' and p[2]=='notification-credential' and method=='DELETE':
            if access(db,p[1],user)['owner']!=user: raise APIError(403,'Only the owner can revoke credentials.')
            db.execute('DELETE FROM creator_credentials WHERE app_id=?',(p[1],));db.execute('DELETE FROM pairings WHERE app_id=?',(p[1],))
            return {'ok':True}
        if p==['notification-inbox'] and method=='GET':
            if set(self.query)-{'limit','before','appId'} or any(len(v)!=1 for v in self.query.values()): raise APIError(400,'Invalid pagination.')
            try: limit=int(self.query.get('limit',['100'])[0])
            except ValueError: raise APIError(400,'Invalid page size.')
            if not 1<=limit<=100: raise APIError(400,'Page size must be 1–100.')
            where='i.username=?'; args=[user]
            if 'before' in self.query:
                cursor=db.execute('SELECT seq FROM inbox WHERE event_id=? AND username=?',(self.query['before'][0],user)).fetchone()
                if cursor is None: raise APIError(400,'Invalid cursor.')
                where+=' AND i.seq<?';args.append(cursor['seq'])
            if 'appId' in self.query: where+=' AND e.app_id=?';args.append(self.query['appId'][0])
            rows=db.execute('SELECT i.read,e.* FROM inbox i JOIN notification_events e ON e.id=i.event_id WHERE '+where+' ORDER BY i.seq DESC LIMIT ?',args+[limit+1]).fetchall()
            entries=[]
            for r in rows[:limit]:
                payload=json.loads(r['payload'])
                entries.append({'eventId':r['id'],'appId':r['app_id'],'title':payload['title'],'body':payload['body'],'target':payload['target'],'createdAt':r['created'],'read':bool(r['read'])})
            unread=db.execute('SELECT COUNT(*) FROM inbox WHERE username=? AND read=0',(user,)).fetchone()[0]
            return {'entries':entries,'nextCursor':entries[-1]['eventId'] if len(rows)>limit else None,'unreadCount':unread}
        if len(p)==3 and p[0]=='notification-inbox':
            row=db.execute('SELECT e.*,s.app_id AS app,s.username FROM inbox i JOIN notification_events e ON e.id=i.event_id JOIN subscriptions s ON s.id=e.subscription_id WHERE i.username=? AND e.id=?',(user,p[1])).fetchone()
            if row is None: raise APIError(404,'Notification unavailable.')
            access(db,row['app'],user)
            if p[2]=='read' and method=='POST':
                exact(d,[]);db.execute('UPDATE inbox SET read=1 WHERE event_id=?',(p[1],));return {'ok':True}
            if p[2]=='launch' and method=='GET':
                web=db.execute('SELECT origin FROM web_apps WHERE app_id=?',(row['app'],)).fetchone()
                if web is None: raise APIError(404,'App unavailable.')
                t=target(json.loads(row['payload'])['target'])
                return {'appId':row['app'],'target':t,'url':web['origin']+t,'deepLink':'pocket://app/'+row['app']+'?event='+row['id']}
        if p==['notification-devices'] and method=='POST':
            exact(d,['deviceId','token','environment'])
            try: device_id=str(uuid.UUID(d['deviceId']))
            except (ValueError,TypeError,AttributeError): raise APIError(400,'Invalid device ID.')
            if not isinstance(d['token'],str) or not re.fullmatch(r'[0-9a-fA-F]{64,512}',d['token']) or d['environment'] not in ('sandbox','production'): raise APIError(400,'Invalid device registration.')
            rate(db,'device:'+user,30)
            db.execute('DELETE FROM notification_devices WHERE id=? OR token=?',(device_id,d['token'].lower()))
            db.execute('INSERT INTO notification_devices VALUES (?,?,?,?,?,?)',(device_id,user,session_digest,d['token'].lower(),d['environment'],time.time()))
            # Limit device metadata to ten active registrations per account.
            db.execute('DELETE FROM notification_devices WHERE username=? AND id NOT IN (SELECT id FROM notification_devices WHERE username=? ORDER BY updated DESC LIMIT 10)',(user,user))
            from push import delivery_mode
            return {'ok':True,'deliveryMode':delivery_mode()}
        if len(p)==2 and p[0]=='notification-devices' and method=='DELETE':
            db.execute('DELETE FROM notification_devices WHERE id=? AND username=?',(p[1],user));return {'ok':True}
        return None
