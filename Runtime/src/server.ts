import {createServer} from 'node:http';
import {scrypt as derive,randomBytes} from 'node:crypto';
import {promisify} from 'node:util';
import {pathToFileURL} from 'node:url';
import {call,envelope,hash,secret,ApiError,publicOrigin} from './spacetime.ts';
import {render} from './template.ts';
const scrypt=promisify(derive);
export function createGateway(invoke=call){
  const attempts=new Map<string,{n:number,until:number}>();
  return createServer(async(req,res)=>{
    res.setHeader('Cache-Control','no-store');res.setHeader('X-Content-Type-Options','nosniff');res.setHeader('Referrer-Policy','no-referrer');
    try{
      const u=new URL(req.url??'/',publicOrigin()),method=req.method??'GET';
      if(req.headers.origin&&req.headers.origin!==publicOrigin())throw new ApiError(403,'Origin not allowed');
      if(u.pathname.startsWith('/internal/'))throw new ApiError(404,'Not found');
      if(u.pathname==='/health'){res.setHeader('Content-Type','application/json');res.end(JSON.stringify({service:'pocket',state:'spacetime',configured:!!process.env.SPACETIME_TOKEN}));return;}
      if(u.pathname==='/icon.svg'){res.setHeader('Content-Type','image/svg+xml');res.end('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><rect width="64" height="64" rx="16" fill="#316849"/><path d="M17 20h30v17q-15 21-30 0z" fill="#f7f5ee"/><path d="m25 29 7 7 7-7" fill="none" stroke="#316849" stroke-width="4"/></svg>');return;}
      const page=u.pathname.match(/^\/mini\/([\w-]+)\/$/);
      if(page&&method==='GET'){const result=await invoke(envelope('GET',`/mini/${page[1]}/spec`));res.setHeader('Content-Type','text/html; charset=utf-8');res.setHeader('Content-Security-Policy',"default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; img-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'");res.end(render(result.spec,page[1]));return;}
      let raw='';for await(const chunk of req){raw+=chunk;if(Buffer.byteLength(raw)>16384)throw new ApiError(413,'Request too large');}
      let body:any;try{body=raw?JSON.parse(raw):{};}catch{throw new ApiError(400,'Invalid JSON');}
      if(!body||typeof body!=='object'||Array.isArray(body))throw new ApiError(400,'Expected a JSON object');
      const token=typeof req.headers.authorization==='string'?req.headers.authorization.replace(/^Bearer /,''):'';
      const generated=secret();const request=envelope(method,u.pathname,{...body,publicOrigin:publicOrigin()},token,{secretHash:hash(generated),query:Object.fromEntries(u.searchParams)});
      if(['/login','/signup'].includes(u.pathname)&&method==='POST'){
        const ip=req.socket.remoteAddress??'unknown';const now=Date.now();if(attempts.size>10000)for(const [key,v]of attempts)if(v.until<now)attempts.delete(key);
        const limit=attempts.get(ip)??{n:0,until:now+60000};if(limit.until<now){limit.n=0;limit.until=now+60000;}attempts.set(ip,limit);if(++limit.n>20)throw new ApiError(429,'Please try again later');
        if(typeof body.password!=='string'||body.password.length<8||body.password.length>1024||typeof body.username!=='string')throw new ApiError(400,'Use a password of 8–1,024 characters');
        body.username=body.username.toLowerCase();const auth=await invoke(envelope('POST','/internal/auth',{username:body.username}));
        const salt=auth.salt??randomBytes(16).toString('hex');request.salt=salt;request.proof=(await scrypt(body.password,salt,64) as Buffer).toString('hex');request.body={username:body.username};
      }
      if(u.pathname==='/notification-pairings/redeem'){request.body.pairingHash=hash(String(body.pairingCode??''));delete request.body.pairingCode;}
      const result=await invoke(request);
      if(['/login','/signup'].includes(u.pathname)&&method==='POST')result.token=generated;
      if(u.pathname.endsWith('/notification-credential')&&method==='POST')result.credential=generated;
      if(u.pathname.endsWith('/pairings')&&method==='POST')result.pairingCode=generated;
      if(u.pathname==='/photon-link'&&method==='POST')result.code=generated;
      if(u.pathname.endsWith('/access')&&method==='POST')result.url=`${publicOrigin()}/mini/${result.appId}/#access=${generated}`;
      res.setHeader('Content-Type','application/json');res.end(JSON.stringify(result));
    }catch(error){res.statusCode=error instanceof ApiError?error.status:500;res.setHeader('Content-Type','application/json');res.end(JSON.stringify({error:error instanceof ApiError?error.message:'Request failed'}));}
  });
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){const server=createGateway();server.requestTimeout=20000;server.listen(Number(process.env.PORT??8787),process.env.HOST??'127.0.0.1',()=>console.log('Pocket gateway listening'));}
