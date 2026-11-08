import type { Appearance } from './web-types.ts';
import { safeTarget, launchURL } from './targets.ts';
export { safeTarget, launchURL };
export const safeAreaCSS=`:root { --pocket-safe-top: env(safe-area-inset-top, 0px); --pocket-safe-right: env(safe-area-inset-right, 0px); --pocket-safe-bottom: env(safe-area-inset-bottom, 0px); --pocket-safe-left: env(safe-area-inset-left, 0px); } .pocket-safe-area { padding: max(16px, var(--pocket-safe-top)) max(16px, var(--pocket-safe-right)) max(16px, var(--pocket-safe-bottom)) max(16px, var(--pocket-safe-left)); }`;
/** Ordinary DOM/CSS enhancement. No host globals or native message handlers. */
export function applyAppearance(appearance:Appearance={},doc:Document=document):void {
  const scheme=appearance.colorScheme??'system';
  if(!['system','light','dark'].includes(scheme) || (appearance.themeColor!==undefined && !/^#[0-9a-f]{6}$/i.test(appearance.themeColor)))throw Error('Invalid appearance');
  doc.documentElement.style.colorScheme=scheme==='system'?'light dark':scheme;
  let viewport=doc.querySelector<HTMLMetaElement>('meta[name="viewport"]');
  if(!viewport){viewport=doc.createElement('meta');viewport.name='viewport';doc.head.append(viewport);}
  const settings=(viewport.content || 'width=device-width, initial-scale=1').split(',').filter(v=>!/^\s*viewport-fit\s*=/i.test(v));
  viewport.content=[...settings,'viewport-fit=cover'].join(',');
  if(appearance.themeColor){let meta=doc.querySelector<HTMLMetaElement>('meta[name="theme-color"]');if(!meta){meta=doc.createElement('meta');meta.name='theme-color';doc.head.append(meta);}meta.content=appearance.themeColor;}
  if(!doc.getElementById('pocket-safe-area')){const style=doc.createElement('style');style.id='pocket-safe-area';style.textContent=safeAreaCSS;doc.head.append(style);}
}
/** Full ordinary web navigation; back/forward and hash routing remain the site's responsibility. */
export function navigate(target:string,location:Pick<Location,'origin'|'assign'>=window.location):void {
  location.assign(launchURL(location.origin,safeTarget(target)));
}
/** Send a user-consented code ONLY to the creator's own authenticated backend.
 * The backend binds the resulting subscription to its own session and returns {paired:true}.
 * Pocket tokens, app credentials and opaque subscription IDs never enter this helper.
 */
export async function pairSubscription(options:{endpoint:string;pairingCode:string;consent:boolean;csrfToken:string}):Promise<{paired:true}> {
  if(options.consent!==true || !/^[A-Za-z0-9_-]{1,128}$/.test(options.pairingCode) || !options.csrfToken)throw Error('Explicit consent, pairing code and CSRF token required');
  const url=launchURL(window.location.origin,safeTarget(options.endpoint));
  const response=await fetch(url,{method:'POST',credentials:'same-origin',redirect:'error',headers:{'Content-Type':'application/json','X-CSRF-Token':options.csrfToken},body:JSON.stringify({pairingCode:options.pairingCode,consent:true}),signal:AbortSignal.timeout(10000)}).catch(()=>{throw Error('Pairing request failed');});
  if(!response.ok)throw Error(`Pairing rejected (HTTP ${response.status})`);
  const result=await response.json();if(result?.paired!==true)throw Error('Invalid pairing confirmation');return {paired:true};
}
