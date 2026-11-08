import { readFileSync } from 'node:fs';
import { Ajv } from 'ajv';
import { validate as legacyValidate } from './legacy-validation.ts';
import { webURL, safeTarget } from './targets.ts';
import type { WebManifest, NotificationEvent } from './web-types.ts';
const schema=JSON.parse(readFileSync(new URL('../Contracts/web-v1/manifest.schema.json',import.meta.url),'utf8'));
const check=new Ajv({allErrors:true}).compile<WebManifest>(schema);
function jsonOnly(v:unknown,depth=0):void {
  if(depth>8)throw Error('JSON nesting exceeds limit');
  if(v===null || typeof v==='string' || typeof v==='boolean' || (typeof v==='number' && Number.isFinite(v)))return;
  if(typeof v!=='object' || (!Array.isArray(v) && ![Object.prototype,null].includes(Object.getPrototypeOf(v))))throw Error('Use plain JSON values');
  for(const child of Object.values(v))jsonOnly(child,depth+1);
}
export function validateManifest(value:unknown): WebManifest {
  jsonOnly(value);
  if(Buffer.byteLength(JSON.stringify(value))>8192 || !check(value))throw Error('Invalid web-v1 listing manifest');
  for(const text of [value.name,value.summary,value.version])if(!text.trim() || /[\x00-\x1f\x7f]/.test(text))throw Error('Listing text must be nonblank without control characters');
  webURL(value.entryURL);webURL(value.iconURL,false);
  return structuredClone(value);
}
export function validate(value:unknown): any {
  if((value as any)?.schemaVersion==='web-v1')return validateManifest(value);
  return legacyValidate(value);
}
export function validateEvent(value:unknown): NotificationEvent {
  jsonOnly(value);const d=value as NotificationEvent;
  if(!d || typeof d!=='object' || Object.keys(d).sort().join(',')!=='body,idempotencyKey,subscriptionId,target,title' || Buffer.byteLength(JSON.stringify(d))>4096)throw Error('Invalid notification event');
  if(typeof d.idempotencyKey!=='string' || !/^[A-Za-z0-9_-]{1,64}$/.test(d.idempotencyKey) || typeof d.subscriptionId!=='string' || !/^[A-Za-z0-9_-]{1,128}$/.test(d.subscriptionId))throw Error('Invalid event identifier');
  for(const [value,max] of [[d.title,80],[d.body,240]] as const)if(typeof value!=='string' || !value.trim() || [...value].length>max || /[\x00-\x1f\x7f]/.test(value))throw Error('Invalid event text');
  safeTarget(d.target);return structuredClone(d);
}
