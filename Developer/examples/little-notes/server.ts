/** Local-only creator backend example. Own sessions, no Pocket account tokens. */
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { NotificationClient } from '../../src/server.ts';
const port=Number(process.env.NOTES_PORT??8788),host='127.0.0.1';
const publicDir=process.env.NOTES_PUBLIC_DIR??fileURLToPath(new URL('./public',import.meta.url));
const browserDir=fileURLToPath(new URL('../../dist/browser',import.meta.url));
const password=process.env.NOTES_PASSWORD??'local-demo-password';
let appCredential=process.env.POCKET_APP_CREDENTIAL??'';
if(!appCredential && process.env.POCKET_APP_CREDENTIAL_FILE)appCredential=(await readFile(process.env.POCKET_APP_CREDENTIAL_FILE,'utf8')).trim();
const client=new NotificationClient({backend:process.env.POCKET_BACKEND??'http://127.0.0.1:8787',credential:appCredential});
const sessions=new Map<string,{csrf:string;signedIn:boolean;subscriptionId?:string;expires:number}>();
const server=createServer(async(req,res)=>{
 const reply=(status:number,data:unknown)=>{res.writeHead(status,{'Content-Type':'application/json','Cache-Control':'no-store'});res.end(JSON.stringify(data));};
 try{
  const origin=`http://${host}:${(server.address() as any).port}`;
  if(req.headers.host!==new URL(origin).host)return reply(403,{error:'Invalid host'});
  const path=new URL(req.url??'/',origin).pathname;
  if(req.method==='GET' && !path.startsWith('/api/')){
   const files:Record<string,[string,string]>={'/style.css':['style.css','text/css'],'/app.js':['app.js','text/javascript'],'/icon.svg':['icon.svg','image/svg+xml']};
   let file,mime;
   if(['/','/notes/42'].includes(path)){file=resolve(publicDir,'index.html');mime='text/html';}
   else if(files[path]){file=resolve(publicDir,files[path][0]);mime=files[path][1];}
   else if(['/sdk/browser.js','/sdk/targets.js','/sdk/web-types.js'].includes(path)){file=resolve(browserDir,path.split('/').at(-1)!);mime='text/javascript';}
   else return reply(404,{error:'Page not found'});
   res.writeHead(200,{'Content-Type':mime,'X-Content-Type-Options':'nosniff','Content-Security-Policy':"default-src 'self'; style-src 'self' 'unsafe-inline'; script-src 'self'; frame-ancestors 'none'",'Referrer-Policy':'no-referrer'});res.end(await readFile(file));return;
  }
  for(const [key,value] of sessions)if(value.expires<Date.now())sessions.delete(key);
  const cookie=req.headers.cookie?.split(';').map(s=>s.trim()).find(s=>s.startsWith('notes_session='))?.slice(14);
  let id=cookie,s=id?sessions.get(id):undefined;
  if(!s){if(sessions.size>=1000)return reply(429,{error:'Try later'});id=randomBytes(24).toString('hex');s={csrf:randomBytes(24).toString('hex'),signedIn:false,expires:Date.now()+3600000};sessions.set(id,s);res.setHeader('Set-Cookie',`notes_session=${id}; HttpOnly; SameSite=Strict; Path=/; Max-Age=3600`);}
  if(req.method==='GET' && path==='/api/session')return reply(200,{signedIn:s.signedIn,paired:!!s.subscriptionId,csrfToken:s.csrf});
  if(req.method!=='POST')return reply(404,{error:'Not found'});
  if(req.headers.origin!==origin || req.headers['x-csrf-token']!==s.csrf)return reply(403,{error:'Invalid request origin or CSRF token'});
  let raw='';for await(const chunk of req){raw+=chunk;if(Buffer.byteLength(raw)>4096)return reply(400,{error:'Request too large'});}
  let body;try{body=JSON.parse(raw);}catch{return reply(400,{error:'Invalid JSON'});}
  if(path==='/api/login'){
   const a=Buffer.from(typeof body.password==='string'?body.password:''),b=Buffer.from(password);
   if(a.length!==b.length || !timingSafeEqual(a,b))return reply(401,{error:'Incorrect demo password'});
   s.signedIn=true;return reply(200,{ok:true});
  }
  if(!s.signedIn)return reply(401,{error:'Sign in to Little Notes first'});
  if(path==='/api/logout'){sessions.delete(id!);res.setHeader('Set-Cookie','notes_session=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0');return reply(200,{ok:true});}
  if(path==='/api/pair'){
   if(body.consent!==true || Object.keys(body).sort().join(',')!=='consent,pairingCode')return reply(400,{error:'Consent required'});
   const result=await client.redeemPairing(body.pairingCode);s.subscriptionId=result.subscriptionId;return reply(200,{paired:true});
  }
  if(path==='/api/remind'){
   if(!s.subscriptionId)return reply(409,{error:'Connect Pocket reminders first'});
   if(Object.keys(body).join(',')!=='idempotencyKey')return reply(400,{error:'Invalid reminder'});
   return reply(200,await client.send({idempotencyKey:body.idempotencyKey,subscriptionId:s.subscriptionId,title:'Your note is ready',body:'Open the note you saved for later.',target:'/notes/42?view=full#content'}));
  }
  reply(404,{error:'Not found'});
 }catch{reply(400,{error:'Request failed. Check your connection or reconnect Pocket reminders.'});}
});
server.listen(port,host,()=>console.log(`Little Notes: http://${host}:${(server.address() as any).port} (local development only)`));
