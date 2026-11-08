import {service,hash} from './spacetime.ts';
export class Photon {
  readonly key:string;readonly project:string;readonly sender:string;readonly fetcher:typeof fetch;
  constructor(key:string,project:string,sender:string,fetcher:typeof fetch=fetch){this.key=key;this.project=project;this.sender=sender;this.fetcher=fetcher;}
  async request(path:string,body?:any,idempotency?:string){
    const r=await this.fetcher(`https://api.photon.codes/v1/projects/${encodeURIComponent(this.project)}${path}`,{method:body?'POST':'GET',headers:{Authorization:`Bearer ${this.key}`,'Content-Type':'application/json',...(idempotency?{'Idempotency-Key':idempotency}:{})},body:body?JSON.stringify(body):undefined,signal:AbortSignal.timeout(20000),redirect:'error'});
    if(!r.ok){await r.body?.cancel();throw Error(`Photon request failed (${r.status})`);}return r.json() as Promise<any>;
  }
  async tick(invoke=service){
    // Authenticated Photon 2.0 API polling avoids exposing a public webhook. Durable cursor + overlap handles eventual consistency.
    const key='photon:'+this.project;const state=await invoke('GET','photon/cursor',{key});
    if(!state.value){await invoke('POST','photon/cursor',{key,value:new Date().toISOString()});return;}
    const upper=new Date().toISOString();const since=new Date(new Date(state.value).getTime()-60000).toISOString();let pageToken:string|undefined;
    do{
      const params=new URLSearchParams({createdSince:since,createdBefore:upper,direction:'received',order:'asc',pageSize:'100'});if(pageToken)params.set('pageToken',pageToken);
      const page=await this.request('/messages?'+params);
      if(!Array.isArray(page.items))throw Error('Unexpected Photon message page');
      for(const m of page.items){
        if(m.projectId!==this.project||m.status!=='received'||m.sentBy?.id===this.sender||!m.space?.participantIds?.includes(this.sender)||m.content?.type!=='text'||!m.space?.id||!m.sentBy?.id||!m.id)continue;
        const key=`${this.project}:${m.space.id}:${m.sentBy.id}`;
        const text=m.content.text; if(typeof text!=='string'||text.length>4000)continue;
        const result=await invoke('POST','photon/ingest',{key,eventId:m.id,text,codeHash:hash(text.startsWith('link ')?text.slice(5).trim():'')});
        if(!result.sent){await this.request('/messages',{senderId:this.sender,spaceId:m.space.id,parentMessageId:m.id,content:{type:'text',format:'plain',text:result.reply}},'pocket-'+m.id);await invoke('POST','photon/sent',{key,eventId:m.id});}
      }
      pageToken=page.nextPageToken||undefined;
    }while(pageToken);
    await invoke('POST','photon/cursor',{key,value:upper});
  }
}
