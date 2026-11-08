import {randomBytes,randomUUID,createHash} from 'node:crypto';
import type {Request} from '../../Spacetime/spacetimedb/src/domain.ts';
export const hash=(s:string)=>createHash('sha256').update(s).digest('hex');
export const secret=()=>randomBytes(32).toString('base64url');
export class ApiError extends Error {status:number;constructor(status:number,message:string){super(message);this.status=status;}}
export function envelope(method:string,path:string,body:any={},auth='',extra:Partial<Request>={}):Request {
  return {method,path,body,auth:hash(auth),id:randomUUID(),secretHash:hash(secret()),...extra};
}
export async function call(request:Request):Promise<any>{
  const origin=process.env.SPACETIME_URL??'http://127.0.0.1:3000';
  const database=process.env.SPACETIME_DATABASE;const token=process.env.SPACETIME_TOKEN;
  if(!database||!token)throw new ApiError(503,'Configure SPACETIME_DATABASE and SPACETIME_TOKEN');
  const response=await fetch(`${origin}/v1/database/${encodeURIComponent(database)}/call/request`,{
    method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify([JSON.stringify(request)]),signal:AbortSignal.timeout(15000),redirect:'error'
  }).catch(()=>{throw new ApiError(503,'Spacetime is unavailable');});
  if(!response.ok)throw new ApiError(503,`Spacetime rejected the service call (${response.status})`);
  const wire:any=await response.json();const result=typeof wire==='string'?JSON.parse(wire):wire;
  if(typeof result?.status!=='number')throw new ApiError(503,'Unexpected Spacetime response');
  if(result.status!==200)throw new ApiError(result.status,result.body?.error??'Request failed');return result.body;
}
export const publicOrigin=()=>process.env.POCKET_PUBLIC_ORIGIN??'http://127.0.0.1:8787';
export const service=(method:string,path:string,body:any={})=>call(envelope(method,'/internal/'+path,{...body,publicOrigin:publicOrigin()}));
