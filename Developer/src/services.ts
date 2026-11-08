import { readFile, writeFile, mkdir, chmod, cp } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { validate, validateManifest } from './validation.ts';
import { backendURL, request, opaque } from './http.ts';
import { webURL } from './targets.ts';
import { NotificationClient } from './server.ts';
import type { Registration } from './web-types.ts';
export {backendURL};
export const credentialsPath=()=>process.env.POCKET_CREDENTIALS_FILE||resolve(homedir(),'.config/pocket/credentials.json');
export async function loadConfiguration(file:string) {
  const raw=await readFile(resolve(file),'utf8');if(Buffer.byteLength(raw)>65536)throw Error('Manifest file too large');return validate(JSON.parse(raw));
}
export function inspect(configuration:unknown) {
  const manifest=validate(configuration);
  return {mode:'listing-inspection',registered:false,executesCode:false,legacy:manifest.schemaVersion!=='web-v1',manifest,message:'Metadata inspection only. Pocket opens the creator-hosted website; this preview does not fetch, register, host or execute app code.'};
}
export async function init(directory:string) {
  await readFile(new URL('../dist/browser/browser.js',import.meta.url)).catch(()=>{throw Error('Run npm --prefix Developer run build:browser before init');});
  const target=resolve(directory);
  await mkdir(target,{recursive:true});
  // Exclusive manifest acts as a guard; never overwrite an existing creator project.
  const fixture=await readFile(new URL('../Contracts/web-v1/fixtures/manifest.json',import.meta.url),'utf8');
  await writeFile(resolve(target,'pocket.manifest.json'),fixture,{flag:'wx'});
  await cp(fileURLToPath(new URL('../examples/little-notes/public',import.meta.url)),resolve(target,'public'),{recursive:true,errorOnExist:true,force:false});
  await cp(fileURLToPath(new URL('../dist/browser',import.meta.url)),resolve(target,'public/sdk'),{recursive:true,errorOnExist:true,force:false});
  await writeFile(resolve(target,'README.md'),'# Creator-owned web app\nServe public/ with your own web host. Edit pocket.manifest.json to reference it, then use pocket register. The copied Little Notes UI requires the optional example backend for login/reminders; see Developer/examples/little-notes/README.md in the Pocket checkout. No native UI JSON is generated.\n',{flag:'wx'});
  return {created:target,message:'Edit pocket.manifest.json with your hosted URLs. Static interface copied to public/. See Developer/examples/little-notes for the optional backend integration.'};
}
export async function login(base:string,username:string,password:string) {
  base=backendURL(base);
  // Existing login endpoint is account credential exchange, not app credential authentication.
  const result=await request(base,'/login',{username,password},'login');
  if(typeof result.token!=='string' || !result.token || /\s/.test(result.token))throw Error('Invalid login confirmation');
  const file=credentialsPath();await mkdir(dirname(file),{recursive:true,mode:0o700});
  await writeFile(file,JSON.stringify({backend:base,token:result.token}),{mode:0o600});await chmod(file,0o600);
  return {authenticated:true,backend:base};
}
async function credentials(base:string):Promise<string> {
  if(process.env.POCKET_TOKEN)return process.env.POCKET_TOKEN;
  let c;try{c=JSON.parse(await readFile(credentialsPath(),'utf8'));}catch{throw Error('Login required');}
  if(c.backend!==backendURL(base) || typeof c.token!=='string' || !c.token)throw Error('Login required for this backend');return c.token;
}
function registration(result:any):Registration {
  if(!opaque(result?.appId) || !Number.isSafeInteger(result.revision) || result.revision<1 || result.deepLink!==`pocket://app/${result.appId}`)throw Error('Invalid registration confirmation');
  return {appId:result.appId,revision:result.revision,deepLink:result.deepLink};
}
export async function register(base:string,value:unknown):Promise<Registration> {
  const manifest=validateManifest(value);return registration(await request(base,'/web-apps',{manifest},await credentials(base)));
}
export async function registerURL(base:string,url:string,name:string,summary='') {
  webURL(url);if(!name.trim() || [...name].length>60 || [...summary].length>160)throw Error('Invalid listing name or summary');
  const result=await request(base,'/apps',{name,url,summary},await credentials(base));
  if(!opaque(result?.id) || result.url!==url)throw Error('Invalid URL registration confirmation');
  return {appId:result.id,deepLink:`pocket://app/${result.id}`,mode:'basic-url',notifications:false};
}
/** Secret is written exclusively to the specified file; never returned to CLI/MCP. */
export async function rotateCredential(base:string,appId:string,out:string) {
  if(!opaque(appId))throw Error('Invalid app ID');
  const file=resolve(out);
  // Reserve before rotation to avoid destroying a live credential when the path is not writable.
  const {open}=await import('node:fs/promises');const handle=await open(file,'wx',0o600);
  try{
    const r=await request(base,`/apps/${appId}/notification-credential`,{},await credentials(base));
    if(r?.appId!==appId || typeof r.credential!=='string' || !r.credential || /\s/.test(r.credential))throw Error('Invalid credential confirmation');
    await handle.writeFile(r.credential+'\n');
    return {appId,credentialFile:file,rotated:true};
  }finally{await handle.close();}
}
export async function revokeCredential(base:string,appId:string) {
  if(!opaque(appId))throw Error('Invalid app ID');const r=await request(base,`/apps/${appId}/notification-credential`,undefined,await credentials(base),'DELETE');if(r?.ok!==true)throw Error('Invalid revocation confirmation');return {revoked:true,appId};
}
export async function notificationTest(base:string,event:unknown) {
  let credential=process.env.POCKET_APP_CREDENTIAL;
  if(!credential && process.env.POCKET_APP_CREDENTIAL_FILE)credential=(await readFile(process.env.POCKET_APP_CREDENTIAL_FILE,'utf8')).trim();
  if(!credential)throw Error('Set POCKET_APP_CREDENTIAL or POCKET_APP_CREDENTIAL_FILE on the creator backend');
  return new NotificationClient({backend:base,credential}).send(event);
}
