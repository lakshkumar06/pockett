import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {flow,root,startBackend,api} from './helpers.ts';
test('custom example backend: own login, CSRF consent, hidden subscription, inbox event and exact web target',async()=>{
 const b=await startBackend();let notes:ReturnType<typeof spawn>|undefined;
 try{
  const owner=(await api(b.base,'/signup',undefined,{username:'exampleowner',password:'local-test-password'})).body.token;
  const appId=(await api(b.base,'/web-apps',owner,flow.registration.request)).body.appId;
  const credential=(await api(b.base,`/apps/${appId}/notification-credential`,owner,{})).body.credential;
  notes=spawn(process.execPath,['Developer/examples/little-notes/server.ts'],{cwd:root,env:{...process.env,NOTES_PORT:'0',NOTES_PASSWORD:'example-password',POCKET_BACKEND:b.base,POCKET_APP_CREDENTIAL:credential},stdio:['ignore','pipe','pipe']});
  const line=await new Promise<string>((accept,reject)=>{const timer=setTimeout(()=>reject(Error('Example startup timeout')),10000);notes!.stdout!.once('data',b=>{clearTimeout(timer);accept(b.toString());});notes!.once('exit',()=>{clearTimeout(timer);reject(Error('Example startup failed'));});});
  const base=line.match(/http:\/\/127\.0\.0\.1:\d+/)![0];assert.ok(!line.includes(credential));
  // Update before pairing; origin change invalidates old credential, so rotate and restart example.
  await api(b.base,'/web-apps',owner,{manifest:{...flow.manifest,entryURL:base+'/',iconURL:base+'/icon.svg'}});
  const liveCredential=(await api(b.base,`/apps/${appId}/notification-credential`,owner,{})).body.credential;
  const old=once(notes,'exit');notes.kill();await old;
  notes=spawn(process.execPath,['Developer/examples/little-notes/server.ts'],{cwd:root,env:{...process.env,NOTES_PORT:new URL(base).port,NOTES_PASSWORD:'example-password',POCKET_BACKEND:b.base,POCKET_APP_CREDENTIAL:liveCredential},stdio:['ignore','pipe','pipe']});await once(notes.stdout!,'data');
  const session=await fetch(base+'/api/session');const cookie=session.headers.get('set-cookie')!.split(';')[0];const info=await session.json() as any;
  async function post(path:string,body:unknown,origin=base){const r=await fetch(base+path,{method:'POST',headers:{Cookie:cookie,Origin:origin,'Content-Type':'application/json','X-CSRF-Token':info.csrfToken},body:JSON.stringify(body)});return {status:r.status,body:await r.json() as any};}
  assert.equal((await post('/api/login',{password:'example-password'},'https://evil.example')).status,403);
  assert.equal((await post('/api/login',{password:'wrong'})).status,401);
  assert.equal((await post('/api/login',{password:'example-password'})).status,200);
  assert.equal((await post('/api/remind',{idempotencyKey:'before-pair'})).status,409);
  const pairing=(await api(b.base,`/apps/${appId}/pairings`,owner,{consent:true})).body;
  assert.equal((await post('/api/pair',{pairingCode:pairing.pairingCode,consent:false})).status,400);
  const paired=await post('/api/pair',{pairingCode:pairing.pairingCode,consent:true});assert.deepEqual(paired.body,{paired:true});assert.ok(!JSON.stringify(paired).includes('subscriptionId'));
  const sent=await post('/api/remind',{idempotencyKey:'example-event'});assert.equal(sent.status,200);assert.equal(sent.body.duplicate,false);
  assert.equal((await post('/api/remind',{idempotencyKey:'example-event'})).body.duplicate,true);
  const inbox=(await api(b.base,'/notification-inbox',owner)).body;assert.equal(inbox.entries.length,1);
  const launch=(await api(b.base,`/notification-inbox/${sent.body.eventId}/launch`,owner)).body;assert.equal(launch.url,base+'/notes/42?view=full#content');
  const page=await fetch(launch.url);assert.equal(page.status,200);assert.match(await page.text(),/id="content"/);
  assert.equal((await fetch(base+'/sdk/browser.js')).status,200);
  assert.equal((await post('/api/remind',{idempotencyKey:'arbitrary',subscriptionId:'someone-else'})).status,400);
 }finally{if(notes && notes.exitCode===null && notes.signalCode===null){const exited=once(notes,'exit');notes.kill();await exited;}await b.close();}
});
