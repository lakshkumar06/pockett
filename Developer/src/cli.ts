#!/usr/bin/env node
import { readFile } from 'node:fs/promises';
import { init, loadConfiguration, inspect, login, register, registerURL, notificationTest, rotateCredential, revokeCredential } from './services.ts';
const [command,...args]=process.argv.slice(2);
const options:Record<string,string[]>={init:[],validate:[],preview:[],login:['--backend','--username'],register:['--backend'],'register-url':['--backend','--name','--summary'],'notification-test':['--backend'],'credential-rotate':['--backend','--out'],'credential-revoke':['--backend']};
function option(name:string){const i=args.indexOf(name);return i<0?undefined:args[i+1];}
function required(value:string|undefined,name:string){if(!value)throw Error(`${name} required`);return value;}
try{
 if(['build','publish','plan'].includes(command))throw Error(`${command} is obsolete. Use validate/preview for listing metadata and register for explicit web registration. Pocket does not build or host app code.`);
 if(!(command in options))throw Error('Usage: pocket init|validate|preview|login|register|register-url|notification-test|credential-rotate|credential-revoke');
 if(command!=='login' && (!args[0] || args[0].startsWith('--')))throw Error('Path, URL or app ID required');
 const seen=new Set<string>();for(let i=command==='login'?0:1;i<args.length;i+=2){if(!options[command].includes(args[i]) || seen.has(args[i]) || !args[i+1] || args[i+1].startsWith('--'))throw Error('Unknown, duplicate or missing option');seen.add(args[i]);}
 const base=option('--backend')??'http://127.0.0.1:8787';let result;
 switch(command){
 case 'init':result=await init(args[0]);break;
 case 'validate':await loadConfiguration(args[0]);result={valid:true,registered:false};break;
 case 'preview':result=inspect(await loadConfiguration(args[0]));break;
 case 'login':result=await login(base,required(option('--username'),'--username'),required(process.env.POCKET_PASSWORD,'POCKET_PASSWORD'));break;
 case 'register':result=await register(base,await loadConfiguration(args[0]));break;
 case 'register-url':result=await registerURL(base,args[0],required(option('--name'),'--name'),option('--summary'));break;
 case 'notification-test':result=await notificationTest(base,JSON.parse(await readFile(args[0],'utf8')));break;
 case 'credential-rotate':result=await rotateCredential(base,args[0],required(option('--out'),'--out'));break;
 case 'credential-revoke':result=await revokeCredential(base,args[0]);break;
 }
 console.log(JSON.stringify(result,null,2));
}catch(e){console.error(e instanceof SyntaxError?'Invalid JSON':e instanceof Error?e.message:'Command failed');process.exitCode=1;}
