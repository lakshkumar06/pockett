import test from 'node:test';
import assert from 'node:assert/strict';
import {dispatch,mini,Fault,validateSpec,type Store} from '../../Spacetime/spacetimedb/src/domain.ts';
import {envelope,hash} from '../src/spacetime.ts';
import {build,checks,complete} from '../src/agent.ts';
import {Photon} from '../src/photon.ts';
function database(){let records=new Map<string,any>();const store:Store={get:(t,k)=>structuredClone(records.get(t+':'+k)),put:(t,k,v)=>{records.set(t+':'+k,structuredClone(v));},delete:(t,k)=>{records.delete(t+':'+k);},all:t=>[...records].filter(([k])=>k.startsWith(t+':')).map(([,v])=>structuredClone(v))};
 const api=(method:string,path:string,body:any={},token='alice',extra:any={})=>{const snapshot=new Map(records);try{const req=envelope(method,path,body,token,extra);return path.startsWith('/mini/')?mini(store,req,100):dispatch(store,req,100);}catch(e){records=snapshot;throw e;}};
 for(const user of ['alice','bob','eve'])api('POST','/signup',{username:user},'',{proof:'password-hash',salt:'salt',secretHash:hash(user)});return {api,store};}
const spec={name:'House list',summary:'Things we need',kind:'list',appearance:{icon:'check',theme:'forest',background:'glow',layout:'cards'},actionLabel:'Add item',emptyTitle:'Your list is clear',emptyBody:'Add what the house needs next.',fields:[{key:'item',label:'Item',type:'text',placeholder:'Milk, batteries, soap'}]};
const manifest={schemaVersion:'web-v1',creatorKey:'house-list',name:'House list',summary:'Things we need',entryURL:'https://example.com/',iconURL:'https://example.com/icon.svg',version:'1'};
test('sharing, pairing consent, idempotency and revocation are enforced in the domain',()=>{
 const {api}=database();const app=api('POST','/web-apps',{manifest});
 assert.throws(()=>api('GET','/apps/'+app.appId,{},'eve'),/not found/);
 api('POST',`/apps/${app.appId}/shares`,{username:'bob'});
 assert.equal(api('GET','/apps/'+app.appId,{},'bob').name,'House list');
 api('POST',`/apps/${app.appId}/notification-credential`,{},'alice',{secretHash:hash('creator')});
 assert.throws(()=>api('POST',`/apps/${app.appId}/pairings`,{},'bob'),/consent/);
 const pair=api('POST',`/apps/${app.appId}/pairings`,{consent:true},'bob',{secretHash:hash('pair')});assert.equal(pair.expiresAt,400);
 const sub=api('POST','/notification-pairings/redeem',{pairingHash:hash('pair')},'creator');
 assert.throws(()=>api('POST','/notification-pairings/redeem',{pairingHash:hash('pair')},'creator'),/expired/);
 const event={subscriptionId:sub.subscriptionId,idempotencyKey:'one',title:'Ready',body:'Your list is ready',target:'/list'};
 const first=api('POST','/notification-events',event,'creator');assert.equal(api('POST','/notification-events',event,'creator').eventId,first.eventId);
 assert.throws(()=>api('POST','/notification-events',{...event,title:'Changed'},'creator'),/Idempotency/);
 assert.equal(api('GET','/notification-inbox',{},'bob').entries.length,1);
 api('DELETE',`/apps/${app.appId}/shares/bob`);
 assert.equal(api('GET','/notification-inbox',{},'bob').entries.length,0);
 assert.throws(()=>api('POST','/notification-events',event,'creator'),/unavailable/);
});
test('worker lease, explicit publish and app-scoped access prevent cross-user writes',()=>{
 const {api}=database();const j=api('POST','/jobs',{prompt:'Build a house list'});
 assert.throws(()=>api('POST',`/jobs/${j.id}/publish`,{publicOrigin:'https://pocket.example'}),/pass/);
 const lease=api('POST',`/internal/jobs/${j.id}/claim`);
 assert.throws(()=>api('POST',`/internal/jobs/${j.id}/claim`),/claimed/);
 assert.throws(()=>api('POST',`/internal/jobs/${j.id}/save`,{lease:'wrong',status:'ready',spec}),/expired/);
 api('POST',`/internal/jobs/${j.id}/save`,{lease:lease.lease,status:'ready',spec});
 const a=api('POST',`/jobs/${j.id}/publish`,{publicOrigin:'https://pocket.example'});
 api('POST',`/apps/${a.appId}/access`,{},'alice',{secretHash:hash('access')});
 api('POST',`/mini/${a.appId}/items`,{data:{item:'Milk'}},'access');
 assert.equal(api('GET',`/mini/${a.appId}/items`,{},'access').items.length,1);
 assert.throws(()=>api('GET',`/mini/${a.appId}/items`,{},'bob'),/access link/);
 assert.throws(()=>api('GET',`/jobs/${j.id}`,{},'bob'),/not found/);
});
test('model receives failed tool results and must repair before finishing',async()=>{
 let turn=0;const steps=[['build_app',{spec:{...spec,kind:'arbitrary-code'}}],['build_app',{spec}],['test_app',{}],['finish',{}]];
 const result=await build('Make a list',null,async()=>{},async messages=>{if(turn===1)assert.match(messages.at(-1).content,/Choose list/);const [name,args]=steps[turn++];return {tool_calls:[{id:'call'+turn,type:'function',function:{name,arguments:JSON.stringify(args)}}]};});
 assert.equal(result.spec.name,'House list');assert.deepEqual(result.trace.map(t=>t.ok),[false,true,true,true]);assert.equal(checks(spec).ok,true);
});
test('appearance and choice fields stay within the fixed safe design system',()=>{
 const poll={name:'Lunch vote',summary:'Choose today’s lunch',kind:'poll',appearance:{icon:'inbox',theme:'ember',background:'mesh',layout:'cards'},actionLabel:'Cast vote',emptyTitle:'No votes yet',emptyBody:'Be the first to choose lunch.',fields:[{key:'choice',label:'Lunch',type:'choice',placeholder:'Pick one',options:['Tacos','Salad','Pizza']}]};
 assert.equal(checks(poll).ok,true);assert.doesNotThrow(()=>validateSpec(poll));
 assert.throws(()=>validateSpec({...poll,appearance:{...poll.appearance,theme:'neon'}}),/Invalid appearance/);
 assert.throws(()=>validateSpec({...poll,fields:[{...poll.fields[0],options:['Tacos','Tacos']}]}),/Duplicate choice/);
});
test('Photon consumes its documented 2.0 message shape and deduplicates replies',async()=>{
 const {api}=database();api('POST','/photon-link',{},'alice',{secretHash:hash('link-secret')});let sends=0;
 const message={id:'msg-one',projectId:'project',status:'received',createdAt:new Date().toISOString(),sentBy:{id:'human'},space:{id:'space',participantIds:['human','agent']},content:{type:'text',text:'link link-secret'}};
 const photon=new Photon('key','project','agent',async(url,opts)=>{if(opts?.method==='POST'){sends++;assert.equal(JSON.parse(String(opts.body)).content.format,'plain');return Response.json({id:'outgoing'});}assert.match(String(url),/direction=received/);return Response.json({items:[message]});});
 const invoke=async(method:string,path:string,body:any={})=>api(method,'/internal/'+path,body);
 await photon.tick(invoke);await photon.tick(invoke);await photon.tick(invoke);assert.equal(sends,1);
 message.id='msg-build';message.content.text='build a shared list';await photon.tick(invoke);
 assert.equal(api('GET','/jobs').jobs.length,1);
});

