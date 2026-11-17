// rc2 long-press/right-click body-portal contract regression, not an engine or
// Android test. Keeps test_web_account_menu_layout.mjs's 53 cases untouched.
// Node 24: node tooling/test_web_longpress_layout.mjs [--broken]
// --broken removes ONLY the app's contextmenu event recorder in memory; all
// other production JS, shipped CSS, official-handler fixture and assertions stay.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';

const root = '.harness-tmp-rc2/linux-arm64-prefix/node_modules/@deepseek-ai';
const assets = `${root}/dsh-web-frontend/dist/assets`;
const css = fs.readdirSync(assets).filter(n => n.endsWith('.css')).map(n => fs.readFileSync(`${assets}/${n}`, 'utf8')).join('\n');
const source = fs.readFileSync('app/assets/web/dsh_web_phone.js', 'utf8');
const adaptation = fs.readFileSync('app/assets/web/dsh_web_phone.css', 'utf8');
const context = fs.readFileSync(`${root}/dsh-client-ui-context-menu/lib/client.js`, 'utf8');
const workspace = fs.readFileSync(`${root}/dsh-client-ui-workspace/lib/client.js`, 'utf8');
// Fixture inputs come from the rc2 consumer, not the app's fallback algorithm.
assert(context.includes('event.preventDefault();event.stopPropagation();event.currentTarget.focus({preventScroll:true});open(captured,{x,y})'));
assert(context.includes('event.clientX===0&&event.clientY===0?event.currentTarget.getBoundingClientRect()'));
assert(context.includes('anchorPoint:point') && context.includes('contextual:true'));
assert(workspace.includes('role:`treeitem`') && workspace.includes('getTriggerProps('));
const listClass = css.match(/\.(_list_[\w]+)\{/)[1];
const portalClass = css.match(/\.(_portal_[\w]+)\{/)[1];
const viewportClass = css.match(/\.(_viewport_[\w]+)\{/)[1];
const sessionClass = workspace.match(/\.([\w]+_sessionRow)[{.,:]/)[1];
const projectClass = workspace.match(/\.([\w]+_projectRow)[{.,:]/)[1];
const start = source.indexOf("  document.addEventListener('contextmenu', function (event) {");
const end = source.indexOf('  }, true);', start);
assert(start >= 0 && end > start, 'Locate the exact recorder for the bad baseline');
const broken = process.argv.includes('--broken');
const phone = broken ? source.slice(0, start) + source.slice(end + '  }, true);'.length) : source;
const output = 'build/longpress-menu-layout';
fs.mkdirSync(output, { recursive: true });
const endpoint = 'http://127.0.0.1:19229';
const delay = ms => new Promise(r => setTimeout(r, ms));
const available = async () => { try { return (await fetch(`${endpoint}/json/version`, { signal: AbortSignal.timeout(500) })).ok; } catch { return false; } };
assert(!await available(), 'Dedicated longpress test port 19229 is occupied');
const edge = spawn(process.env.DSH_HEADER_EDGE || 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe', [
  '--headless=new', '--remote-debugging-port=19229', '--user-data-dir=D:\\Tools\\tmp\\dsh-longpress-19229',
  '--no-first-run', '--disable-background-networking', 'about:blank',
], { stdio: 'ignore' });
let client, browser;
const results = [], failures = [];
function connect(url) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url), pending = new Map(); let id = 0;
    ws.onerror = reject;
    ws.onopen = () => resolve({ ws, command(method, params = {}) { return new Promise((r, j) => {
      const key = ++id, timer = setTimeout(() => { pending.delete(key); j(Error(`CDP timeout ${method}`)); }, 10000);
      pending.set(key, { r, j, timer }); ws.send(JSON.stringify({ id: key, method, params }));
    }); } });
    ws.onmessage = event => { const m = JSON.parse(event.data), p = pending.get(m.id); if (!p) return; pending.delete(m.id); clearTimeout(p.timer); m.error ? p.j(Error(m.error.message)) : p.r(m.result); };
  });
}
async function evaluate(expression) {
  const r = await client.command('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
  if (r.exceptionDetails) throw Error(r.exceptionDetails.exception?.description || r.exceptionDetails.text);
  return r.result.value;
}
const paint = () => evaluate('new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(()=>requestAnimationFrame(r))))');
function fixture(kind, fault, mode = 'new') {
  return `<!doctype html><html data-dsh-app-lite data-dsh-app-layout="drawer"><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>${css}</style><style>${adaptation}</style><style>
  html,body{margin:0;width:100%;height:100%;--dsh-app-safe-top:40px;--dsh-app-safe-bottom:24px;--dsh-app-inset-left:0px;--dsh-app-inset-right:0px}
  #root{position:fixed;inset:40px 0 60px;transform:translateZ(0)}#scroller{position:absolute;inset:0;overflow:auto}#content{position:relative;height:1400px;width:100%}
  [role=treeitem]{position:absolute;left:24px;top:70px;width:250px;height:40px;box-sizing:border-box;padding:4px;display:flex;align-items:center;background:#eee;color:#111}
  #other-row{top:180px}#outside{position:fixed;left:24px;top:200px;width:250px;height:40px}#popup button{display:block;box-sizing:border-box;height:34px;width:140px;flex:none}#popup{overflow:auto}
  ${fault ? '#popup{position-anchor:--unresolved-fixture-anchor!important}' : ''}
  </style></head><body><div id="root"><div data-slot="sidebar"><div id="scroller"><div id="content"><div id="row" class="${kind === 'session' ? sessionClass : projectClass}" role="treeitem" tabindex="0"><span id="label">Synthetic ${kind} row</span></div><div id="other-row" class="${sessionClass}" role="treeitem" tabindex="0">Other row</div><div id="unrelated-row" class="fixture_unrelatedRow" role="treeitem" style="top:250px" tabindex="0">Unrelated type</div></div></div></div><div data-slot="shell.overlay"></div></div><div id="outside" class="${sessionClass}" role="treeitem" tabindex="0">Outside sidebar</div><script>
  window.fixtureReady=true;window.eventTrace=[];window.observed=[];window.clicks=[];window.officialCount=0;window.openCount=0;window.beforeCapture=[];window.afterCapture=[];window.preventOfficial=${mode !== 'unprevented'};window.reuseMenu=${mode === 'existing'};window.skipOpen=false;
  document.addEventListener('contextmenu',e=>{beforeCapture.push({prevented:e.defaultPrevented,target:e.target.id});eventTrace.push({phase:'capture',prevented:e.defaultPrevented});Promise.resolve().then(()=>eventTrace.push({phase:'capture-microtask',prevented:e.defaultPrevented}))},true);
  let serial=0;
  window.openFixture=function(x,y){
    let menu=window.reuseMenu&&document.querySelector('#popup');
    let anchor=menu&&document.querySelector('#virtual');
    if(!menu){
      anchor=document.createElement('span');anchor.id='virtual';anchor.style.cssText='position:fixed;width:0;height:0;anchor-name:--dsh-menu-trigger-press-'+(++serial);document.querySelector('[data-slot="shell.overlay"]').append(anchor);
      menu=document.createElement('div');menu.id='popup';menu.setAttribute('role','menu');menu.setAttribute('data-context-menu','');menu.setAttribute('data-anchor-side','bottom');menu.setAttribute('data-anchor-align','start');menu.className='${listClass} ${portalClass}';menu.style.positionAnchor='--dsh-menu-trigger-press-'+serial;
      menu.innerHTML='<div class="${viewportClass}"><button role="menuitem" data-action="rename">Rename fixture</button><button role="menuitem" data-action="delete">Delete fixture</button></div>';
    }
    anchor.style.left=x+'px';anchor.style.top=y+'px';document.body.append(menu);openCount++;
  };
  function official(event){
    const entry={target:event.target.id,row:event.currentTarget.id,preventedBefore:event.defaultPrevented,x:event.clientX,y:event.clientY,trusted:event.isTrusted,cancelable:event.cancelable};officialCount++;eventTrace.push({phase:'official-handler',prevented:event.defaultPrevented});
    // This is the rc2 handler's public DOM contract, without loading its engine.
    if(preventOfficial){event.preventDefault();event.stopPropagation();event.currentTarget.focus({preventScroll:true});}
    const rect=event.clientX===0&&event.clientY===0?event.currentTarget.getBoundingClientRect():null;
    if(!skipOpen)openFixture(rect?rect.left:event.clientX,rect?rect.bottom:event.clientY);
    entry.preventedAfter=event.defaultPrevented;observed.push(entry);
  }
  for(const row of document.querySelectorAll('[role=treeitem]'))row.addEventListener('contextmenu',official);
  document.addEventListener('click',event=>{const b=event.target.closest('[data-action]');if(b)clicks.push(b.dataset.action)});
  ${mode === 'existing' ? 'openFixture(0,0);' : ''}
  </script></body></html>`;
}
async function setup(width, height, kind, fault, mode) {
  await client.command('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: true });
  // A new document/window avoids accumulating observers/listeners across cases.
  await client.command('Page.navigate', { url: 'about:blank' });
  const { frameTree } = await client.command('Page.getFrameTree');
  await client.command('Page.setDocumentContent', { frameId: frameTree.frame.id, html: fixture(kind, fault, mode) });
  await evaluate(phone);
  await evaluate(`document.addEventListener('contextmenu',e=>afterCapture.push({prevented:e.defaultPrevented,target:e.target.id}),true)`);
  await paint();
}
async function geometry() {
  return evaluate(`(()=>{const rect=e=>{if(!e)return null;const r=e.getBoundingClientRect();return {left:r.left,right:r.right,top:r.top,bottom:r.bottom,width:r.width,height:r.height}};const p=document.querySelector('#popup'),row=document.querySelector('#row'),s=getComputedStyle(document.documentElement);return {popup:rect(p),row:rect(row),other:rect(document.querySelector('#other-row')),anchor:rect(document.querySelector('#virtual')),marked:!!p&&p.hasAttribute('data-dsh-app-anchor-popup'),sidebarMarked:!!p&&p.hasAttribute('data-dsh-app-sidebar-menu'),bounds:{left:(parseFloat(s.getPropertyValue('--dsh-app-inset-left'))||0)+8,right:innerWidth-(parseFloat(s.getPropertyValue('--dsh-app-inset-right'))||0)-8,top:(parseFloat(s.getPropertyValue('--dsh-app-safe-top'))||0)+8,bottom:innerHeight-(parseFloat(s.getPropertyValue('--dsh-app-safe-bottom'))||0)-8},eventTrace:eventTrace.slice(),observed:observed.slice(),before:beforeCapture.slice(),after:afterCapture.slice(),officialCount,openCount,clicks:clicks.slice(),items:p?[...p.querySelectorAll('[data-action]')].map(e=>({...rect(e),action:e.dataset.action,hit:(()=>{const r=e.getBoundingClientRect();return e.contains(document.elementFromPoint(r.left+r.width/2,r.top+r.height/2))})()})):[]}})()`);
}
function checkEvent(g, count = 1, prevented = true) {
  assert.equal(g.officialCount, count, 'Original official handler runs exactly once per event');
  assert.equal(g.before.length, count); assert.equal(g.after.length, count, 'App never stops contextmenu propagation');
  assert(g.before.every(e => !e.prevented) && g.after.every(e => !e.prevented), 'App never consumes contextmenu in capture');
  assert(g.observed.every(e => !e.preventedBefore && e.preventedAfter === prevented), 'Only official handler owns prevention');
}
function checkPlacement(g, dx, dy, label) {
  assert(g.marked && g.sidebarMarked, `${label}: exact new sidebar portal is marked ${JSON.stringify(g)}`);
  const p = g.popup, b = g.bounds, x = g.row.left + dx, y = g.row.top + dy;
  assert(p.left >= b.left-.5 && p.right <= b.right+.5 && p.top >= b.top-.5 && p.bottom <= b.bottom+.5, `${label}: safe viewport ${JSON.stringify(g)}`);
  const left = Math.max(b.left, Math.min(x, b.right-p.width));
  assert(Math.abs(p.left-left)<1, `${label}: pointer x stays bound to originating row ${JSON.stringify(g)}`);
  const down = y+1+4, up = y-p.height-4;
  assert(Math.abs(p.top-down)<1 || Math.abs(p.top-up)<1 || Math.abs(p.top-b.top)<1 || Math.abs(p.bottom-b.bottom)<1, `${label}: pointer y stays beside originating row ${JSON.stringify(g)}`);
  assert(g.items.every(i=>i.hit), `${label}: official action targets stay clickable ${JSON.stringify(g)}`);
}
async function dispatch(target, x, y, trusted = false) {
  if (trusted) {
    for (const type of ['mousePressed', 'mouseReleased']) await client.command('Input.dispatchMouseEvent', { type, x, y, button: 'right', buttons: type === 'mousePressed' ? 2 : 0, clickCount: 1 });
  } else {
    await evaluate(`document.querySelector(${JSON.stringify(target)}).dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,cancelable:true,clientX:${x},clientY:${y}}))`);
  }
  await paint();
}
async function runCase(label, action) {
  try { const data = await action(); results.push({ label, ...data }); console.log(`PASS ${label}`); }
  catch (error) { const evidence=await geometry().catch(()=>null); failures.push({ label, error: error.message, evidence }); console.error(`FAIL ${label}: ${error.message}`); }
}
try {
  for (let i = 0; i < 100 && !await available(); i++) { assert(edge.exitCode === null, 'Owned Edge exited'); await delay(100); }
  const version = await fetch(`${endpoint}/json/version`).then(r=>r.json()); browser = await connect(version.webSocketDebuggerUrl);
  const target = (await fetch(`${endpoint}/json/list`).then(r=>r.json())).find(t=>t.type==='page'); client = await connect(target.webSocketDebuggerUrl);
  for (const [width,height] of [[363,800],[320,640],[800,363]]) {
    for (const kind of ['session','workspace']) for (const fault of [false,true]) {
      const label = `${kind} ${width}x${height} ${fault?'anchor-fault':'normal'}`;
      await runCase(label, async()=>{
        await setup(width,height,kind,fault,'new');
        const row = (await geometry()).row, dx=67,dy=17;
        await dispatch('#label',row.left+dx,row.top+dy,true);
        const initial=await geometry();checkEvent(initial);assert(initial.observed[0].trusted,'Real CDP right-click must generate trusted contextmenu');
        if(broken)assert(!initial.marked,'Removing just the recorder must lose longpress association');else checkPlacement(initial,dx,dy,label);
        await evaluate(`document.querySelector('#scroller').scrollTop=23;document.querySelector('#other-row').style.transform='translate(47px,11px)'`);await paint();
        const moved=await geometry();assert.equal(moved.row.top,initial.row.top-23,'Real sidebar scroll moves source row');assert.deepEqual(moved.anchor,initial.anchor,'Official virtual point remains stale during scroll');
        if(broken){assert(!moved.marked);assert(Math.abs(moved.popup.top-(moved.row.top+dy+5))>10,'Bad baseline is visibly stale/misplaced after scroll');}
        else {
          checkPlacement(moved,dx,dy,`${label} scroll`);assert(Math.abs(moved.popup.top-initial.popup.top)>20,'Menu follows event row, not unrelated row');
          await evaluate(`document.documentElement.style.setProperty('--dsh-app-safe-top','52px');document.documentElement.style.setProperty('--dsh-app-inset-left','28px');document.documentElement.style.setProperty('--dsh-app-inset-right','18px');document.body.style.transform='translate(5px,9px)'`);await paint();checkPlacement(await geometry(),dx,dy,`${label} safearea/body`);
          await client.command('Emulation.setDeviceMetricsOverride',{width:height,height:width,deviceScaleFactor:1,mobile:true});await paint();checkPlacement(await geometry(),dx,dy,`${label} rotation`);
          const final=await geometry();
          for(const item of final.items)for(const type of ['mousePressed','mouseReleased'])await client.command('Input.dispatchMouseEvent',{type,x:item.left+item.width/2,y:item.top+item.height/2,button:'left',clickCount:1});
          assert.deepEqual((await geometry()).clicks,['rename','delete'],'App leaves official menu actions intact');
          await evaluate(`document.querySelector('#row').remove();document.dispatchEvent(new Event('scroll'))`);await paint();assert(!(await geometry()).marked,'Detached event row invalidates retained WeakMap association');
        }
        return {initial,moved};
      });
    }
  }
  for(const kind of ['session','workspace'])await runCase(`${kind} synthetic pointer control`,async()=>{
    await setup(363,800,kind,true,'new');const r=(await geometry()).row;
    await dispatch('#label',r.left+67,r.top+17);const g=await geometry();checkEvent(g);
    if(broken)assert(!g.marked);else checkPlacement(g,67,17,`${kind} synthetic control`);return {geometry:g};
  });
  // Edge pointers and keyboard-origin 0,0 use dispatched browser MouseEvents;
  // the 12 matrix cases above independently require real trusted CDP events.
  for(const point of ['top-left','bottom-right','keyboard'])for(const kind of ['session','workspace'])await runCase(`${kind} ${point}`,async()=>{
    await setup(320,640,kind,true,'new');
    if(point==='top-left')await evaluate(`document.querySelector('#row').style.cssText='left:8px;top:10px;width:250px;height:40px'`);
    if(point==='bottom-right')await evaluate(`document.querySelector('#row').style.cssText='left:60px;top:510px;width:250px;height:40px'`);
    await paint();let r=(await geometry()).row;
    const dx=point==='bottom-right'?r.width-1:point==='top-left'?1:0,dy=point==='bottom-right'?r.height-1:point==='top-left'?1:r.height;
    await dispatch('#label',point==='keyboard'?0:r.left+dx,point==='keyboard'?0:r.top+dy);
    const g=await geometry();checkEvent(g);if(broken)assert(!g.marked);else checkPlacement(g,dx,dy,`${kind} ${point}`);return {geometry:g};
  });
  for(const mode of ['unprevented','existing','unrelated-type','outside-sidebar','wrong-point','no-open'])await runCase(`ownership ${mode}`,async()=>{
    await setup(363,800,'session',true,mode);
    const target=mode==='unrelated-type'?'#unrelated-row':mode==='outside-sidebar'?'#outside':'#label';
    if(mode==='wrong-point')await evaluate(`const original=openFixture;openFixture=(x,y)=>original(x+30,y+30)`);
    if(mode==='no-open')await evaluate(`skipOpen=true`);
    const r=await evaluate(`(()=>{const r=document.querySelector(${JSON.stringify(target)}).getBoundingClientRect();return {left:r.left,top:r.top}})()`);
    await dispatch(target,r.left+10,r.top+10);
    const g=await geometry();checkEvent(g,1,mode!=='unprevented');assert(!g.marked,`${mode}: app leaves nonmatching/old/unhandled menu upstream-owned`);return {geometry:g};
  });
  // A newer irrelevant or unhandled event clears the prior pending row; a
  // delayed matching portal from the old event must not inherit its association.
  for(const second of ['unprevented','unrelated'])await runCase(`pending invalidated by ${second}`,async()=>{
    await setup(363,800,'session',true,'new');
    await evaluate(`skipOpen=true`);const r=(await geometry()).row;
    await dispatch('#label',r.left+61,r.top+19);
    if(second==='unprevented')await evaluate(`preventOfficial=false`);
    await dispatch(second==='unrelated'?'#unrelated-row':'#label',r.left+81,r.top+29);
    await evaluate(`openFixture(${r.left+61},${r.top+19})`);await paint();
    const g=await geometry();assert.equal(g.officialCount,2);assert(!g.marked,'A second contextmenu invalidates stale pending association');return {geometry:g};
  });
  // Two events can occur before the next animation frame. Cancellation by the
  // newer event must also invalidate an older recorder callback still queued.
  for(const second of ['unprevented','unrelated'])await runCase(`same-frame pending invalidated by ${second}`,async()=>{
    await setup(363,800,'session',true,'new');const r=(await geometry()).row;
    await evaluate(`(()=>{skipOpen=true;const emit=(target,x,y)=>document.querySelector(target).dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,cancelable:true,clientX:x,clientY:y}));emit('#label',${r.left+61},${r.top+19});${second==='unprevented'?'preventOfficial=false;':''}emit('${second==='unrelated'?'#unrelated-row':'#label'}',${r.left+81},${r.top+29})})()`);
    await paint();await evaluate(`openFixture(${r.left+61},${r.top+19})`);await paint();
    const g=await geometry();assert.equal(g.officialCount,2);assert(!g.marked,'Newer contextmenu also invalidates an older queued recorder callback');return {geometry:g};
  });
} finally {
  fs.writeFileSync(`${output}/${broken?'before':'after'}.json`,JSON.stringify({mode:broken?'recorder-removed':'current',phoneSha256:createHash('sha256').update(source).digest('hex'),passed:results.length,failed:failures.length,results,failures},null,2));
  client?.ws.close();if(browser){await browser.command('Browser.close').catch(()=>{});browser.ws.close();}else edge.kill();
}
console.log(`Longpress ${broken?'bad baseline reproduced':'geometry passed'}: ${results.length} passed, ${failures.length} failed`);
assert.equal(failures.length,0,JSON.stringify(failures,null,2));
