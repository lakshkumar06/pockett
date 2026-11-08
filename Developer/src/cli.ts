#!/usr/bin/env node
import { cloudPlan, cloudDeploy, cloudUpload } from './cloud.ts';
import { readFile } from 'node:fs/promises';
import { init, loadConfiguration, inspect, login, register, registerURL, notificationTest, rotateCredential, revokeCredential, buildApp, buildStatus, publishApp, connectPhoton, openApp } from './services.ts';
const [command,...args]=process.argv.slice(2);
const options:Record<string,string[]>={'cloud-plan':['--out','--region','--plan','--os-id','--ssh-key-id'],'cloud-deploy':['--max-monthly'],'cloud-upload':[],build:['--backend','--app'],status:['--backend'],publish:['--backend'],'connect-photon':['--backend'],open:['--backend'],init:[],validate:[],preview:[],login:['--backend','--username'],register:['--backend'],'register-url':['--backend','--name','--summary'],'notification-test':['--backend'],'credential-rotate':['--backend','--out'],'credential-revoke':['--backend']};
function option(name:string){const i=args.indexOf(name);return i<0?undefined:args[i+1];}
function required(value:string|undefined,name:string){if(!value)throw Error(`${name} required`);return value;}
try{

 if(!(command in options))throw Error('Usage: pocket init|validate|preview|login|register|register-url|notification-test|credential-rotate|credential-revoke|build|status|publish|open|connect-photon');
 if(!['login','connect-photon'].includes(command) && (!args[0] || args[0].startsWith('--')))throw Error('Path, URL or app ID required');
 const seen=new Set<string>();for(let i=['login','connect-photon'].includes(command)?0:1;i<args.length;i+=2){if(!options[command].includes(args[i]) || seen.has(args[i]) || !args[i+1] || args[i+1].startsWith('--'))throw Error('Unknown, duplicate or missing option');seen.add(args[i]);}
 const base=option('--backend')??'http://127.0.0.1:8787';let result;
 switch(command){
 case 'cloud-plan':result=await cloudPlan(args[0],required(option('--out'),'--out'),required(option('--region'),'--region'),required(option('--plan'),'--plan'),required(option('--os-id'),'--os-id'),required(option('--ssh-key-id'),'--ssh-key-id'));break;
 case 'cloud-deploy':result=await cloudDeploy(args[0],Number(required(option('--max-monthly'),'--max-monthly')));break;
 case 'cloud-upload':result=await cloudUpload(args[0]);break;
 case 'build':result=await buildApp(base,args[0],option('--app'));break;
 case 'status':result=await buildStatus(base,args[0]);break;
 case 'publish':result=await publishApp(base,args[0]);break;
 case 'connect-photon':result=await connectPhoton(base);break;
 case 'open':result=await openApp(base,args[0]);break;
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
