import { webURL } from './targets.ts';
export function backendURL(value:string):string {
  const url=webURL(value);
  if(url.pathname!=='/' || url.search || url.hash)throw Error('Backend must be an HTTPS origin (HTTP loopback allowed)');
  return url.origin;
}
export function opaque(value:unknown):value is string {return typeof value==='string' && /^[A-Za-z0-9_-]{1,128}$/.test(value);}
/** Never prints request headers, bodies, response errors or fetch exception text. */
export async function request(base:string,path:string,body:unknown,token:string,method=body===undefined?'GET':'POST'):Promise<any> {
  if(typeof token!=='string' || !token || /[\s\x00-\x1f\x7f]/.test(token))throw Error('Authentication required');
  const raw=body===undefined?undefined:JSON.stringify(body);
  if(raw && Buffer.byteLength(raw)>16384)throw Error('Request too large');
  const response=await fetch(backendURL(base)+path,{method,headers:{'Content-Type':'application/json',Authorization:`Bearer ${token}`},body:raw,redirect:'error',signal:AbortSignal.timeout(10000)}).catch(()=>{throw Error('Backend connection failed');});
  if(!response.ok){await response.body?.cancel();throw Error(`Backend rejected request (HTTP ${response.status})`);}
  const chunks:Uint8Array[]=[];let size=0;
  if(!response.body)throw Error('Empty backend response');
  try{for await(const chunk of response.body){size+=chunk.length;if(size>262144)throw Error();chunks.push(chunk);}}
  catch{throw Error('Invalid or oversized backend response');}
  try{return JSON.parse(Buffer.concat(chunks).toString('utf8'));}catch{throw Error('Invalid backend JSON');}
}
