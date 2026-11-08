import { schema, table, t, SenderError } from 'spacetimedb/server';
import { dispatch, mini, Fault, type Store, type Request } from './domain';
const record=()=>table({public:false},{id:t.string().primaryKey(),value:t.string()});
const spacetimedb=schema({
  config:record(),users:record(),sessions:record(),apps:record(),credentials:record(),pairings:record(),
  subscriptions:record(),events:record(),inbox:record(),devices:record(),limits:record(),
  jobs:record(),links:record(),conversations:record(),messages:record(),cursors:record(),capabilities:record(),items:record()
});
export default spacetimedb;
export const init=spacetimedb.init(ctx=>{ctx.db.config.insert({id:'gateway',value:ctx.sender.toHexString()});});
export const request=spacetimedb.procedure({requestJson:t.string()},t.string(),(ctx,{requestJson})=>{
  // Throw on errors so the entire transaction rolls back, including partial mutations.
  try{return ctx.withTx(tx=>{
    if(tx.db.config.id.find('gateway')?.value!==ctx.sender.toHexString())throw new SenderError('Gateway identity required');
    if(requestJson.length>65536)throw new Fault(413,'Request too large');
    const r=JSON.parse(requestJson) as Request;
    const tables=tx.db as any;
    const store:Store={
      get:(name,id)=>{const row=tables[name].id.find(id);return row?JSON.parse(row.value):undefined;},
      put:(name,id,value)=>{const row={id,value:JSON.stringify(value)};if(tables[name].id.find(id))tables[name].id.update(row);else tables[name].insert(row);},
      delete:(name,id)=>{tables[name].id.delete(id);},
      all:name=>Array.from(tables[name].iter(),(row:any)=>JSON.parse(row.value))
    };
    const now=Number(tx.timestamp.microsSinceUnixEpoch/1000000n);
    return JSON.stringify({status:200,body:r.path.startsWith('/mini/')?mini(store,r,now):dispatch(store,r,now)});
  });}catch(e){if(e instanceof Fault)return JSON.stringify({status:e.status,body:{error:e.message}});throw e;}
});
