import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile,mkdtemp,rm,stat,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {defineWebApp,validateManifest,validateEvent} from '../../Developer/src/sdk.ts';
import {safeTarget,launchURL} from '../../Developer/src/targets.ts';
import {navigate,pairSubscription,safeAreaCSS} from '../../Developer/src/browser.ts';
import {init,inspect,register,notificationTest} from '../../Developer/src/services.ts';
import {flow,root,run,rpc} from './helpers.ts';
test('web manifest metadata schema and SDK output; legacy validation preserved',async()=>{
 assert.deepEqual(defineWebApp(flow.manifest),flow.manifest);
 for(const change of [{schemaVersion:2},{creatorKey:'Bad slug'},{name:' '},{screens:[]},{entryURL:'javascript:alert(1)'},{entryURL:'https://user:password@example.com'},{entryURL:'https://@example.com'},{entryURL:'http://example.com'},{iconURL:'https://example.com/icon#x'},{appearance:{themeColor:'red'}},{version:()=>1},{name:'x'.repeat(61)}])assert.throws(()=>validateManifest({...flow.manifest,...change}));
 assert.equal(validateManifest({...flow.manifest,entryURL:'http://127.0.0.1:8788/notes/42?view=full#content'}).schemaVersion,'web-v1');
 assert.equal((await run('Developer/src/cli.ts',['validate','Developer/miniapp.example.json'])).code,0);
});
test('shared unsafe target fixtures and exact query/hash launch',async()=>{
 const targets=JSON.parse(await readFile(resolve(root,'Developer/Contracts/web-v1/fixtures/targets.json'),'utf8'));
 for(const target of targets.valid)assert.equal(safeTarget(target),target);
 for(const target of targets.invalid)assert.throws(()=>safeTarget(target));
 assert.equal(launchURL(flow.manifest.entryURL,flow.event.request.target),flow.launch.url);
 let actual='';navigate('/notes/42?view=full#content',{origin:'https://notes.example',assign:url=>{actual=String(url);}});assert.equal(actual,flow.launch.url);
 assert.match(safeAreaCSS,/env\(safe-area-inset-bottom/);
});
test('event validation rejects arbitrary recipients, unbounded text and unsafe targets',()=>{
 assert.deepEqual(validateEvent(flow.event.request),flow.event.request);
 for(const change of [{user:'someone'},{title:' '},{body:'x'.repeat(241)},{target:'//evil.example'},{idempotencyKey:'bad/key'},{subscriptionId:''}])assert.throws(()=>validateEvent({...flow.event.request,...change}));
});
test('CLI/MCP validation and preview never fetch or execute; obsolete commands fail',async()=>{
 const file='Developer/Contracts/web-v1/fixtures/manifest.json';
 for(const command of ['validate','preview']){const cli=await run('Developer/src/cli.ts',[command,file]);assert.equal(cli.code,0);const mcp=await rpc(command,{manifest:flow.manifest});assert.deepEqual(JSON.parse(cli.stdout),JSON.parse(mcp.content[0].text));}
 assert.equal(inspect(flow.manifest).executesCode,false);
 assert.equal((await run('Developer/src/cli.ts',['publish',file])).code,1);
 assert.equal((await run('Developer/src/cli.ts',['build',file])).code,1);
 assert.equal((await rpc('publish',{manifest:flow.manifest})).isError,true);
 assert.equal((await rpc('validate',{manifest:{...flow.manifest,script:'alert(1)'}})).isError,true);
});
test('init scaffolds custom web assets without overwriting',async()=>{
 const dir=await mkdtemp(resolve(tmpdir(),'pocket-web-init-'));try{await init(dir);assert.equal(JSON.parse(await readFile(resolve(dir,'pocket.manifest.json'),'utf8')).schemaVersion,'web-v1');assert.match(await readFile(resolve(dir,'public/index.html'),'utf8'),/Little Notes/);await assert.rejects(init(dir));}finally{await rm(dir,{recursive:true,force:true});}
});
test('browser pairing sends consent/code only to same-origin creator API',async()=>{
 const priorWindow=(globalThis as any).window,priorFetch=globalThis.fetch;let call:any;
 (globalThis as any).window={location:{origin:'https://notes.example'}};
 globalThis.fetch=(async(url,options)=>{call={url,options};return new Response('{"paired":true}');}) as typeof fetch;
 try{
  await assert.rejects(pairSubscription({endpoint:'//evil.example',pairingCode:'code',consent:true,csrfToken:'csrf'}));
  await assert.rejects(pairSubscription({endpoint:'/api/pair',pairingCode:'code',consent:false,csrfToken:'csrf'}));
  assert.equal(call,undefined);
  assert.deepEqual(await pairSubscription({endpoint:'/api/pair',pairingCode:'code',consent:true,csrfToken:'csrf'}),{paired:true});
  assert.equal(call.url,'https://notes.example/api/pair');assert.equal(call.options.credentials,'same-origin');assert.equal(call.options.headers.Authorization,undefined);assert.deepEqual(JSON.parse(call.options.body),{pairingCode:'code',consent:true});
 }finally{globalThis.fetch=priorFetch;if(priorWindow===undefined)delete (globalThis as any).window;else (globalThis as any).window=priorWindow;}
});
test('mock CLI/MCP registration and events match shared fixtures; no false success or secret output',async()=>{
 let revision=0,malformed=false;const events=new Map<string,unknown>();const server=createServer(async(req,res)=>{
  let raw='';for await(const c of req)raw+=c;const body=JSON.parse(raw||'{}');res.setHeader('Content-Type','application/json');
  if(req.url==='/web-apps' && req.headers.authorization==='Bearer account-fixture'){revision++;res.end(JSON.stringify(malformed?{}:{...flow.registration.response,revision}));return;}
  if(req.url==='/notification-events' && req.headers.authorization==='Bearer app-fixture'){validateEvent(body);const duplicate=events.has(body.idempotencyKey);events.set(body.idempotencyKey,body);res.end(JSON.stringify({...flow.event.response,duplicate}));return;}
  res.statusCode=401;res.end('{"error":"never echo secret-fixture"}');
 });
 const dir=await mkdtemp(resolve(tmpdir(),'pocket-mock-'));
 try{server.listen(0,'127.0.0.1');await once(server,'listening');const base=`http://127.0.0.1:${(server.address() as any).port}`;
  const env={POCKET_TOKEN:'account-fixture',POCKET_APP_CREDENTIAL:'app-fixture'};
  const file='Developer/Contracts/web-v1/fixtures/manifest.json';const cli=await run('Developer/src/cli.ts',['register',file,'--backend',base],undefined,env);assert.equal(cli.code,0);assert.deepEqual(JSON.parse(cli.stdout),flow.registration.response);
  const mcp=await rpc('register',{backend:base,manifest:flow.manifest},env);assert.equal(JSON.parse(mcp.content[0].text).revision,2);
  const eventPath=resolve(dir,'event.json');await writeFile(eventPath,JSON.stringify(flow.event.request));
  const sent=await run('Developer/src/cli.ts',['notification-test',eventPath,'--backend',base],undefined,env);assert.equal(sent.code,0);assert.deepEqual(JSON.parse(sent.stdout),flow.event.response);
  assert.deepEqual(JSON.parse((await rpc('notification-test',{backend:base,event:flow.event.request},env)).content[0].text),flow.event.duplicateResponse);
  const denied=await run('Developer/src/cli.ts',['register',file,'--backend',base],undefined,{POCKET_TOKEN:'bad'});assert.equal(denied.code,1);assert.match(denied.stderr,/401/);assert.ok(!denied.stderr.includes('secret-fixture'));
  malformed=true;const bad=await rpc('register',{backend:base,manifest:flow.manifest},env);assert.equal(bad.isError,true);
  assert.ok(!cli.stdout.includes('account-fixture'));assert.ok(!sent.stdout.includes('app-fixture'));
 }finally{server.close();await rm(dir,{recursive:true,force:true});}
});
