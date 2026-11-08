/** Requires a fresh local Spacetime module + gateway. Uses synthetic users and prints no tokens. */
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {fileURLToPath} from 'node:url';
import {service} from '../src/spacetime.ts';
import {tick} from '../src/worker.ts';
const base=process.env.POCKET_PUBLIC_ORIGIN!;const suffix=Date.now().toString(36);
async function api(path:string,method='GET',body?:any,token=''){
 const r=await fetch(base+path,{method,headers:{'Content-Type':'application/json',Authorization:'Bearer '+token},body:body?JSON.stringify(body):undefined});const data:any=await r.json();if(!r.ok)throw Error(`${path}: ${r.status} ${data.error}`);return data;
}
const alice=await api('/signup','POST',{username:'alice_'+suffix,password:'synthetic-test-password'});const bob=await api('/signup','POST',{username:'bob_'+suffix,password:'synthetic-test-password'});
const login=await api('/login','POST',{username:alice.username,password:'synthetic-test-password'});assert.equal(login.username,alice.username);
const a=await api('/apps','POST',{name:'A site',summary:'A useful site',url:'https://example.com/'},alice.token);
await api(`/apps/${a.id}/shares`,'POST',{username:bob.username},alice.token);assert.equal((await api('/apps','GET',undefined,bob.token)).apps.length,1);
await api(`/apps/${a.id}/shares/${bob.username}`,'DELETE',undefined,alice.token);
const cli=async(...args:string[])=>JSON.parse((await promisify(execFile)(process.execPath,[fileURLToPath(new URL('../../Developer/src/cli.ts',import.meta.url)),...args,'--backend',base],{env:{...process.env,POCKET_TOKEN:alice.token}})).stdout);
const j=await cli('build','A shared grocery list');
await tick(service,async(prompt,previous,progress)=>{const result={spec:{name:'Groceries',summary:'A shared grocery list',kind:'list',fields:[{key:'item',label:'Item',type:'text'}]},trace:[{tool:'fixture-model',ok:true,detail:'Deterministic integration fixture; no NVIDIA call'}]};await progress(result.spec,result.trace);return result;});
assert.equal((await cli('status',j.id)).status,'ready');
const built=await cli('publish',j.id);
const access=await cli('open',built.appId);const appToken=new URL(access.url).hash.slice(8);
await api(`/mini/${built.appId}/items`,'POST',{data:{item:'Milk'}},appToken);
assert.equal((await api(`/mini/${built.appId}/items`,'GET',undefined,appToken)).items[0].data.item,'Milk');
const html=await fetch(base+`/mini/${built.appId}/`).then(r=>r.text());assert.match(html,/Groceries/);
const foreign=await fetch(base+`/mini/${built.appId}/items`,{headers:{Authorization:'Bearer '+bob.token}});assert.equal(foreign.status,401);
const manifest={schemaVersion:'web-v1',creatorKey:'test-'+suffix,name:'Notes',summary:'Little notes',entryURL:'https://example.com/',iconURL:'https://example.com/icon.svg',version:'1'};
const registered=await api('/web-apps','POST',{manifest},alice.token);
const credential=await api(`/apps/${registered.appId}/notification-credential`,'POST',{},alice.token);
const pairing=await api(`/apps/${registered.appId}/pairings`,'POST',{consent:true},alice.token);assert.equal(typeof pairing.expiresAt,'number');
const subscription=await api('/notification-pairings/redeem','POST',{pairingCode:pairing.pairingCode},credential.credential);
const event={idempotencyKey:'one',subscriptionId:subscription.subscriptionId,title:'Ready',body:'Your notes are ready',target:'/notes'};
const receipt=await api('/notification-events','POST',event,credential.credential);assert.equal((await api('/notification-events','POST',event,credential.credential)).eventId,receipt.eventId);
assert.equal((await api('/notification-inbox','GET',undefined,alice.token)).entries.length,1);
const launch=await api(`/notification-inbox/${receipt.eventId}/launch`,'GET',undefined,alice.token);assert.equal(launch.url,'https://example.com/notes');
console.log('PASS: real Spacetime signup/login, sharing/revocation, CLI build/status/publish/open, leased job, publication, generated app data, access isolation, notification pairing/idempotency/inbox. Model response was a fixture.');
// Private fixture for browser QA, never committed or printed.
if(process.env.QA_LINK_FILE){const {writeFile}=await import('node:fs/promises');await writeFile(process.env.QA_LINK_FILE,JSON.stringify({url:access.url,appId:built.appId}),{mode:0o600});}
