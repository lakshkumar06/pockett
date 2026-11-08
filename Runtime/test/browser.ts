/** Live browser smoke test. QA_LINK_FILE must point to a private fixture from test/live.ts. */
import {chromium} from 'playwright';
import {readFile,mkdir} from 'node:fs/promises';
import assert from 'node:assert/strict';
const {url}=JSON.parse(await readFile(process.env.QA_LINK_FILE!,'utf8'));
const out=process.env.QA_SCREENSHOT_DIR??'.runtime/screenshots';await mkdir(out,{recursive:true});
const browser=await chromium.launch({channel:'chrome',headless:true});
try{
 for(const viewport of [{width:390,height:844},{width:1280,height:900}]){
  const page=await browser.newPage({viewport});const errors:string[]=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto(url);await page.locator('#openComposer:not([hidden])').waitFor();
  assert.equal(new URL(page.url()).hash,'');
  assert.equal(await page.evaluate(()=>document.documentElement.scrollHeight<=innerHeight),true);
  await page.locator('#openComposer').click();await page.locator('#entry.sheet-open').waitFor();
  const item='Browser check '+viewport.width;await page.getByLabel('Item',{exact:true}).fill(item);await page.locator('#save').click();
  await page.locator('article').filter({hasText:item}).waitFor();await page.reload();await page.locator('article').filter({hasText:item}).waitFor();
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
  await page.screenshot({path:`${out}/miniapp-${viewport.width}.png`,fullPage:true,animations:'disabled'});
  await page.locator('article').filter({hasText:item}).getByRole('button',{name:'Remove',exact:true}).click();await page.locator('article').filter({hasText:item}).waitFor({state:'detached'});
  assert.deepEqual(errors,[]);await page.close();
 }
 console.log('PASS: browser add, reload persistence, removal, access-fragment cleanup, and overflow checks at phone and desktop sizes.');
}finally{await browser.close();}