test('NVIDIA tool choices advance after successful checks and reopen repair after failures',async()=>{
 const originalKey=process.env.NVIDIA_API_KEY,originalModel=process.env.NEMOTRON_MODEL;
 process.env.NVIDIA_API_KEY='test-fixture';process.env.NEMOTRON_MODEL='test-model';
 const messages:any[]=[];let offered:string[]=[];
 const fetcher:typeof fetch=async(_url,options)=>{offered=JSON.parse(String(options?.body)).tools.map((t:any)=>t.function.name);return Response.json({choices:[{message:{tool_calls:[]}}]});};
 const result=(name:string,ok:boolean)=>{const id=String(messages.length);messages.push({role:'assistant',tool_calls:[{id,function:{name}}]},{role:'tool',tool_call_id:id,content:JSON.stringify({ok})});};
 try{
  await complete(messages,fetcher);assert.deepEqual(offered,['build_app']);
  result('build_app',true);await complete(messages,fetcher);assert.deepEqual(offered,['test_app']);
  result('test_app',false);await complete(messages,fetcher);assert.deepEqual(offered,['build_app']);
  result('build_app',true);result('test_app',true);await complete(messages,fetcher);assert.deepEqual(offered,['finish']);
 }finally{
  if(originalKey===undefined)delete process.env.NVIDIA_API_KEY;else process.env.NVIDIA_API_KEY=originalKey;
  if(originalModel===undefined)delete process.env.NEMOTRON_MODEL;else process.env.NEMOTRON_MODEL=originalModel;
 }
});
