import test from 'node:test';
import assert from 'node:assert/strict';
import {checkPrice,type Plan} from '../../Developer/src/cloud.ts';
const plan={plan:'vc2-test'} as Plan;
test('Vultr creation requires a current available plan within the explicit spending ceiling',()=>{
 const prices=[{id:'vc2-test',monthly_cost:6}];assert.equal(checkPrice(plan,prices,['vc2-test'],7),6);
 assert.throws(()=>checkPrice(plan,prices,['vc2-test'],5),/ceiling/);
 assert.throws(()=>checkPrice(plan,prices,[],7),/unavailable/);
 assert.throws(()=>checkPrice(plan,[{id:'vc2-test'}],['vc2-test'],7),/unavailable/);
 assert.throws(()=>checkPrice(plan,prices,['vc2-test'],NaN),/ceiling/);
});
