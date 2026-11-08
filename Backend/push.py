"""Optional APNs transport. No tokens, payloads, or secret material are logged.
Default local adapter records local-only handling, never simulated device delivery.
Uses system curl HTTP/2 and openssl; Python server remains standard library only.
"""
import base64
import json
import os
import re
import sqlite3
import subprocess
import threading
import time
from pathlib import Path

def delivery_mode():
    return 'apns' if os.environ.get('POCKET_PUSH_ADAPTER','local')=='apns' else 'local'

def b64(value): return base64.urlsafe_b64encode(value).rstrip(b'=').decode()

def provider_token():
    key_id=os.environ['APNS_KEY_ID']; team=os.environ['APNS_TEAM_ID']; key=os.environ['APNS_PRIVATE_KEY_PATH']
    if not re.fullmatch(r'[A-Za-z0-9]{10}',key_id) or not re.fullmatch(r'[A-Za-z0-9]{10}',team): raise ValueError('Invalid APNs configuration')
    header=b64(json.dumps({'alg':'ES256','kid':key_id},separators=(',',':')).encode())
    claims=b64(json.dumps({'iss':team,'iat':int(time.time())},separators=(',',':')).encode())
    message=(header+'.'+claims).encode()
    signed=subprocess.run(['openssl','dgst','-sha256','-sign',key],input=message,capture_output=True,timeout=5,check=True).stdout
    # DER ECDSA sequence of two positive integers -> JOSE fixed-width r||s.
    if len(signed)<8 or signed[0]!=48 or signed[2]!=2: raise ValueError('Invalid signing response')
    rlen=signed[3];r=signed[4:4+rlen];offset=4+rlen
    if signed[offset]!=2: raise ValueError('Invalid signing response')
    slen=signed[offset+1];s=signed[offset+2:offset+2+slen]
    r=r.lstrip(b'\0');s=s.lstrip(b'\0')
    if len(r)>32 or len(s)>32: raise ValueError('Invalid signing response')
    return message.decode()+'.'+b64(r.rjust(32,b'\0')+s.rjust(32,b'\0'))

class LocalAdapter:
    def send(self,device,event): return 'local-only'

class APNsAdapter:
    def send(self,device,event):
        try:
            topic=os.environ['APNS_TOPIC']
            if not re.fullmatch(r'[A-Za-z0-9.-]{1,255}',topic): return 'configuration-error'
            bearer=provider_token()
            host='api.sandbox.push.apple.com' if device['environment']=='sandbox' else 'api.push.apple.com'
            # No app message content on the lock screen; fetch exact content/target after auth.
            payload=json.dumps({'aps':{'alert':{'title':'Pocket','body':'An app has an update.'},'sound':'default'},'appId':event['app_id'],'eventId':event['id']},separators=(',',':'))
            # Configuration is supplied on stdin, keeping device/bearer tokens out of process arguments.
            def quote(value): return json.dumps(value)
            config='\n'.join(['url = '+quote('https://'+host+'/3/device/'+device['token']), 'request = "POST"', 'header = '+quote('authorization: bearer '+bearer), 'header = '+quote('apns-topic: '+topic), 'header = "apns-push-type: alert"', 'header = "apns-priority: 10"', 'header = "apns-expiration: 0"', 'data = '+quote(payload)])
            result=subprocess.run(['curl','--http2','--silent','--max-time','10','--output','/dev/null','--write-out','%{http_code}','--config','-'],input=config.encode(),capture_output=True,timeout=12)
            code=result.stdout.decode().strip()
            if result.returncode!=0: return 'retry'
            if code=='200': return 'provider-accepted' # NOT proof of physical-device delivery.
            if code=='410': return 'invalid-device'
            if code in ('429','500','503'): return 'retry'
            return 'provider-rejected'
        except (KeyError,ValueError,OSError,subprocess.SubprocessError): return 'configuration-error'

def process_pending(db_path, adapter=None):
    adapter=adapter or (APNsAdapter() if delivery_mode()=='apns' else LocalAdapter())
    with sqlite3.connect(db_path) as db:
        db.row_factory=sqlite3.Row;db.execute('PRAGMA foreign_keys=ON')
        from web_api import cleanup
        cleanup(db);db.commit()
        rows=db.execute("SELECT event_id,device_id FROM delivery_outbox WHERE status='pending' AND next_attempt<=? LIMIT 20",(time.time(),)).fetchall()
        for row in rows:
            # Recheck consent/access/session immediately before submission. Revoke cascades queued work.
            event=db.execute('SELECT e.*,s.username AS recipient FROM notification_events e JOIN subscriptions s ON s.id=e.subscription_id JOIN apps a ON a.id=e.app_id WHERE e.id=? AND EXISTS (SELECT 1 FROM inbox WHERE event_id=e.id) AND s.enabled=1 AND (a.owner=s.username OR EXISTS (SELECT 1 FROM shares WHERE app=a.id AND username=s.username))',(row['event_id'],)).fetchone()
            device=db.execute('SELECT d.* FROM notification_devices d JOIN sessions s ON s.token=d.session_digest WHERE d.id=? AND s.expires>?',(row['device_id'],time.time())).fetchone()
            if event is None or device is None or event['recipient'] != device['username']:
                db.execute('DELETE FROM delivery_outbox WHERE event_id=? AND device_id=?',(row['event_id'],row['device_id']));continue
            result=adapter.send(device,event)
            if result=='invalid-device': db.execute('DELETE FROM notification_devices WHERE id=?',(device['id'],));continue
            db.execute('UPDATE delivery_outbox SET attempts=attempts+1,status=?,next_attempt=? WHERE event_id=? AND device_id=?',('pending' if result=='retry' else result,time.time()+60,event['id'],device['id']))
            db.execute("UPDATE delivery_outbox SET status='retry-exhausted' WHERE attempts>=3 AND status='pending'")

def start_worker(db_path, stop):
    def work():
        while not stop.wait(5):
            try: process_pending(db_path)
            except (sqlite3.Error,OSError): pass # No sensitive exception text in logs.
    thread=threading.Thread(target=work,daemon=True,name='pocket-notification-delivery');thread.start();return thread
