import { readFileSync } from 'node:fs';
import { Ajv } from 'ajv';
const schema = JSON.parse(readFileSync(new URL('../Contracts/experience.schema.json', import.meta.url), 'utf8'));
const check = new Ajv({allErrors: true, strict: false}).compile<any>(schema);
export function httpsURL(value: unknown): string {
  if (typeof value !== 'string' || value.length > 2048 || /\s/.test(value)) throw Error('Invalid HTTPS URL');
  let u: URL; try { u = new URL(value); } catch { throw Error('Invalid HTTPS URL'); }
  if (u.protocol !== 'https:' || !u.hostname || u.username || u.password || u.search || u.hash) throw Error('Use HTTPS without credentials, query or fragment');
  return value;
}
function unique(values: string[]) { if (new Set(values).size !== values.length) throw Error('Duplicate identifier'); }
export function validate(value: unknown): any {
  function jsonOnly(v: unknown, depth=0): void {
    if (depth > 16) throw Error('Configuration nesting exceeds 16');
    if (v === null || typeof v === 'string' || typeof v === 'boolean') return;
    if (typeof v === 'number' && Number.isFinite(v)) return;
    if (typeof v !== 'object') throw Error('Configuration contains non-JSON values');
    if (!Array.isArray(v) && Object.getPrototypeOf(v) !== Object.prototype && Object.getPrototypeOf(v) !== null) throw Error('Configuration must contain plain JSON objects');
    for (const child of Object.values(v)) jsonOnly(child,depth+1);
  }
  jsonOnly(value);
  const json = JSON.stringify(value);
  if (!json || Buffer.byteLength(json) > 65536) throw Error('Configuration must be JSON under 64 KiB');
  const d = JSON.parse(json);
  if (d?.schemaVersion === 1) {
    const keys = ['schemaVersion','id','name','icon','url','community','summary'];
    if (Object.keys(d).length !== keys.length || keys.some(k => !(k in d))) throw Error('Invalid v1 fields');
    for (const [k,n] of Object.entries({id:64,name:60,icon:80,community:64,summary:160})) if (typeof d[k] !== 'string' || !d[k].trim() || d[k].length > n) throw Error(`Invalid v1 ${k}`);
    for (const k of ['id','community']) if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(d[k])) throw Error('Invalid slug');
    // Legacy URLs permit query and fragment, as the original validator did.
    if (typeof d.url !== 'string' || /\s/.test(d.url)) throw Error('Invalid v1 URL');
    let u; try {u = new URL(d.url);} catch {throw Error('Invalid v1 URL');}
    if (u.protocol !== 'https:' || !u.hostname || u.username || u.password) throw Error('Invalid v1 URL');
    return d;
  }
  if (!check(d)) throw Error('Invalid v2 configuration: ' + check.errors?.map(e => `${e.instancePath} ${e.keyword}`).join('; '));
  const caps = new Set(d.capabilities);
  const requireCap = (c: string) => { if (!caps.has(c)) throw Error(`Missing capability ${c}`); };
  if (caps.has('liveActivity.route')) requireCap('route.recording');
  unique(d.screens.map((s:any)=>s.id)); unique((d.dataSources??[]).map((s:any)=>s.id));
  const sources = new Map<string,any>((d.dataSources??[]).map((s:any)=>[s.id,s]));
  for (const s of sources.values()) { httpsURL(s.url); unique(s.response.fields.map((f:any)=>f.name)); for (const f of s.response.fields) if (f.path.some((k:string)=>['__proto__','constructor','prototype'].includes(k))) throw Error('Unsafe mapping key'); }
  for (const s of d.screens) {
    if (!s.title.trim()) throw Error('Empty title');
    for (const c of s.components) {
      if (c.type === 'routeMap') requireCap('route.recording');
      const b = c.binding;
      if (b?.source === 'route') {requireCap('route.recording'); if (b.type !== (b.field === 'status' ? 'string':'number')) throw Error('Wrong binding type');}
      if (b?.source === 'data' && !sources.get(b.dataSource)?.response.fields.some((f:any)=>f.name === b.field && f.type === b.type)) throw Error('Unknown data binding');
      const a = c.action;
      if (a?.type.startsWith('route.')) requireCap('route.recording');
      if (a?.type.startsWith('liveActivity.')) requireCap('liveActivity.route');
      if (a?.type === 'navigate' && !d.screens.some((s:any)=>s.id === a.screen)) throw Error('Unknown screen');
      if (a?.type === 'data.refresh' && !sources.has(a.dataSource)) throw Error('Unknown data source');
    }
  }
  if (!d.metadata.name.trim() || !d.metadata.summary.trim()) throw Error('Empty metadata');
  return d;
}
