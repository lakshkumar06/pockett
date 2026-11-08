/** Server-only SDK. Importing this in browser code is unsupported. */
import { backendURL, request, opaque } from './http.ts';
import { validateEvent } from './validation.ts';
import type { Subscription, EventReceipt } from './web-types.ts';
export class NotificationClient {
  #backend:string;#credential:string;
  constructor(options:{backend:string;credential:string}) {this.#backend=backendURL(options.backend);this.#credential=options.credential;}
  async redeemPairing(pairingCode:string):Promise<Subscription> {
    if(!opaque(pairingCode))throw Error('Invalid pairing code');
    const r=await request(this.#backend,'/notification-pairings/redeem',{pairingCode},this.#credential);
    if(!opaque(r?.subscriptionId) || !opaque(r.appId) || r.notificationsEnabled!==true)throw Error('Invalid pairing confirmation');
    return {subscriptionId:r.subscriptionId,appId:r.appId,notificationsEnabled:true};
  }
  async send(event:unknown):Promise<EventReceipt> {
    const r=await request(this.#backend,'/notification-events',validateEvent(event),this.#credential);
    if(!opaque(r?.eventId) || typeof r.duplicate!=='boolean')throw Error('Invalid event confirmation');
    return {eventId:r.eventId,duplicate:r.duplicate};
  }
}
