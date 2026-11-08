#!/usr/bin/env node
import { createInterface } from 'node:readline';
import { init, inspect, login, register, registerURL, notificationTest, rotateCredential, revokeCredential } from './services.ts';
import { validate } from './validation.ts';
const str={type:'string'},obj={type:'object'};
function tool(name:string,description:string,properties:Record<string,unknown>,required=Object.keys(properties)){return {name,description,inputSchema:{type:'object',properties,required,additionalProperties:false}};}
export const toolDefinitions=[
 tool('init','Create local web listing and static app scaffold',{directory:str}),
 tool('validate','Validate listing JSON locally; no fetch or execution',{manifest:obj}),
 tool('preview','Inspect listing metadata only; no registration, fetch or execution',{manifest:obj}),
 tool('login','Sign in using POCKET_PASSWORD from environment; never returns token',{backend:str,username:str}),
 tool('register','Explicitly register or update a creator-hosted web listing',{backend:str,manifest:obj}),
 tool('register-url','Explicitly add a basic URL listing; no notification integration',{backend:str,url:str,name:str,summary:str},['backend','url','name']),
 tool('notification-test','Explicitly send a real inbox event using app credential from environment',{backend:str,event:obj}),
 tool('credential-rotate','Explicitly rotate app credential and save to exclusive local file; never return secret',{backend:str,appId:str,out:str}),
 tool('credential-revoke','Explicitly revoke the app notification credential',{backend:str,appId:str})
];
export async function callTool(name:string,a:any){
 const def=toolDefinitions.find(t=>t.name===name);if(!def)throw Error('Unknown or obsolete tool');
 if(!a || typeof a!=='object' || Array.isArray(a) || Object.keys(a).some(k=>!(k in def.inputSchema.properties)) || def.inputSchema.required.some(k=>!(k in a)))throw Error('Invalid tool arguments');
 for(const [k,v] of Object.entries(a))if(typeof v!==(def.inputSchema.properties[k] as any).type || v===null || Array.isArray(v))throw Error('Invalid tool argument type');
 switch(name){
 case 'init':return init(a.directory);
 case 'validate':validate(a.manifest);return {valid:true,registered:false};
 case 'preview':return inspect(a.manifest);
 case 'login':if(!process.env.POCKET_PASSWORD)throw Error('POCKET_PASSWORD required');return login(a.backend,a.username,process.env.POCKET_PASSWORD);
 case 'register':return register(a.backend,a.manifest);
 case 'register-url':return registerURL(a.backend,a.url,a.name,a.summary);
 case 'notification-test':return notificationTest(a.backend,a.event);
 case 'credential-rotate':return rotateCredential(a.backend,a.appId,a.out);
 case 'credential-revoke':return revokeCredential(a.backend,a.appId);
 }
}
const input=createInterface({input:process.stdin,crlfDelay:Infinity});
for await (const line of input) {
 let m:any;
 try {
  if(Buffer.byteLength(line)>100000)throw Error('Request too large'); m=JSON.parse(line);
  if(m.id===undefined)continue;
  let result;
  if(m.jsonrpc!=='2.0')throw Error('Invalid JSON-RPC');
  if(m.method==='initialize')result={protocolVersion:'2024-11-05',capabilities:{tools:{}},serverInfo:{name:'pocket-creator',version:'0.3.0'}};
  else if(m.method==='ping')result={};
  else if(m.method==='tools/list')result={tools:toolDefinitions};
  else if(m.method==='tools/call') {try {result={content:[{type:'text',text:JSON.stringify(await callTool(m.params?.name,m.params?.arguments))}]};}catch(e){result={isError:true,content:[{type:'text',text:e instanceof Error?e.message:'Tool failed'}]};}}
  else {console.log(JSON.stringify({jsonrpc:'2.0',id:m.id,error:{code:-32601,message:'Method not found'}}));continue;}
  console.log(JSON.stringify({jsonrpc:'2.0',id:m.id,result}));
 }catch{console.log(JSON.stringify({jsonrpc:'2.0',id:m?.id??null,error:{code:-32600,message:'Invalid request'}}));}
}
