// rc2 account body-portal geometry regression. Uses shipped frontend CSS and
// AccountMenu markup/anchor contract; no account/network/engine code executes.
// node tooling/test_web_account_menu_layout.mjs [--broken]
import assert from 'node:assert/strict';
import fs from 'node:fs';
// Desktop Edge + synthetic rc2-contract DOM; not a phone-root-cause claim.
import { spawn } from 'node:child_process';
const root = '.harness-tmp-rc2/linux-arm64-prefix/node_modules/@deepseek-ai';
const assets = `${root}/dsh-web-frontend/dist/assets`;
const css = fs.readdirSync(assets).filter(n => n.endsWith('.css')).map(n => fs.readFileSync(`${assets}/${n}`, 'utf8')).join('\n');
const account = fs.readFileSync(`${root}/dsh-client-ui-settings-account/lib/client.js`, 'utf8');
assert(account.includes('side:`top`,portal:true') && account.includes('"data-signed-out":!signedIn'));
const prefix = css.match(/\.(_list_[\w]+)\{/)[1];
const portal = css.match(/\.(_portal_[\w]+)\{/)[1];
const viewport = css.match(/\.(_viewport_[\w]+)\{/)[1];
const phone = fs.readFileSync('app/assets/web/dsh_web_phone.js', 'utf8');
const adaptation = fs.readFileSync('app/assets/web/dsh_web_phone.css', 'utf8');
const modal = fs.readFileSync('app/assets/web/dsh_web_modal.js', 'utf8');
const broken = process.argv.includes('--broken');
const output = 'build/account-menu-layout';
fs.mkdirSync(output, { recursive: true });
const endpoint = 'http://127.0.0.1:19229';
const edgePath = process.env.DSH_HEADER_EDGE || 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
const delay = ms => new Promise(r => setTimeout(r, ms));
const available = async () => { try { return (await fetch(`${endpoint}/json/version`, { signal: AbortSignal.timeout(500) })).ok; } catch { return false; } };
assert(!await available(), 'Dedicated account test port is occupied');
const edge = spawn(edgePath, ['--headless=new', '--remote-debugging-port=19229', '--user-data-dir=D:\\Tools\\tmp\\dsh-account-19229', '--no-first-run', '--disable-background-networking', 'about:blank'], { stdio: 'ignore' });
let client, browser;
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
const paint = () => evaluate('new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)))');
const mutationStability = () => evaluate(`new Promise(resolve=>{let mutations=0;const observer=new MutationObserver(records=>{mutations+=records.filter(r=>r.target.hasAttribute('data-dsh-app-anchor-popup')).length});observer.observe(document.body,{subtree:true,attributes:true,attributeFilter:['style']});for(let i=0;i<50;i++){window.dispatchEvent(new Event('resize'));document.dispatchEvent(new Event('scroll'));window.dispatchEvent(new Event('pageshow'))}let frames=0;function tick(){if(++frames===4){mutations=0}if(frames===12){observer.disconnect();resolve({burstEvents:150,quietFrames:8,quietStyleMutations:mutations})}else requestAnimationFrame(tick)}requestAnimationFrame(tick)})`);
function fixture(width, height) {
  return `<!doctype html><html data-dsh-app-lite data-dsh-app-layout="drawer"><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>${css}</style><style>${adaptation}</style><style>
  html,body{margin:0;width:100%;height:100%;--dsh-app-safe-top:40px;--dsh-app-safe-bottom:24px;--dsh-app-inset-top:40px;--dsh-app-inset-bottom:60px}
  #root{position:fixed;inset:40px 0 60px;transform:translateZ(0)}[data-slot]{display:contents}.fixture_frame{height:100%}.fixture_sidebarCol{width:286px;height:100%}
  .fixture_root{display:flex;flex-direction:column}.fixture_space{flex:1}.fixture_anchor{display:flex;width:240px;margin-left:8px;anchor-name:--dsh-menu-trigger-account}
  /* Model the observed failure class: a portal's CSS anchor does not resolve
     across the drawer root. Retain the inline link so production fallback can
     bind it; apply to both baseline and repaired pages, not just baseline. */
  #account{position-anchor:--unresolved-fixture-anchor!important}
  button[data-signed-out]{height:44px;width:240px}.fixture_menuitem{display:block;width:100%;height:34px;flex:none}.fixture_unrelated{position:fixed;left:170px;top:100px;width:100px;height:50px}
  </style></head><body><div id="root"><div data-slot="root"><div class="fixture_frame" data-sidebar-drawer><div class="fixture_sidebarCol"><div data-slot="sidebar"><div class="fixture_root" data-shortcut-modal="sidebar" role="dialog" aria-modal="true"><div class="fixture_space"></div><span class="fixture_anchor" style="anchor-name:--dsh-menu-trigger-account"><button data-signed-out="false" aria-haspopup="menu" aria-expanded="true">Synthetic account</button></span></div></div></div></div></div></div>
  <div id="account" role="menu" data-anchor-side="top" data-anchor-align="start" class="${prefix} ${portal}" style="position-anchor:--dsh-menu-trigger-account"><div class="${viewport}"><button role="menuitem" class="fixture_menuitem" data-action="settings">Settings</button><button role="menuitem" class="fixture_menuitem" data-action="feedback">Feedback</button><button role="menuitem" class="fixture_menuitem" data-action="signout">Sign out</button></div></div>
  <div id="other" role="menu" data-anchor-side="top" class="fixture_unrelated" style="position-anchor:--dsh-menu-trigger-other">Other menu</div>
  <script>delete window.__dshApp;delete window.__dshAppModal;window.messages=[];window.DshAppModal={postMessage:m=>messages.push(m)};window.clicked=[];document.addEventListener('click',e=>{if(e.target.dataset.action)clicked.push(e.target.dataset.action)});</script></body></html>`;
}
async function measure() {
  return evaluate(`(()=>{const rect=e=>{const r=e.getBoundingClientRect();return {left:r.left,right:r.right,top:r.top,bottom:r.bottom,width:r.width,height:r.height}};const m=document.querySelector('#account'),a=document.querySelector('.fixture_anchor'),s=getComputedStyle(document.documentElement);return {menu:rect(m),anchor:rect(a),marked:m.hasAttribute('data-dsh-app-account-menu'),otherMarked:document.querySelector('#other').hasAttribute('data-dsh-app-account-menu'),other:rect(document.querySelector('#other')),safeTop:parseFloat(s.getPropertyValue('--dsh-app-safe-top')),safeBottom:parseFloat(s.getPropertyValue('--dsh-app-safe-bottom')),safeLeft:parseFloat(s.getPropertyValue('--dsh-app-inset-left'))||0,safeRight:parseFloat(s.getPropertyValue('--dsh-app-inset-right'))||0,width:innerWidth,height:innerHeight,messages:messages.slice(),items:[...m.querySelectorAll('button')].map(e=>{const r=rect(e);return {...r,action:e.dataset.action,hit:e.contains(document.elementFromPoint(r.left+r.width/2,r.top+r.height/2))}})}})()`);
}
function check(g) {
  assert(g.marked && !g.otherMarked, `Only linked account menu must be marked: ${JSON.stringify(g)}`);
  assert(g.menu.top >= g.safeTop + 7.5 && g.menu.bottom <= g.height - g.safeBottom - 7.5, `Menu violates safe viewport: ${JSON.stringify(g)}`);
  assert(g.menu.left >= g.safeLeft + 7.5 && g.menu.right <= g.width - g.safeRight - 7.5, 'Menu violates horizontal safe viewport');
  assert(Math.abs(g.menu.bottom - g.anchor.top + 4) <= 1, `Bottom account must open above its trigger, not at status bar: ${JSON.stringify(g)}`);
  assert(g.items.every(i => i.hit), `Every menu item must be clickable: ${JSON.stringify(g)}`);
  assert.deepEqual(g.messages, ['closed'], 'Navigation dialog is not a blocking modal');
}
// Read the actual shipped consumers and pure Tooltip geometry, not a second
// implementation of the production App fallback. CSS fault injection models
// unresolved CSS anchors; it is not evidence of the phone's precise cause.
const core = fs.readFileSync(`${assets}/index-ghOpC9uV.js`, 'utf8');
const contextMenu = fs.readFileSync(`${root}/dsh-client-ui-context-menu/lib/client.js`, 'utf8');
const chat = fs.readFileSync(`${root}/dsh-client-ui-chat/lib/client.js`, 'utf8');
const conversation = fs.readFileSync(`${root}/dsh-client-ui-conversation/lib/client.js`, 'utf8');
const permissions = fs.readFileSync(`${root}/dsh-client-ui-permission-presets/lib/client.js`, 'utf8');
const permissionCss = permissions.match(/const css\$1=`([^`]+)`;/)[1];
const permissionTrigger = permissions.match(/"trigger":`([^`]+)`/)[1];
const permissionChevron = permissions.match(/"chevron":`([^`]+)`/)[1];
assert(permissions.includes('side:`top`,portal:true,anchor:') && permissions.includes('name:`conversation.input.permission`') && permissions.includes('onSelect:choose'));
assert(conversation.includes('renderSlot(`conversation.input.permission`,{locked})'));
assert(contextMenu.includes('anchorPoint:point') && contextMenu.includes('contextual:true') && contextMenu.includes('toggle(id,target,{x:rect.left,y:rect.bottom})'));
assert(conversation.includes('function ViewsMoreMenu') && conversation.includes('portal:true,autoFocus:true'));
assert(chat.includes('stat:`usage`') && chat.includes('openOnClick:true') && chat.includes('"data-composer-stat":stat'));
assert(core.includes('"aria-describedby":h&&oe?') && core.includes('function gH('));
const tooltipGeometry = core.slice(core.indexOf('const mH={right:'), core.indexOf('function ib(', core.indexOf('function gH(')));
const statCss = chat.match(/const css\$4=`([^`]+)`;/)[1];
const statClass = statCss.match(/\.([\w-]+_panel)\{/)[1];
const contextCss = conversation.match(/const css\$2=`([^`]+)`;/)[1];
const contextClass = contextCss.match(/\.([\w-]+_panel)\{/)[1];
assert(conversation.includes('const anchorName=`--dsh-context-') && conversation.includes('"data-composer-dock":true') && conversation.includes('className:ContextMeter_module_css_default.panel,style:{positionAnchor:anchorName},role:`dialog`'));
const tooltipClass = css.match(/\.(_bubble_[\w]+)\[data-portal\]/)[1];
const submenuClass = css.match(/\.(_submenu_[\w]+)\{/)[1];
const submenuAnchorClass = css.match(/\.(_submenuAnchor_[\w]+)\{/)[1];
const results = [];
function popupFixture(kind, fault) {
  const contextual = ['session-delete', 'workspace-delete', 'mode-ellipsis'].includes(kind);
  const header = kind.startsWith('mode') || kind === 'header-named';
  const tooltip = kind === 'cache-tooltip';
  const stat = kind === 'cache-dialog';
  const context = kind === 'context-dialog';
  const permission = kind === 'permission-menu';
  const sub = kind.startsWith('submenu-');
  const scope = permission ? 'data-slot="conversation.input.permission"' : context ? 'data-composer-dock' : stat || tooltip ? 'data-composer-stat="usage"' : `data-slot="${header ? 'conversation.session.header' : 'sidebar'}"`;
  const trigger = permission ? `<button id="trigger" class="${permissionTrigger}" type="button" aria-label="Synthetic permission"><span>Fixture mode</span><span class="${permissionChevron}">⌃</span></button>` : `<button id="trigger" ${contextual ? 'data-context-menu-trigger' : ''} aria-haspopup="${stat || context ? 'dialog' : 'menu'}" aria-expanded="true" ${tooltip ? 'aria-describedby="unrelated-id cache-tip"' : ''}>Synthetic trigger</button>`;
  const anchor = `<span id="named-anchor" style="anchor-name:${context ? '--dsh-context-exact' : '--dsh-menu-trigger-exact'}">${trigger}</span>`;
  let popup = `<div id="popup" role="menu" data-anchor-side="bottom" data-anchor-align="start" ${contextual ? 'data-context-menu' : ''} class="${prefix} ${portal}" style="position-anchor:--dsh-menu-trigger-exact"><div class="${viewport}"><button role="menuitem" data-action="delete">Delete fixture</button><button role="menuitem" data-action="second">Second action</button></div></div>`;
  if (permission) popup = `<div id="popup" role="menu" data-anchor-side="top" data-anchor-align="start" class="${prefix} ${portal}" style="position-anchor:--dsh-menu-trigger-exact"><div class="${viewport}"><button role="menuitem" data-action="fixture-read">Fixture read mode</button><button role="menuitem" data-action="fixture-write">Fixture write mode</button></div></div>`;
  if (tooltip) popup = `<span id="cache-tip" role="tooltip" data-portal="true" data-pinned="true" data-align="center" data-side="top" class="${tooltipClass}" style="visibility:visible">Cache hit synthetic tooltip</span>`;
  if (stat) popup = `<div id="popup" role="dialog" class="${statClass}" style="position-anchor:--dsh-menu-trigger-exact"><dl data-session-stats-usage><dt>Cached input</dt><dd>100 tok</dd><dt>Cache hit</dt><dd>50%</dd></dl></div>`;
  if (context) popup = `<div id="popup" role="dialog" class="${contextClass}" style="position-anchor:--dsh-context-exact"><div>Context used 50%</div><dl><dt>System</dt><dd>1000 tok</dd><dt>Tools</dt><dd>2000 tok</dd><dt>Messages</dt><dd>3000 tok</dd></dl></div>`;
  if (sub) popup += `<div id="child" role="menu" data-submenu-layout="${kind === 'submenu-page' ? 'page' : 'side'}" class="${submenuClass}" style="--dsh-submenu-parent:--dsh-submenu-parent-exact;--dsh-submenu-row-offset:10px"><div class="${viewport}"><button role="menuitem" data-action="child">Child fixture</button></div></div>`;
  return `<!doctype html><html data-dsh-app-lite data-dsh-app-layout="drawer"><head><meta name="viewport" content="width=device-width,initial-scale=1"><style>${css}\n${statCss}\n${contextCss}\n${permissionCss}</style><style>${adaptation}</style><style>
  html,body{margin:0;width:100%;height:100%;--dsh-app-safe-top:40px;--dsh-app-safe-bottom:24px;--dsh-app-inset-left:0px;--dsh-app-inset-right:0px}#root{position:fixed;inset:40px 0 60px;height:auto!important;transform:translateZ(0)}
  #scope{position:absolute;${context ? 'bottom:18px;right:24px' : tooltip || stat || permission ? 'bottom:18px;left:24px' : header ? 'top:16px;right:20px' : 'top:70px;left:30px'};display:flex}#named-anchor{display:inline-flex}#trigger{height:36px;width:140px}#popup button,#child button{display:block;box-sizing:border-box;height:34px;width:140px;flex:none}#popup,#child{overflow:auto}#other{position:fixed;left:160px;top:110px;width:100px;height:44px}body>[role=tooltip]:not(#cache-tip){left:150px;top:110px}
  ${fault ? '#popup,#child{position-anchor:--unresolved-fixture-anchor!important}' : ''}
  </style></head><body><div id="root"><div id="scope" ${scope}>${contextual ? trigger : anchor}</div><div data-slot="shell.overlay">${contextual ? '<span id="virtual" style="position:fixed;width:0;height:0;anchor-name:--dsh-menu-trigger-exact"></span>' : ''}</div></div>${popup}<div id="other" role="dialog" style="position-anchor:--unrelated">Unrelated dialog</div><span role="tooltip" id="not-cache-tip" data-portal="true" class="${tooltipClass}">Unrelated tooltip</span><script>
  (function(){delete window.__dshApp;window.clicked=[];document.addEventListener('click',e=>{if(e.target.dataset.action)clicked.push(e.target.dataset.action)});
  ${tooltipGeometry}
  const t=document.querySelector('#trigger'),p=document.querySelector('${tooltip ? '#cache-tip' : '#popup'}'),v=document.querySelector('#virtual');
  if(v){const r=t.getBoundingClientRect();v.style.left=r.left+'px';v.style.top=r.bottom+'px'}
  if(${sub}){const a=document.createElement('span');a.className='${submenuAnchorClass}';a.style.anchorName='--dsh-submenu-parent-exact';p.append(a)}
  if(${tooltip}){const a=t.getBoundingClientRect(),r=p.getBoundingClientRect(),g=gH({anchor:a,width:r.width,height:r.height,viewportWidth:innerWidth,viewportHeight:innerHeight,side:'top',align:'center',gap:8});p.style.left=(g.left+g.width/2)+'px';p.style.top=(g.top+g.height)+'px';p.dataset.side=g.side}
  })();</script></body></html>`;
}
async function popupGeometry(kind) {
  return evaluate(`(()=>{const rect=e=>{const r=e.getBoundingClientRect();return {left:r.left,right:r.right,top:r.top,bottom:r.bottom,width:r.width,height:r.height}};const p=document.querySelector('${kind === 'cache-tooltip' ? '#cache-tip' : kind.startsWith('submenu-') ? '#child' : '#popup'}'),s=getComputedStyle(document.documentElement);return {popup:rect(p),trigger:rect(document.querySelector('#trigger')),parent:document.querySelector('#popup')?rect(document.querySelector('#popup')):null,marked:p.hasAttribute('data-dsh-app-anchor-popup'),otherMarked:document.querySelector('#other').hasAttribute('data-dsh-app-anchor-popup'),other:rect(document.querySelector('#other')),unrelatedTipMarked:document.querySelector('#not-cache-tip').hasAttribute('data-dsh-app-anchor-popup'),bounds:{left:(parseFloat(s.getPropertyValue('--dsh-app-inset-left'))||0)+8,right:innerWidth-(parseFloat(s.getPropertyValue('--dsh-app-inset-right'))||0)-8,top:parseFloat(s.getPropertyValue('--dsh-app-safe-top'))+8,bottom:innerHeight-parseFloat(s.getPropertyValue('--dsh-app-safe-bottom'))-8},items:[...p.querySelectorAll('[data-action]')].map(e=>({...rect(e),action:e.dataset.action,hit:(()=>{const r=e.getBoundingClientRect();return e.contains(document.elementFromPoint(r.left+r.width/2,r.top+r.height/2))})()}))}})()`);
}
function checkPopup(g, kind) {
  assert(g.marked && !g.otherMarked && !g.unrelatedTipMarked, `${kind}: only exact linked popup is adapted ${JSON.stringify(g)}`);
  const p = g.popup, b = g.bounds;
  assert(p.top >= b.top-.5 && p.bottom <= b.bottom+.5 && p.left >= b.left-.5 && p.right <= b.right+.5, `${kind}: safe viewport ${JSON.stringify(g)}`);
  assert(g.items.every(i => i.hit), `${kind}: action hit targets ${JSON.stringify(g)}`);
  if (kind === 'context-dialog') assert(Math.abs(p.width-Math.min(264,b.right-b.left))<1, 'Context panel preserves its official 264px width');
  if (kind === 'cache-tooltip' || kind === 'cache-dialog' || kind === 'context-dialog' || kind === 'permission-menu') assert(Math.abs(p.bottom - g.trigger.top + (kind === 'cache-dialog' || kind === 'permission-menu' ? 4 : 8)) < 1, `${kind}: opens above actual trigger ${JSON.stringify(g)}`);
  else if (kind === 'submenu-page') assert(Math.abs(p.left-g.parent.left) < 1 && Math.abs(p.top-g.parent.top) < 1, 'Submenu page replaces its exact parent');
  else if (kind === 'submenu-side') assert(Math.abs(p.left-g.parent.right-4) < 1 || Math.abs(p.right-g.parent.left+4) < 1, 'Submenu stays beside exact parent');
  else assert(Math.abs(p.top-g.trigger.bottom-4) < 1, `${kind}: stays beside clicked trigger ${JSON.stringify(g)}`);
}
try {
  for (let i = 0; i < 100 && !await available(); i++) { assert(edge.exitCode === null, 'Owned Edge exited'); await delay(100); }
  const version = await fetch(`${endpoint}/json/version`).then(r => r.json()); browser = await connect(version.webSocketDebuggerUrl);
  const target = (await fetch(`${endpoint}/json/list`).then(r => r.json())).find(t => t.type === 'page'); client = await connect(target.webSocketDebuggerUrl);
  for (const [width, height] of [[363, 800], [320, 640], [800, 363]]) {
    await client.command('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: true });
    const { frameTree } = await client.command('Page.getFrameTree');
    await client.command('Page.setDocumentContent', { frameId: frameTree.frame.id, html: fixture(width, height) });
    if (!broken) await evaluate(phone);
    await evaluate(modal); await paint();
    const initial = await measure();
    if (broken) { assert(!initial.marked); assert(Math.abs(initial.menu.bottom - initial.anchor.top + 4) > 10, 'Bad baseline must lose anchor'); results.push({ width, height, baseline: initial }); continue; }
    check(initial); const other = initial.other;
    // A changing footer and status inset must move the portal, not freeze it to top.
    await evaluate(`document.documentElement.style.setProperty('--dsh-app-safe-top','52px');document.documentElement.style.setProperty('--dsh-app-inset-left','28px');document.documentElement.style.setProperty('--dsh-app-inset-right','18px');document.querySelector('.fixture_anchor').style.marginBottom='23px'`); await paint();
    const moved = await measure(); check(moved); assert(Math.abs(moved.menu.top - initial.menu.top) > 20); assert.deepEqual(moved.other, other);
    // Simulated keyboard geometry, then dismissal, rotation and foreground report.
    // Match WebPageInsets' keyboard sheet: the fixed sidebar column also ends
    // at the keyboard (changing #root alone does not resize that fixed layer).
    const keyboard = Math.min(220, Math.round(height * .24));
    await evaluate(`document.documentElement.style.setProperty('--dsh-app-safe-bottom','${keyboard}px');document.querySelector('#root').style.bottom='${keyboard}px';document.querySelector('.fixture_sidebarCol').style.setProperty('bottom','${keyboard}px','important');window.dispatchEvent(new Event('resize'))`); await paint(); check(await measure());
    await evaluate(`document.documentElement.style.setProperty('--dsh-app-safe-bottom','24px');document.querySelector('#root').style.bottom='60px';document.querySelector('.fixture_sidebarCol').style.removeProperty('bottom');document.dispatchEvent(new Event('visibilitychange'));window.dispatchEvent(new Event('pageshow'))`); await paint(); check(await measure());
    for (const item of (await measure()).items) {
      for (const type of ['mousePressed', 'mouseReleased']) await client.command('Input.dispatchMouseEvent', { type, x: item.left + item.width / 2, y: item.top + item.height / 2, button: 'left', clickCount: 1 });
    }
    assert.deepEqual(await evaluate('clicked'), ['settings','feedback','signout']);
    await evaluate(`document.querySelector('[data-signed-out]').setAttribute('aria-expanded','false')`); await paint(); assert(!(await measure()).marked, 'Closing account releases adaptation');
    await evaluate(`document.querySelector('[data-signed-out]').setAttribute('aria-expanded','true')`); await paint(); check(await measure());
    await evaluate(`document.documentElement.setAttribute('data-dsh-app-layout','desktop')`); await paint(); assert(!(await measure()).marked, 'Desktop retains upstream menu positioning');
    await evaluate(`document.documentElement.setAttribute('data-dsh-app-layout','drawer');document.documentElement.removeAttribute('data-dsh-app-lite')`); await paint(); assert(!(await measure()).marked, 'Full edition retains upstream menu positioning');
    await evaluate(`document.documentElement.setAttribute('data-dsh-app-lite','')`); await paint(); check(await measure());
    await evaluate(`var d=document.createElement('div');d.role='dialog';d.style.cssText='position:fixed;inset:60px;background:white';d.id='real-modal';document.body.append(d)`); await paint(); assert.equal((await measure()).messages.at(-1), 'open');
    await evaluate(`document.querySelector('#real-modal').remove()`); await paint(); assert.equal((await measure()).messages.at(-1), 'closed');
    const shot = await client.command('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false }); fs.writeFileSync(`${output}/${width}x${height}.png`, Buffer.from(shot.data, 'base64'));
    const stability = await mutationStability(); assert.equal(stability.quietStyleMutations, 0, 'Account style observer must converge');
    results.push({ width, height, initial, moved, stability });
  }
  for (const [width, height] of [[363,800],[320,640],[800,363]]) {
    for (const kind of ['session-delete','workspace-delete','mode-ellipsis','header-named','cache-tooltip','cache-dialog','context-dialog','permission-menu','submenu-page','submenu-side']) {
      if (kind === 'submenu-side' && width < 600) continue; // rc2 selects page, not side, at these widths.
      for (const fault of [false,true]) {
        await client.command('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: true });
        const { frameTree } = await client.command('Page.getFrameTree');
        await client.command('Page.setDocumentContent', { frameId: frameTree.frame.id, html: popupFixture(kind, fault) });
        if (!broken) await evaluate(phone);
        await paint();
        const initial = await popupGeometry(kind);
        if (!broken) checkPopup(initial, kind);
        // Move the real trigger without updating the virtual anchorPoint or
        // Tooltip's captured JS coordinates. The upstream Tooltip listens to
        // window resize, not scroll or native inset-sheet changes.
        await evaluate(`document.querySelector('#scope').style.transform='translate(7px,-13px)';document.dispatchEvent(new Event('scroll'))`);
        await paint(); const moved = await popupGeometry(kind);
        if (broken) {
          assert(!moved.marked);
          if (kind === 'cache-tooltip') assert(Math.abs(moved.popup.bottom-moved.trigger.top+8)>10, 'Stale JS tooltip baseline must fail after scroll');
          else if (fault && !kind.startsWith('submenu-')) assert(Math.abs(moved.popup.top-moved.trigger.bottom-4)>10, `${kind} CSS anchor fault must fail baseline`);
          results.push({width,height,kind,fault,baseline:initial,moved}); continue;
        }
        checkPopup(moved, kind);
        assert.deepEqual(moved.other, initial.other, 'Unrelated dialog geometry must stay upstream-owned');
        // Body transforms are not assumed to be the phone cause; independently
        // stress the fixed containing-block conversion and safe-area clamping.
        await evaluate(`document.body.style.transform='translate(5px,9px)';document.documentElement.style.setProperty('--dsh-app-inset-left','24px');document.documentElement.style.setProperty('--dsh-app-inset-right','18px');document.documentElement.style.setProperty('--dsh-app-safe-top','52px')`);
        await paint(); const transformed = await popupGeometry(kind); checkPopup(transformed, kind);
        if (!kind.startsWith('submenu-')) {
          const keyboard = Math.min(180,Math.round(height*.22));
          await evaluate(`document.documentElement.style.setProperty('--dsh-app-safe-bottom','${keyboard}px');document.querySelector('#root').style.bottom='${keyboard}px';window.dispatchEvent(new Event('resize'))`);
          await paint(); checkPopup(await popupGeometry(kind), kind);
        }
        for (const item of (await popupGeometry(kind)).items) {
          for (const type of ['mousePressed','mouseReleased']) await client.command('Input.dispatchMouseEvent', {type,x:item.left+item.width/2,y:item.top+item.height/2,button:'left',clickCount:1});
        }
        assert.deepEqual(await evaluate('clicked'), (await popupGeometry(kind)).items.map(i=>i.action), `${kind}: all official action targets preserved`);
        const stability = await mutationStability();
        assert.equal(stability.quietStyleMutations, 0, `${kind}: style MutationObserver/rAF must converge after event burst`);
        if (kind === 'permission-menu') {
          await evaluate(`document.querySelector('#scope').setAttribute('data-slot','conversation.input.unrelated');window.dispatchEvent(new Event('resize'))`); await paint();
          assert(!(await popupGeometry(kind)).marked, 'Unrelated composer slot must not claim permission menu');
          await evaluate(`document.querySelector('#scope').setAttribute('data-slot','conversation.input.permission');document.querySelector('#trigger span:last-child').className='unrelated';window.dispatchEvent(new Event('resize'))`); await paint();
          assert(!(await popupGeometry(kind)).marked, 'Permission scope requires its chevron trigger contract');
          await evaluate(`document.querySelector('#trigger span:last-child').className='${permissionChevron}';window.dispatchEvent(new Event('resize'))`); await paint(); checkPopup(await popupGeometry(kind),kind);
          await evaluate(`document.querySelector('#named-anchor').setAttribute('hidden','')`); await paint(); assert(!(await popupGeometry(kind)).marked,'Hidden permission trigger releases layout');
          await evaluate(`document.querySelector('#named-anchor').removeAttribute('hidden')`); await paint(); checkPopup(await popupGeometry(kind),kind);
          assert.deepEqual(await evaluate(`[document.querySelector('#trigger').hasAttribute('aria-haspopup'),document.querySelector('#trigger').hasAttribute('aria-expanded')]`),[false,false],'App must not rewrite official permission trigger semantics');
        }
        if (kind === 'context-dialog') {
          await evaluate(`document.querySelector('#scope').removeAttribute('data-composer-dock');window.dispatchEvent(new Event('resize'))`); await paint();
          assert(!(await popupGeometry(kind)).marked, 'Context anchor outside composer dock is not claimed');
          await evaluate(`document.querySelector('#scope').setAttribute('data-composer-dock','');document.querySelector('#trigger').setAttribute('aria-haspopup','menu');window.dispatchEvent(new Event('resize'))`); await paint();
          assert(!(await popupGeometry(kind)).marked, 'Context requires the exact dialog trigger contract');
          await evaluate(`document.querySelector('#trigger').setAttribute('aria-haspopup','dialog');window.dispatchEvent(new Event('resize'))`); await paint(); checkPopup(await popupGeometry(kind), kind);
        }
        // Ambiguous/unexpanded contextual triggers must never select an
        // unrelated menu. A new occurrence has a new body portal node.
        if (['session-delete','workspace-delete','mode-ellipsis'].includes(kind)) {
          await evaluate(`(()=>{const m=document.querySelector('#popup'),v=document.querySelector('#virtual'),t=document.querySelector('#trigger');m.remove();const r=t.getBoundingClientRect();v.style.left=r.left+'px';v.style.top=r.bottom+'px';const clone=t.cloneNode(true);clone.id='duplicate';clone.style.cssText='position:absolute;inset:0';t.parentElement.append(clone);const replacement=m.cloneNode(true);replacement.removeAttribute('data-dsh-app-anchor-popup');replacement.removeAttribute('data-dsh-app-sidebar-menu');document.body.append(replacement)})()`);
          await paint(); assert(!(await popupGeometry(kind)).marked, 'Duplicate expanded triggers at same point remain unclaimed');
        }
        results.push({width,height,kind,fault,initial,moved,transformed,stability});
      }
    }
  }
  fs.writeFileSync(`${output}/${broken ? 'before' : 'after'}.json`, JSON.stringify(results, null, 2)); console.log(`Account/context/header/cache/submenu ${broken ? 'bad baseline reproduced' : 'geometry passed'}: ${results.length} viewport/scenario cases`);
} finally { client?.ws.close(); if (browser) { await browser.command('Browser.close').catch(() => {}); browser.ws.close(); } else edge.kill(); }
