import {applyAppearance,pairSubscription} from '/sdk/browser.js';
applyAppearance({colorScheme:'system',themeColor:'#48634A'});
const $=id=>document.getElementById(id);let csrfToken='';let reminderKey;
function status(message){$('status').textContent=message;}
async function api(path,body){const r=await fetch(path,{method:body?'POST':'GET',credentials:'same-origin',headers:{'Content-Type':'application/json','X-CSRF-Token':csrfToken},body:body?JSON.stringify(body):undefined});const data=await r.json();if(!r.ok)throw Error(data.error||'Request failed');return data;}
async function refresh(){const data=await api('/api/session');csrfToken=data.csrfToken;$('login-panel').hidden=!data.signedIn?false:true;$('notes-panel').hidden=!data.signedIn;$('remind').disabled=!data.paired;$('pairing').open=data.signedIn&&!data.paired;$('back').hidden=location.pathname==='/';if(location.pathname==='/notes/42')$('title').textContent='Your Saturday note';}
async function perform(button,action){button.disabled=true;try{await action();}catch(e){status(e.message);}finally{button.disabled=false;}}
$('login').onsubmit=e=>{e.preventDefault();perform(e.submitter,async()=>{await api('/api/login',{password:$('password').value});$('password').value='';status('');await refresh();});};
$('pair').onsubmit=e=>{e.preventDefault();perform(e.submitter,async()=>{await pairSubscription({endpoint:'/api/pair',pairingCode:$('code').value.trim(),consent:$('consent').checked,csrfToken});$('code').value='';status('Reminders connected.');await refresh();});};
$('remind').onclick=e=>perform(e.currentTarget,async()=>{reminderKey??=crypto.randomUUID();const receipt=await api('/api/remind',{idempotencyKey:reminderKey});reminderKey=undefined;status(receipt.duplicate?'This reminder is already in Pocket’s inbox.':'Your note is in Pocket’s inbox. Open it there to return to this exact note.');});
$('logout').onclick=()=>api('/api/logout',{}).then(refresh).catch(e=>status(e.message));
refresh().catch(()=>status('Start the Little Notes example backend to sign in and connect reminders.'));
