/** All durable state and authorization live in the Spacetime transaction. No network or filesystem. */
export type RecordValue = Record<string, any>;
export interface Store {
  get(table: string, id: string): RecordValue | undefined;
  put(table: string, id: string, value: RecordValue): void;
  delete(table: string, id: string): void;
  all(table: string): RecordValue[];
}
export interface Request {
  method: string; path: string; body: RecordValue; query?: Record<string,string>;
  auth: string; id: string; secretHash: string; proof?: string; salt?: string;
}
export class Fault extends Error { status: number; constructor(status:number,message:string){super(message);this.status=status;} }
function fail(status:number,message:string):never{throw new Fault(status,message);}
function text(value:unknown,max:number,label:string):string {
  if(typeof value!=='string'||!value.trim()||value.length>max)fail(400,`Invalid ${label}`);return value as string;
}
/** Strict ASCII authority grammar works in Spacetime's deterministic V8 (no global URL API).
 * Browsers still use WHATWG URL; credentials, percent-encoded hosts, controls and ambiguous authority syntax are refused here. */
export function originOf(value:unknown):string {
  const raw=text(value,2048,'URL');
  if(/[\\\s\x00-\x1f\x7f]/.test(raw))fail(400,'Invalid URL');
  const m=/^(https?):\/\/(\[[0-9a-f:]+\]|[a-z0-9.-]+)(?::([0-9]{1,5}))?(?:[/?#].*)?$/i.exec(raw);
  if(!m)fail(400,'Invalid URL');
  const protocol=m[1].toLowerCase(),host=m[2].toLowerCase(),port=m[3]?Number(m[3]):null;
  if(port!==null&&(port<1||port>65535))fail(400,'Invalid port');
  if(!host.startsWith('[')&&host.split('.').some(label=>!label||label.length>63||label.startsWith('-')||label.endsWith('-')))fail(400,'Invalid hostname');
  if(protocol==='http'&&!['localhost','127.0.0.1','[::1]'].includes(host))fail(400,'Use HTTPS (HTTP is allowed on localhost)');
  return protocol+'://'+host+(port&&port!==(protocol==='https'?443:80)?':'+port:'');
}
export function safeURL(value:unknown):string {originOf(value);return value as string;}
export function safeTarget(value:unknown):string {
  const v=text(value,2048,'target');if(!v.startsWith('/')||v.startsWith('//')||/[\\\s]/.test(v)||/%(?:0.|1.|20|7f|5c|2f|25)/i.test(v)||/%(?![0-9a-f]{2})/i.test(v))fail(400,'Invalid target');
  if(decodeURIComponent(v).split(/[/?#]/).some(p=>p==='.'||p==='..'))fail(400,'Invalid target');return v;
}
export function manifest(value:any) {
  if(!value||Array.isArray(value)||JSON.stringify(value).length>8192||value.schemaVersion!=='web-v1')fail(400,'Invalid web manifest');
  if(Object.keys(value).some(k=>!['schemaVersion','creatorKey','name','summary','entryURL','iconURL','version','appearance'].includes(k)))fail(400,'Unknown manifest field');
  if(!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(text(value.creatorKey,64,'creator key')))fail(400,'Invalid creator key');
  text(value.name,60,'name');text(value.summary,160,'summary');text(value.version,32,'version');safeURL(value.entryURL);safeURL(value.iconURL);
  if(originOf(value.entryURL)!==originOf(value.iconURL))fail(400,'Icon must share app origin');
  if(value.appearance){const a=value.appearance;if(Object.keys(a).some(k=>!['colorScheme','themeColor'].includes(k))||(a.colorScheme&&!['system','light','dark'].includes(a.colorScheme))||(a.themeColor&&!/^#[\da-f]{6}$/i.test(a.themeColor)))fail(400,'Invalid appearance');}
  return value;
}
export function validateSpec(s:any) {
  if(!s||Object.keys(s).some(k=>!['name','summary','kind','fields','accent','appearance','actionLabel','emptyTitle','emptyBody'].includes(k)))fail(400,'Invalid app specification');
  text(s.name,60,'name');text(s.summary,160,'summary');
  if(!['list','tracker','poll'].includes(s.kind))fail(400,'Choose list, tracker, or poll');
  if(!Array.isArray(s.fields)||s.fields.length<1||s.fields.length>8)fail(400,'Use one to eight fields');
  const seen=new Set<string>();for(const f of s.fields){
    if(!f||Object.keys(f).some(k=>!['key','label','type','placeholder','options'].includes(k))||!/^([a-z][a-z0-9_]{0,23})$/.test(f.key)||seen.has(f.key)||['__proto__','constructor','prototype'].includes(f.key))fail(400,'Invalid or duplicate field');
    seen.add(f.key);text(f.label,40,'field label');if(!['text','number','boolean','choice'].includes(f.type))fail(400,'Invalid field type');
    if(f.placeholder!==undefined)text(f.placeholder,80,'placeholder');
    if(f.type==='choice'){
      if(!Array.isArray(f.options)||f.options.length<2||f.options.length>8)fail(400,'Choice fields need two to eight options');
      const options=new Set<string>();for(const option of f.options){const value=text(option,40,'choice option');if(options.has(value))fail(400,'Duplicate choice option');options.add(value);}
    }else if(f.options!==undefined)fail(400,'Only choice fields use options');
  }
  if(s.accent&&!/^#[\da-f]{6}$/i.test(s.accent))fail(400,'Invalid accent');
  if(s.appearance){
    const a=s.appearance;if(Array.isArray(a)||Object.keys(a).some(k=>!['icon','theme','background','layout'].includes(k)))fail(400,'Invalid appearance');
    if(!['check','notebook-pen','calendar-days','wallet','timer','book-open','user-round','grid-2x2','inbox','bell'].includes(a.icon)||!['forest','ember','ocean','violet','paper'].includes(a.theme)||!['glow','mesh','grid','plain'].includes(a.background)||!['cards','rows'].includes(a.layout))fail(400,'Invalid appearance');
  }
  if(s.actionLabel!==undefined)text(s.actionLabel,28,'action label');
  if(s.emptyTitle!==undefined)text(s.emptyTitle,60,'empty title');
  if(s.emptyBody!==undefined)text(s.emptyBody,120,'empty message');
  return s;
}
export function dispatch(db:Store,r:Request,now:number):any {
  const b=r.body??{},p=r.path.split('/').filter(Boolean),method=r.method,q=r.query??{};
  const put=(table:string,id:string,v:RecordValue):RecordValue=>{db.put(table,id,{...v,id});return {...v,id};};
  const rows=(table:string,fn:(v:RecordValue)=>boolean)=>db.all(table).filter(fn);
  const remove=(table:string,fn:(v:RecordValue)=>boolean)=>{for(const v of rows(table,fn))db.delete(table,v.id);};
  function rate(key:string,limit:number,period=60){const old=db.get('limits',key);const n=old&&old.until>now?old:{count:0,until:now+period};if(n.count>=limit)fail(429,'Please try again later');put('limits',key,{count:n.count+1,until:n.until});}
  function cleanup(appId:string,user?:string){const affected=rows('subscriptions',x=>x.appId===appId&&(!user||x.username===user));for(const s of affected){db.delete('subscriptions',s.id);remove('inbox',x=>x.subscriptionId===s.id);}remove('pairings',x=>x.appId===appId&&(!user||x.username===user));}
  function app(id:string,user:string,owner=false){const a=db.get('apps',id);if(!a||!(a.owner===user||(!owner&&a.sharedWith.includes(user))))fail(404,'App not found');return a!;}
  function session(){const s=db.get('sessions',r.auth);if(!s||s.expires<=now)fail(401,'Sign in required');return s!.username as string;}
  function reg(a:RecordValue){return {appId:a.id,revision:a.revision,deepLink:`pocket://app/${a.id}`};}
  function job(id:string,user:string){const j=db.get('jobs',id);if(!j||j.owner!==user)fail(404,'Build not found');return j!;}
  if(p[0]==='internal'){
    // These routes are reachable only through the publisher-identity procedure, never HTTP.
    if(p[1]==='auth'){const u=db.get('users',String(b.username));return u?{salt:u.salt}:{salt:null};}
    if(p[1]==='jobs'&&method==='GET')return {jobs:rows('jobs',j=>j.status==='queued'||(j.status==='building'&&j.leaseUntil<now)).slice(0,10)};
    if(p[1]==='jobs'&&p[3]==='claim'){
      const j=db.get('jobs',p[2]);if(!j||!(j.status==='queued'||(j.status==='building'&&j.leaseUntil<now)))fail(409,'Build already claimed');
      return put('jobs',j.id,{...j,status:'building',lease:r.id,leaseUntil:now+300,attempt:(j.attempt??0)+1});
    }
    if(p[1]==='jobs'&&p[3]==='save'){
      const j=db.get('jobs',p[2]);if(!j||j.status!=='building'||j.lease!==b.lease||j.leaseUntil<now)fail(409,'Build lease expired');
      if(!['building','ready','failed'].includes(b.status))fail(400,'Invalid build status');
      if(b.status==='ready')validateSpec(b.spec);
      return put('jobs',j.id,{...j,status:b.status,spec:b.spec??j.spec,trace:b.trace??[],error:b.error??null,leaseUntil:now+300});
    }
    if(p[1]==='photon'){
      const key=text(b.key,180,'conversation key');
      if(p[2]==='cursor'){if(method==='GET')return db.get('cursors',key)??{};return put('cursors',key,{value:b.value});}
      if(p[2]==='ingest'){
        const eventId=text(b.eventId,128,'message ID');const existing=db.get('messages',eventId);if(existing)return existing;
        const command=text(b.text,4000,'message');const link=db.get('conversations',key);
        let reply='Link Pocket first: run pocket connect-photon, then send link followed by your code.',jobId:string|undefined;
        if(command.startsWith('link ')){
          const code=db.get('links',b.codeHash);if(!code||code.expires<now)reply='That code expired. Create a new one in Pocket.';
          else {put('conversations',key,{owner:code.username,jobId:null});db.delete('links',b.codeHash);reply='Pocket is linked. Send build followed by what you want to make.';}
        }else if(link){
          if(command==='status'){const j=link.jobId&&db.get('jobs',link.jobId);reply=j?`Your app is ${j.status}. ${j.status==='ready'?'Reply publish to add it to Pocket.':''}`:'Send build followed by your app idea.';}
          else if(command==='publish'&&link.jobId){const j=job(link.jobId,link.owner);if(j.status==='published')reply=`Open pocket://app/${j.appId}`;else if(j.status!=='ready')reply='Your build is not ready yet. Send status in a moment.';else {const a=publish(j,link.owner);reply=`Added to Pocket: pocket://app/${a.appId}`;}}
          else if(command.startsWith('build ')||command.startsWith('change ')){
            rate('build:'+link.owner,10,3600);const prior=link.jobId&&db.get('jobs',link.jobId);if(prior&&['queued','building'].includes(prior.status))reply='Your current build is still running. Send status in a moment.';
            else{jobId=r.id;put('jobs',jobId,{owner:link.owner,prompt:command,spec:prior?.spec??null,status:'queued',trace:[],createdAt:now,appId:prior?.appId??null});put('conversations',key,{...link,jobId});reply='I’m building it. Send status to check, then publish when it’s ready.';}
          }else reply='Send build <idea>, change <request>, status, or publish.';
        }
        return put('messages',eventId,{reply,jobId,sent:false,key,createdAt:now});
      }
      if(p[2]==='sent'){const m=db.get('messages',b.eventId);if(m)put('messages',m.id,{...m,sent:true});return {ok:true};}
    }
    return fail(404,'Unknown service operation');
  }
  if((p[0]==='signup'||p[0]==='login')&&method==='POST'){
    const username=text(b.username,32,'username').toLowerCase();if(!/^[a-z0-9_]{3,32}$/.test(username))fail(400,'Use 3–32 letters, numbers, or underscores');
    rate('login:'+username,30,300);const u=db.get('users',username);
    if(p[0]==='signup'){if(u)fail(409,'Username already exists');if(!r.proof||!r.salt)fail(400,'Password required');put('users',username,{username,passwordHash:r.proof,salt:r.salt});}
    else if(!u||u.passwordHash!==r.proof)fail(401,'Invalid username or password');
    put('sessions',r.secretHash,{username,expires:now+604800});return {username};
  }
  if(p[0]==='notification-pairings'||p[0]==='notification-events'){
    const cred=db.get('credentials',r.auth);if(!cred)fail(401,'Invalid app credential');
    if(p[0]==='notification-pairings'&&p[1]==='redeem'&&method==='POST'){
      const pairing=db.get('pairings',b.pairingHash);if(!pairing||pairing.appId!==cred.appId||pairing.expires<=now)fail(400,'Pairing expired or unavailable');
      app(cred.appId,pairing!.username);cleanup(cred.appId,pairing!.username);
      put('subscriptions',r.id,{appId:cred.appId,username:pairing!.username,notificationsEnabled:true});return {subscriptionId:r.id,notificationsEnabled:true};
    }
    if(p[0]==='notification-events'&&method==='POST'){
      const sid=text(b.subscriptionId,128,'subscription'),s=db.get('subscriptions',sid);if(!s||s.appId!==cred.appId)fail(404,'Subscription unavailable');app(cred.appId,s!.username);
      const event={subscriptionId:sid,title:text(b.title,100,'title'),body:text(b.body,500,'body'),target:safeTarget(b.target)};
      const idem=text(b.idempotencyKey,128,'idempotency key'),eventKey=cred.appId+':'+idem;const old=db.get('events',eventKey);
      if(old){if(JSON.stringify(old.payload)!==JSON.stringify(event))fail(409,'Idempotency key already used');return {eventId:old.eventId,duplicate:true};}
      if(!s!.notificationsEnabled)fail(409,'Notifications muted');rate('notify:'+cred.appId,60);rate('notify:'+sid,20);
      put('events',eventKey,{payload:event,eventId:r.id,createdAt:now});put('inbox',r.id,{...event,eventId:r.id,appId:cred.appId,username:s!.username,createdAt:now,read:false});
      return {eventId:r.id,duplicate:false};
    }return fail(404,'Not found');
  }
  const user=session();
  if(p[0]==='me'&&method==='GET')return {username:user};
  if(p[0]==='logout'&&method==='POST'){db.delete('sessions',r.auth);remove('devices',d=>d.session===r.auth);return {ok:true};}
  if(p[0]==='photon-link'&&method==='POST'){rate('link:'+user,5);put('links',r.secretHash,{username:user,expires:now+300});return {expiresIn:300};}
  if(p[0]==='jobs'){
    if(p.length===1&&method==='POST'){rate('build:'+user,10,3600);const prompt=text(b.prompt,4000,'prompt');let prior;if(b.appId){app(b.appId,user,true);prior=rows('jobs',j=>j.appId===b.appId&&j.status==='published').at(-1);}
      return put('jobs',r.id,{owner:user,prompt,status:'queued',spec:prior?.spec??null,appId:b.appId??null,trace:[],createdAt:now});}
    if(p.length===1&&method==='GET')return {jobs:rows('jobs',j=>j.owner===user)};
    const j=job(p[1],user);if(p.length===2&&method==='GET')return j;
    if(p[2]==='publish'&&method==='POST'){if(j.status==='published')return reg(app(j.appId,user));if(j.status!=='ready')fail(409,'Build must pass its checks before publishing');return publish(j,user);}
  }
  function publish(j:RecordValue,owner:string){
    const spec=validateSpec(j.spec);const id=j.appId??j.id;const old=db.get('apps',id);if(old&&old.owner!==owner)fail(403,'Not your app');
    const origin=safeURL(b.publicOrigin);const entryURL=originOf(origin)+`/mini/${id}/`;
    const m={schemaVersion:'web-v1',creatorKey:'built-'+id,name:spec.name,summary:spec.summary,entryURL,iconURL:originOf(origin)+`/mini/${id}/icon.svg`,version:String((old?.revision??0)+1)};
    const a=put('apps',id,{owner,generated:true,name:spec.name,summary:spec.summary,url:entryURL,kind:'web',supported:true,manifest:m,creatorKey:m.creatorKey,revision:(old?.revision??0)+1,sharedWith:old?.sharedWith??[],spec});
    put('jobs',j.id,{...j,status:'published',appId:id});return reg(a);
  }
  if(p[0]==='apps'||p[0]==='web-apps'){
    if(p.length===1&&method==='GET')return {apps:rows('apps',a=>a.owner===user||a.sharedWith.includes(user))};
    if(p.length===1&&method==='POST'){
      if(p[0]==='web-apps'){
        const m=manifest(b.manifest),old=rows('apps',a=>a.owner===user&&a.creatorKey===m.creatorKey)[0],id=old?.id??r.id;
        if(old&&originOf(old.url)!==originOf(m.entryURL)){cleanup(id);remove('credentials',c=>c.appId===id);}
        const a=put('apps',id,{owner:user,name:m.name,summary:m.summary,url:m.entryURL,kind:'web',supported:true,manifest:m,creatorKey:m.creatorKey,revision:(old?.revision??0)+1,sharedWith:old?.sharedWith??[]});return reg(a);
      }
      return put('apps',r.id,{owner:user,name:text(b.name,60,'name'),summary:typeof b.summary==='string'?b.summary.slice(0,160):'',url:safeURL(b.url),kind:'web',supported:true,revision:1,sharedWith:[]});
    }
    const a=app(p[1],user);
    if(p.length===2&&method==='GET')return p[0]==='web-apps'?{appId:a.id,revision:a.revision,manifest:a.manifest}:a;
    if(p.length===2&&method==='DELETE'){app(a.id,user,true);cleanup(a.id);remove('credentials',c=>c.appId===a.id);remove('items',i=>i.appId===a.id);remove('capabilities',c=>c.appId===a.id);remove('jobs',j=>j.appId===a.id);db.delete('apps',a.id);return {ok:true};}
    if(p[2]==='shares'){
      app(a.id,user,true);const who=text(method==='DELETE'?p[3]:b.username,32,'username').toLowerCase();if(!db.get('users',who))fail(404,'User not found');
      if(method==='POST'){if(who!==user&&!a.sharedWith.includes(who))a.sharedWith.push(who);}
      else if(method==='DELETE'){a.sharedWith=a.sharedWith.filter((v:string)=>v!==who);cleanup(a.id,who);remove('capabilities',c=>c.appId===a.id&&c.username===who);}
      else fail(405,'Method not allowed');put('apps',a.id,a);return {ok:true};
    }
    if(p[2]==='notification-credential'){
      app(a.id,user,true);if(!a.manifest)fail(400,'Register a web manifest first');rate('credential:'+a.id,10,3600);remove('credentials',c=>c.appId===a.id);remove('pairings',c=>c.appId===a.id);
      if(method==='POST'){put('credentials',r.secretHash,{appId:a.id});return {appId:a.id};}if(method==='DELETE')return {ok:true};
    }
    if(p[2]==='pairings'&&method==='POST'){if(b.consent!==true||!a.manifest)fail(400,'Explicit notification consent required');rate('pair:'+a.id+user,5);remove('pairings',c=>c.appId===a.id&&c.username===user);put('pairings',r.secretHash,{appId:a.id,username:user,expires:now+300});return {appId:a.id,expiresIn:300,expiresAt:now+300};}
    if(p[2]==='access'&&method==='POST'){put('capabilities',r.secretHash,{appId:a.id,username:user,expires:now+86400});return {appId:a.id,expiresIn:86400};}
  }
  if(p[0]==='notification-subscriptions'){
    if(p.length===1&&method==='GET')return {subscriptions:rows('subscriptions',s=>s.username===user).map(s=>({...s,subscriptionId:s.id,appName:db.get('apps',s.appId)?.name??'App'}))};
    const s=db.get('subscriptions',p[1]);if(!s||s.username!==user)fail(404,'Subscription not found');
    if(method==='DELETE'){cleanup(s!.appId,user);return {ok:true};}
    if(p[2]==='preferences'&&method==='POST'){if(typeof b.notificationsEnabled!=='boolean')fail(400,'Invalid preference');const v=put('subscriptions',s!.id,{...s,notificationsEnabled:b.notificationsEnabled});return {...v,subscriptionId:v.id,appName:db.get('apps',v.appId)?.name??'App'};}
  }
  if(p[0]==='notification-inbox'){
    const all=rows('inbox',n=>n.username===user&&n.createdAt>now-2592000).sort((a,b)=>b.createdAt-a.createdAt||b.id.localeCompare(a.id));
    if(p.length===1&&method==='GET'){let filtered=q.appId?all.filter(n=>n.appId===q.appId):all;const limit=Number(q.limit??50);if(!Number.isInteger(limit)||limit<1||limit>100)fail(400,'Invalid limit');if(q.before){const ix=filtered.findIndex(n=>n.id===q.before);if(ix<0)fail(400,'Invalid cursor');filtered=filtered.slice(ix+1);}const entries=filtered.slice(0,limit);return {entries,unreadCount:all.filter(n=>!n.read).length,nextCursor:filtered.length>limit?entries.at(-1)!.id:null};}
    const n=db.get('inbox',p[1]);if(!n||n.username!==user)fail(404,'Notification unavailable');const a=app(n!.appId,user);
    if(p[2]==='read'&&method==='POST'){put('inbox',n!.id,{...n,read:true});return {ok:true};}
    if(p[2]==='launch'&&method==='GET')return {appId:a.id,target:n!.target,url:originOf(a.url)+safeTarget(n!.target),deepLink:`pocket://app/${a.id}`};
  }
  if(p[0]==='notification-devices'){
    if(method==='POST'){text(b.deviceId,128,'device ID');if(!/^[a-f\d]{64,512}$/i.test(b.token)||!['sandbox','production'].includes(b.environment))fail(400,'Invalid device');put('devices',b.deviceId,{username:user,session:r.auth,token:b.token,environment:b.environment});return {ok:true,deviceId:b.deviceId,deliveryMode:'local'};}
    if(method==='DELETE'){const d=db.get('devices',p[1]);if(d?.username===user)db.delete('devices',p[1]);return {ok:true};}
  }
  return fail(404,'Not found');
}
/** Generated apps use scoped capabilities. No account token enters a miniapp or model. */
export function mini(db:Store,r:Request,now:number):any {
  const p=r.path.split('/').filter(Boolean),a=db.get('apps',p[1]);if(!a?.spec)fail(404,'App unavailable');
  if(p[2]==='spec'&&r.method==='GET')return {spec:a!.spec}; // Only presentation metadata is public.
  const c=db.get('capabilities',r.auth);if(!c||c.appId!==a!.id||c.expires<=now||!(a!.owner===c.username||a!.sharedWith.includes(c.username)))fail(401,'Open this app using a fresh Pocket access link');
  const all=db.all('items').filter(i=>i.appId===a!.id);
  if(r.method==='GET')return {items:all,revision:a!.revision};
  if(r.method==='POST'){
    if(all.length>=1000)fail(409,'This app has reached 1,000 entries');const data=r.body.data;if(!data||Array.isArray(data))fail(400,'Invalid entry');
    const spec=validateSpec(a!.spec);if(Object.keys(data).some(k=>!spec.fields.some((f:any)=>f.key===k)))fail(400,'Unknown field');
    for(const f of spec.fields){const v=data[f.key],expected=['text','choice'].includes(f.type)?'string':f.type;if(typeof v!==expected||(typeof v==='string'&&v.length>500)||(typeof v==='number'&&!Number.isFinite(v))||(f.type==='choice'&&!f.options.includes(v)))fail(400,'Check '+f.label);}
    const item={id:r.id,appId:a!.id,data,author:c!.username,createdAt:now};db.put('items',r.id,item);return item;
  }
  if(r.method==='DELETE'){const item=db.get('items',p[3]);if(!item||item.appId!==a!.id||(item.author!==c!.username&&a!.owner!==c!.username))fail(404,'Entry unavailable');db.delete('items',item!.id);return {ok:true};}
  return fail(405,'Method not allowed');
}
