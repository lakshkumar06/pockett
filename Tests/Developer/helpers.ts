import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {readFile,mkdtemp,rm} from 'node:fs/promises';
import {resolve} from 'node:path';
import {tmpdir} from 'node:os';
export const root=resolve(import.meta.dirname,'../..');
export const flow=JSON.parse(await readFile(resolve(root,'Developer/Contracts/web-v1/fixtures/flow.json'),'utf8'));
export async function run(file:string,args:string[]=[],input?:string,env:Record<string,string|undefined>={}) {
 const child=spawn(process.execPath,[resolve(root,file),...args],{cwd:root,env:{...process.env,...env},stdio:['pipe','pipe','pipe']});let stdout='',stderr='';
 child.stdout.on('data',b=>stdout+=b);child.stderr.on('data',b=>stderr+=b);child.stdin.end(input);const [code]=await once(child,'exit');return {code,stdout,stderr};
}
export async function rpc(name:string,args:any,env:Record<string,string|undefined>={}){const r=await run('Developer/src/mcp.ts',[],JSON.stringify({jsonrpc:'2.0',id:1,method:'tools/call',params:{name,arguments:args}})+'\n',env);if(r.code!==0)throw Error(r.stderr);return JSON.parse(r.stdout).result;}
export async function startBackend(){
 const dir=await mkdtemp(resolve(tmpdir(),'pocket-web-'));const server=spawn('python3',['-u','-c',"import sys;sys.path.insert(0,'Backend');from server import make_server;s=make_server('127.0.0.1',0,sys.argv[1]);print(s.server_port,flush=True);s.serve_forever()",resolve(dir,'test.sqlite3')],{cwd:root,stdio:['ignore','pipe','pipe'],env:{...process.env,PYTHONDONTWRITEBYTECODE:'1'}});
 let errors='';server.stderr.on('data',b=>errors+=b);
 async function close(){if(server.exitCode===null && server.signalCode===null){const exited=once(server,'exit');server.kill();await exited;}await rm(dir,{recursive:true,force:true});}
 try{const port=await new Promise<string>((accept,reject)=>{const timer=setTimeout(()=>reject(Error('Backend startup timeout')),10000);server.stdout.once('data',b=>{clearTimeout(timer);accept(b.toString().trim());});server.once('error',e=>{clearTimeout(timer);reject(e);});server.once('exit',()=>{clearTimeout(timer);reject(Error('Backend startup failed: '+errors));});});return {base:`http://127.0.0.1:${port}`,dir,close};}catch(e){await close();throw e;}
}
export async function api(base:string,path:string,token?:string,body?:unknown,method=body===undefined?'GET':'POST') {const r=await fetch(base+path,{method,headers:{'Content-Type':'application/json',...(token?{Authorization:`Bearer ${token}`}:{})},body:body===undefined?undefined:JSON.stringify(body)});return {status:r.status,body:await r.json() as any};}
