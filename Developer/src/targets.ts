/** No Node or native APIs: shared by browser and server SDKs. */
export function webURL(value: unknown, allowFragment=true): URL {
  if (typeof value !== 'string' || value.length > 2048 || !/^https?:\/\//.test(value) || /[\s\x00-\x20\x7f\\]/.test(value)) throw Error('Invalid web URL');
  let url: URL; try {url=new URL(value);} catch {throw Error('Invalid web URL');}
  const authority=value.slice(value.indexOf('://')+3).split(/[/?#]/)[0];
  if (!authority || authority.includes('@') || !url.hostname || (url.protocol !== 'https:' && !(url.protocol==='http:' && ['localhost','127.0.0.1','[::1]'].includes(url.hostname))) || (!allowFragment && value.includes('#'))) throw Error('Use HTTPS without credentials (HTTP loopback is allowed for local development)');
  return url;
}
export function safeTarget(value: unknown): string {
  if (typeof value !== 'string' || value.length<1 || value.length>2048 || !value.startsWith('/') || value.startsWith('//') || /[\s\x00-\x20\x7f\\]/.test(value) || /%(?![a-fA-F0-9]{2})/.test(value) || /%(?:0[0-9a-f]|1[0-9a-f]|20|7f|5c|2f|25)/i.test(value)) throw Error('Unsafe app target');
  let decoded: string; try {decoded=decodeURIComponent(value);} catch {throw Error('Invalid target encoding');}
  if (/[\s\x00-\x20\x7f\\]/.test(decoded) || decoded.split(/[?#]/)[0].split('/').some(p=>p==='.' || p==='..')) throw Error('Unsafe app target');
  return value;
}
export function launchURL(entryURL:string,target:string): string {
  const origin=webURL(entryURL).origin;
  const exact=origin+safeTarget(target);
  if(new URL(exact).origin!==origin) throw Error('Target leaves app origin');
  return exact;
}
