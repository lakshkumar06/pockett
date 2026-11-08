/** Local browser fixture: no RPC, signing, or real payment. */
import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import {render} from '../src/template.ts';
const spec={name:'Club dues',summary:'Track contributions',kind:'list',fields:[{key:'member',label:'Member',type:'text'}],payment:{recipient:'So11111111111111111111111111111111111111112',amount:'0.001'}};
const browser=await chromium.launch({channel:'chrome',headless:true});
try{
 for(const viewport of [{width:390,height:844},{width:1280,height:900}]){
  const page=await browser.newPage({viewport});const errors:string[]=[];page.on('pageerror',e=>errors.push(e.message));
  await page.route('https://pocket.test/**',route=>route.fulfill({contentType:route.request().url().includes('/items')?'application/json':'text/html',body:route.request().url().includes('/items')?JSON.stringify({items:[]}):render(spec,'dues')}));
  await page.goto('https://pocket.test/mini/dues#access=fixture');
  await page.getByText('Pay 0.001 SOL',{exact:true}).click();
  const link=page.getByRole('link',{name:'Open wallet'});assert.equal(await link.isVisible(),true);
  assert.equal(await link.getAttribute('href'),'solana:'+spec.payment.recipient+'?amount=0.001&label=Club%20dues');
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
  await page.screenshot({path:`/private/tmp/pocket-solana-${viewport.width}.png`});assert.deepEqual(errors,[]);await page.close();
 }
 console.log('Payment disclosure and link verified at mobile and desktop sizes. Wallet signing not exercised.');
}finally{await browser.close();}
