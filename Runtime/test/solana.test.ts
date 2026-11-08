import test from 'node:test';
import assert from 'node:assert/strict';
import {validateSolanaPayment,solanaPayURL} from '../../Spacetime/spacetimedb/src/solana.ts';
import {validateSpec} from '../../Spacetime/spacetimedb/src/domain.ts';
import {build,checks} from '../src/agent.ts';
import {render} from '../src/template.ts';
const recipient='So11111111111111111111111111111111111111112'; // Format fixture only; never send funds.
const payment={recipient,amount:'0.001'};
const spec={name:'Club dues',summary:'Track contributions',kind:'list',fields:[{key:'member',label:'Member',type:'text'}],payment};
test('SOL requests validate exact decimal precision and decoded address length',()=>{
 assert.doesNotThrow(()=>validateSolanaPayment(payment));
 for(const amount of ['0','0.000000000','-1','1e3','01','0.0000000001','Infinity',1,null])assert.throws(()=>validateSolanaPayment({...payment,amount}));
 for(const recipient of ['1'.repeat(32),'z'.repeat(44),'0'.repeat(32),'https://example.com',payment.recipient+'?amount=1'])assert.throws(()=>validateSolanaPayment({...payment,recipient}));
 assert.throws(()=>validateSpec({...spec,payment:{...payment,secret:'no'}}));
 assert.equal(solanaPayURL(payment,'Dues & tips'),`solana:${recipient}?amount=0.001&label=Dues%20%26%20tips`);
});
test('rendered payment request keeps amount and recipient visible without claiming settlement',()=>{
 assert.equal(checks(spec).ok,true);
 const html=render(spec,'dues');assert.match(html,/Pay 0.001 SOL/);assert.match(html,/Pocket does not verify payment/);
 assert.ok(html.includes(recipient));assert.ok(html.includes(`href="solana:${recipient}?amount=0.001&amp;label=Club%20dues"`));
 assert.ok(!render({...spec,payment:undefined},'dues').includes('Open wallet'));
});
test('agent rejects an invented recipient and can repair to a supplied one',async()=>{
 let step=0;
 const steps=[['build_app',{spec}],['build_app',{spec:{...spec,payment:undefined}}],['test_app',{}],['finish',{}]];
 const result=await build('Create a dues tracker',null,async()=>{},async messages=>{
  if(step===1)assert.match(messages.at(-1).content,/user must supply/);
  const [name,args]=steps[step++];return {tool_calls:[{id:String(step),function:{name,arguments:JSON.stringify(args)}}]};
 });
 assert.deepEqual(result.trace.map(t=>t.ok),[false,true,true,true]);
});
