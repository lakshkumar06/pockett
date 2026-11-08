import {readFile,writeFile,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {resolve,join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';
export type Plan={provider:'vultr';domain:string;region:string;plan:string;os_id:number;sshkey_id:string[];label:string;user_data:string};
const root=fileURLToPath(new URL('../../',import.meta.url));
export async function cloudPlan(domain:string,out:string,region:string,plan:string,osId:string,sshKeyId:string):Promise<any>{
 if(!/^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/.test(domain))throw Error('A public domain is required for HTTPS');
 if(!region||!plan||!sshKeyId||!/^\d+$/.test(osId))throw Error('Region, plan, numeric OS ID and SSH key ID are required');
 const value:Plan={provider:'vultr',domain,region,plan,os_id:Number(osId),sshkey_id:[sshKeyId],label:'pockett',user_data:Buffer.from(await readFile(resolve(root,'deploy/cloud-init.yaml'),'utf8')).toString('base64')};
 await writeFile(out,JSON.stringify(value,null,2)+'\n',{flag:'wx',mode:0o600});
 return {planFile:resolve(out),createsResources:false,next:'Review this file. cloud-deploy requires an explicit monthly price ceiling and live provider preflight.'};
}
async function vultr(path:string,body?:unknown){
 const key=process.env.VULTR_API_KEY;if(!key)throw Error('VULTR_API_KEY required');
 const r=await fetch('https://api.vultr.com/v2'+path,{method:body?'POST':'GET',headers:{Authorization:'Bearer '+key,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined,signal:AbortSignal.timeout(30000),redirect:'error'});
 if(!r.ok){await r.body?.cancel();throw Error(`Vultr request failed (${r.status})`);}return r.json() as Promise<any>;
}
export function checkPrice(plan:Plan,plans:any[],available:string[],max:number){
 const selected=plans.find(p=>p.id===plan.plan);if(!selected||!available.includes(plan.plan))throw Error('Plan unavailable in the chosen region');
 if(!Number.isFinite(max)||max<=0||typeof selected.monthly_cost!=='number'||selected.monthly_cost>max)throw Error('Plan exceeds monthly price ceiling or price is unavailable');return selected.monthly_cost;
}
export async function cloudDeploy(file:string,maxMonthly:number){
 const p:Plan=JSON.parse(await readFile(file,'utf8'));if(p.provider!=='vultr'||!p.domain||p.label!=='pockett'||!p.sshkey_id?.length)throw Error('Invalid Pocket deployment plan');
 // Validate against the fixed bootstrap. A plan cannot smuggle a replacement startup script.
 const expected=Buffer.from(await readFile(resolve(root,'deploy/cloud-init.yaml'),'utf8')).toString('base64');if(p.user_data!==expected)throw Error('Bootstrap differs from the reviewed Pocket template');
 const [pricing,availability]=await Promise.all([vultr('/plans?per_page=500'),vultr('/regions/'+encodeURIComponent(p.region)+'/availability')]);
 const monthly=checkPrice(p,pricing.plans,availability.available_plans,maxMonthly);
 const domain=p.domain;const payload={region:p.region,plan:p.plan,os_id:p.os_id,sshkey_id:p.sshkey_id,label:p.label,user_data:p.user_data};
 const result=await vultr('/instances',payload);const instance=result.instance;if(!instance?.id)throw Error('Provider returned an unexpected creation result; check Vultr before retrying');
 return {instanceId:instance.id,estimatedMonthly:monthly,domain,state:instance.status,next:'Wait for the instance to become active, point your domain to its IPv4 address, then run pocket cloud-upload <IPv4>. This command creates one server; it does not upload credentials.'};
}
function run(bin:string,args:string[],cwd=root){return new Promise<void>((resolve,reject)=>{const child=spawn(bin,args,{cwd,stdio:'inherit'});child.on('error',()=>reject(Error('Could not run '+bin)));child.on('exit',code=>code===0?resolve():reject(Error(bin+' failed')));});}
export async function cloudUpload(host:string){
 if(!/^(?:\d{1,3}\.){3}\d{1,3}$/.test(host)||host.split('.').some(x=>Number(x)>255))throw Error('Use the Vultr instance IPv4 address');
 const env=await readFile(resolve(root,'.env'),'utf8');
 if(!/^SPACETIME_TOKEN=.+$/m.test(env)||!/^SPACETIME_URL=https:\/\//m.test(env)||!/^POCKET_PUBLIC_ORIGIN=https:\/\//m.test(env)||!/^POCKET_DOMAIN=[a-z0-9.-]+$/m.test(env))throw Error('Configure .env with a remote HTTPS Spacetime backend, publisher token, POCKET_PUBLIC_ORIGIN, and POCKET_DOMAIN first');
 // Keys travel over SSH, never through cloud-init or the provider API.
 const dir=await mkdtemp(join(tmpdir(),'pocket-deploy-'));const archive=join(dir,'runtime.tgz');
 const runtimeEnv=env.split(/\r?\n/).filter(line=>/^(?:HOST|PORT|POCKET_[A-Z_]+|SPACETIME_[A-Z_]+|NVIDIA_[A-Z_]+|NEMOTRON_MODEL|PHOTON_[A-Z_]+)=/.test(line)).join('\n')+'\n';
 await writeFile(join(dir,'.env'),runtimeEnv,{mode:0o600});
 try{
  await run('tar',['--exclude=node_modules','--exclude=dist','--exclude=.runtime','-czf',archive,'Runtime','Spacetime/spacetimedb/src','Spacetime/spacetimedb/package.json','Spacetime/spacetimedb/package-lock.json','deploy','-C',dir,'.env']);
  await run('ssh',['-o','StrictHostKeyChecking=accept-new',`root@${host}`,'cloud-init status --wait && mkdir -p /opt/pocket && chmod 700 /opt/pocket']);
  await run('scp',['-o','StrictHostKeyChecking=accept-new',archive,`root@${host}:/opt/pocket/runtime.tgz`]);
  await run('ssh',['-o','StrictHostKeyChecking=accept-new',`root@${host}`,'cd /opt/pocket && tar -xzf runtime.tgz && chmod 600 .env && rm runtime.tgz && docker compose --env-file .env -f deploy/compose.yaml up -d --build']);
  return {uploaded:true,host,message:'Gateway and worker started. Check your HTTPS /health endpoint and test a build.'};
 }finally{await rm(dir,{recursive:true,force:true});}
}
