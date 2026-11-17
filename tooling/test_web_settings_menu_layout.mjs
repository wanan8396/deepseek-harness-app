// Settings Menu geometry/input regression: real Edge + shipped rc2 CSS and DOM
// contracts, synthetic state only. No engine, account or preference RPC runs.
// node tooling/test_web_settings_menu_layout.mjs
// Bad baseline: --phone-js=.harness-tmp-current/settings-menu/phone-before.js --expect-broken
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { spawn } from 'node:child_process';
import { runInNewContext } from 'node:vm';

const root = '.harness-tmp-rc2/linux-arm64-prefix/node_modules/@deepseek-ai';
const output = '.harness-tmp-current/settings-menu';
fs.mkdirSync(output, { recursive: true });
const option = name => process.argv.find(arg => arg.startsWith(`--${name}=`))?.slice(name.length + 3);
const before = process.argv.includes('--expect-broken');
const probe = process.argv.includes('--probe');
const phonePath = option('phone-js') || 'app/assets/web/dsh_web_phone.js';
const phone = fs.readFileSync(phonePath, 'utf8');
const adaptation = fs.readFileSync('app/assets/web/dsh_web_phone.css', 'utf8');
const read = name => fs.readFileSync(`${root}/${name}`, 'utf8');
const files = {
  general: 'dsh-client-ui-settings-general/lib/client.js',
  chat: 'dsh-client-ui-chat/lib/client.js',
  conversation: 'dsh-client-ui-conversation/lib/client.js',
  theme: 'dsh-client-ui-theme/lib/client.js',
};
const source = Object.fromEntries(Object.entries(files).map(([key, file]) => [key, read(file)]));
const assets = `${root}/dsh-web-frontend/dist/assets`;
const core = fs.readFileSync(`${assets}/index-ghOpC9uV.js`, 'utf8');
const coreCss = fs.readdirSync(assets).filter(name => name.endsWith('.css')).map(name => fs.readFileSync(`${assets}/${name}`, 'utf8')).join('\n');
const decode = literal => {
  assert(!literal.startsWith('`') || !literal.includes('${'), 'Only static CSS templates are accepted');
  return literal.startsWith('"') ? JSON.parse(literal) : runInNewContext(literal, Object.create(null), { timeout: 1000 });
};
const cssFrom = text => [...text.matchAll(/\bconst\s+css(?:\$\d+)?\s*=\s*("(?:[^"\\]|\\.)*"|`(?:[^`\\]|\\.)*`)\s*;/g)].map(m => decode(m[1])).join('\n');
const classMap = (text, name) => {
  const literal = text.match(new RegExp(`var ${name}=({[^}]+})`))?.[1];
  assert(literal, `Missing shipped class map ${name}`);
  return runInNewContext(`(${literal})`, Object.create(null), { timeout: 1000 });
};
const settings = classMap(source.general, 'SettingsRoot_module_css_default');
const section = classMap(source.general, 'GeneralSection_module_css_default');
const preference = classMap(source.chat, 'PreferenceRow_module_css_default');
const enter = classMap(source.conversation, 'EnterBehaviorRow_module_css_default');
const menu = Object.fromEntries(['root', 'list', 'portal', 'scrollable', 'viewport', 'itemWrap', 'item', 'itemLabel', 'check', 'selected'].map(key => {
  // The primitive core's minified class map is shared by Menu and MenuItem.
  const match = coreCss.match(new RegExp(`\\.(_${key}_70kcw_[\\w]+)[{.,\\[: ]`));
  assert(match, `Missing shipped Menu ${key} class`);
  return [key, match[1]];
}));
const surface = Object.fromEntries(['surface', 'material', 'backing'].map(key => [key, coreCss.match(new RegExp(`\\.(_${key}_1w4el_[\\w]+)[{.,\\[: ]`))[1]]));
const themeMatches = [...source.theme.matchAll(/\b(?:const|let|var)\s+[\w$]+\s*=\s*("(?:[^"\\]|\\.)*"|`(?:[^`\\]|\\.)*`)\s*;/g)].filter(m => m[1].includes('body{--dsw-static-amber-100:'));
assert.equal(themeMatches.length, 1, 'Exact official theme must be available');
const themeCss = decode(themeMatches[0][1]);
const officialCss = [coreCss, themeCss, cssFrom(source.general), cssFrom(source.chat), cssFrom(source.conversation)].join('\n');
// Verify fixture contracts against shipped consumers and Menu, independently of
// phone.js. Do not use native select, a forced unresolved anchor, or hand-picked
// menu top/left CSS: those would miss this regression.
assert(source.general.includes('"data-shortcut-modal":`settings`') && source.general.includes('document.body'));
assert(source.chat.includes('align:`end`,portal:true,anchor:selector'));
assert(source.chat.includes('id:`compact`,label:`settings.performance.compact`') && source.chat.includes('id:`detailed`,label:`settings.performance.detailed`'));
assert(source.conversation.includes('id:`queue`,label:`settings.enter.queue`') && source.conversation.includes('id:`steer`,label:`settings.enter.steer`'));
assert(source.conversation.includes('align:`end`,portal:true,anchor:'));
for (const value of ['settings.collapse.completion', 'settings.collapse.nextInput', 'settings.foldedReplies.all', 'settings.foldedReplies.final', 'settings.links.sidebar', 'settings.links.newTab']) assert(source.chat.includes(value), `Missing official preference ${value}`);
assert(core.includes('side:h="bottom"') && core.includes('positionAnchor:Oe') && core.includes('anchorName:I===void 0?Oe:void 0'));
assert(core.includes('Tn.createPortal(Jt,document.body)') && core.includes('"data-menu-backing":""'));
const sha = text => createHash('sha256').update(text).digest('hex');
const identity = { phonePath, phoneSha256: sha(phone), cssSha256: sha(adaptation), coreSha256: sha(core), officialCssSha256: sha(officialCss), bundles: Object.fromEntries(Object.entries(source).map(([key, text]) => [files[key], sha(text)])) };

const cases = [
  { id: 'performance', title: '性能与用量', desc: '选择性能与用量信息展示的详细程度', choices: [['compact', '简洁'], ['detailed', '详细']] },
  { id: 'enter', title: '繁忙时的发送行为', desc: '智能体运行时 Enter 键和发送按钮的行为；Cmd/Ctrl+Enter 使用另一行为', choices: [['queue', '排队发送'], ['steer', '插话发送']] },
  { id: 'collapse', title: '工作步骤收起时机', desc: '选择何时自动收起工作步骤', choices: [['completion', '回答结束后'], ['next-input', '下次输入时']] },
  { id: 'folded', title: '收起时显示的回复', desc: '折叠工作步骤后的回答显示方式', choices: [['all', '全部回复'], ['final', '最终回复']] },
  { id: 'links', title: '链接打开位置', desc: '选择 HTTP(S) 链接默认打开位置', choices: [['sidebar', '侧栏'], ['new-tab', '新标签页']] },
];
const esc = text => text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('"', '&quot;');
function fixture(dark, font) {
  const row = (item, index) => {
    const c = item.id === 'enter' ? enter : preference;
    return `<div data-slot="settings.general.item"><div class="${c.row}" id="row-${item.id}"><div class="${c.rowText}"><div class="${c.title}">${esc(item.title)}</div><div class="${c.desc}">${esc(item.desc)}</div></div><span class="${menu.root}" style="anchor-name:--dsh-menu-trigger-settings-${index}"><button id="trigger-${item.id}" type="button" class="${c.selector}" aria-haspopup="menu" aria-expanded="false"><span>${esc(item.choices[0][1])}</span><svg class="${c.chevron}" width="14" height="14"><path d="M3 5l4 4 4-4" fill="none" stroke="currentColor"/></svg></button></span></div></div>`;
  };
  const filler = Array.from({ length: 8 }, (_, i) => `<div data-slot="settings.general.item"><div class="${preference.row}"><div class="${preference.rowText}"><div class="${preference.title}">合成滚动行 ${i + 1}</div><div class="${preference.desc}">仅验证设置内容滚动，不连接真实设置</div></div></div></div>`).join('');
  return `<!doctype html><html data-dsh-app-lite data-dsh-app-layout="drawer"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>${officialCss}</style><style>${adaptation}</style><style>
  html,body{margin:0;height:100%;overflow:hidden;--dsh-app-safe-top:40px;--dsh-app-safe-bottom:24px;--dsh-app-inset-top:40px;--dsh-app-inset-bottom:60px;--dsh-app-inset-left:0px;--dsh-app-inset-right:0px}
  #root{position:fixed;inset:40px 0 60px;height:auto!important;min-height:0!important}[data-slot]{display:contents}
  /* Explicit text-size stress, not a change to the app's typography/theme. */
  ${font === 14 ? '' : `[data-slot="settings.general.item"] button,[data-slot="settings.general.item"] [class*="_title"],[role="menu"] button{font-size:${font}px!important}`}
  #unrelated{position:fixed;top:80px;left:12px;width:120px;height:36px;z-index:0}
  </style><style id="fixture-keyboard"></style></head><body ${dark ? 'data-ds-dark-theme' : ''}><div id="root" inert><div data-slot="root"><div class="fixture_frame" data-sidebar-drawer data-sidebar-collapsed></div></div><span style="anchor-name:--dsh-menu-trigger-account" data-slot="sidebar"><button aria-haspopup="menu" aria-expanded="true" data-signed-out="false">Inactive account fixture</button></span></div>
  <div class="${settings.overlay}" role="presentation"><div class="${settings.mask}" aria-hidden="true"></div><div tabindex="-1" data-shortcut-modal="settings" class="${settings.panel}" role="dialog" aria-modal="true"><div class="${settings.navTitle}">设置</div><nav class="${settings.nav}"><div class="${settings.navList}">${['通用设置', '模型', '内置插件', '会话日志', '其他插件'].map((title, i) => `<button type="button" class="${settings.navCell} ${i === 0 ? settings.active : ''}">${title}</button>`).join('')}</div></nav><div class="${settings.header}"><div class="${settings.actions}"></div><button class="${settings.close}" type="button" aria-label="关闭">×</button></div><div class="${settings.options}" id="settings-scroll"><div data-slot="settings.section"><div class="${section.section}">${filler}${cases.map(row).join('')}${filler}</div></div></div></div></div>
  <div id="unrelated" role="menu" data-anchor-side="bottom" style="position-anchor:--dsh-menu-trigger-not-settings">Unrelated</div>
  <script>(function(){window.fixtureState={values:{performance:'compact',enter:'queue'},clicks:[],pointerHits:[],opened:null};
  const cases=${JSON.stringify(cases)}, menu=${JSON.stringify(menu)}, surface=${JSON.stringify(surface)};
  const dismiss=()=>{document.querySelector('#settings-menu')?.remove();document.querySelector('[data-menu-backing]')?.remove();document.querySelectorAll('[id^="trigger-"]').forEach(e=>e.setAttribute('aria-expanded','false'));fixtureState.opened=null};
  cases.forEach((item,index)=>document.querySelector('#trigger-'+item.id).addEventListener('click',()=>{
    if(fixtureState.opened===item.id){dismiss();return}dismiss();fixtureState.opened=item.id;
    const trigger=document.querySelector('#trigger-'+item.id);trigger.setAttribute('aria-expanded','true');
    const list=document.createElement('div');list.id='settings-menu';list.role='menu';list.className=[menu.list,menu.portal,menu.scrollable,surface.surface].join(' ');list.dataset.anchorSide='bottom';list.dataset.anchorAlign='end';list.dataset.menuMaterial='translucent';list.style.positionAnchor='--dsh-menu-trigger-settings-'+index;list.style.setProperty('--dsh-menu-anchor','--dsh-menu-settings-surface');
    list.innerHTML='<div aria-hidden="true" class="'+surface.material+'"></div><div role="presentation" class="'+menu.viewport+'">'+item.choices.map(([value,label])=>'<div class="'+menu.itemWrap+'"><button type="button" role="menuitem" class="'+menu.item+'" data-value="'+value+'"><span class="'+menu.itemLabel+'">'+label+'</span></button></div>').join('')+'</div>';
    list.addEventListener('click',event=>{const button=event.target.closest('[data-value]');if(!button)return;fixtureState.values[item.id]=button.dataset.value;fixtureState.clicks.push({id:item.id,value:button.dataset.value});trigger.firstElementChild.textContent=button.textContent;trigger.focus({preventScroll:true});dismiss()});document.body.append(list);
    const backing=document.createElement('div');backing.className=surface.backing;backing.dataset.menuBacking='';backing.setAttribute('aria-hidden','true');backing.style.setProperty('--dsh-menu-anchor','--dsh-menu-settings-surface');document.body.append(backing);
  }));
  document.addEventListener('pointerdown',e=>fixtureState.pointerHits.push({target:e.target.closest('button')?.id||e.target.closest('[data-value]')?.dataset.value||e.target.id,x:e.clientX,y:e.clientY}));
  document.addEventListener('keydown',e=>{if(e.key==='Escape')dismiss()});
  window.fixtureDismiss=dismiss;
  })();</script></body></html>`;
}

const endpoint = 'http://127.0.0.1:19231';
const available = async () => { try { return (await fetch(`${endpoint}/json/version`, { signal: AbortSignal.timeout(500) })).ok; } catch { return false; } };
assert(!await available(), 'Dedicated settings test port 19231 is occupied');
const edgePath = process.env.DSH_SETTINGS_EDGE || 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
const edge = spawn(edgePath, ['--headless=new', '--remote-debugging-port=19231', `--user-data-dir=${path.resolve(output, 'edge-profile')}`, '--no-first-run', '--disable-background-networking', 'about:blank'], { stdio: 'ignore' });
let client, browser;
const connect = url => new Promise((resolve, reject) => {
  const ws = new WebSocket(url), pending = new Map(); let id = 0;
  ws.onerror = reject;
  ws.onopen = () => resolve({ ws, command(method, params = {}) { return new Promise((r, j) => {
    const key = ++id, timer = setTimeout(() => { pending.delete(key); j(Error(`CDP timeout ${method}`)); }, 10000);
    pending.set(key, { r, j, timer }); ws.send(JSON.stringify({ id: key, method, params }));
  }); } });
  ws.onmessage = event => { const message = JSON.parse(event.data), p = pending.get(message.id); if (!p) return; pending.delete(message.id); clearTimeout(p.timer); message.error ? p.j(Error(message.error.message)) : p.r(message.result); };
});
async function evaluate(expression) {
  const result = await client.command('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
  if (result.exceptionDetails) throw Error(result.exceptionDetails.exception?.description || result.exceptionDetails.text);
  return result.result.value;
}
const paint = () => evaluate('new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(()=>requestAnimationFrame(r))))');
async function clickPoint(x, y) {
  for (const type of ['mousePressed', 'mouseReleased']) await client.command('Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1 });
  await paint();
}
async function click(selector) {
  const hit = await evaluate(`(()=>{const e=document.querySelector(${JSON.stringify(selector)}),r=e.getBoundingClientRect(),x=r.left+r.width/2,y=r.top+r.height/2;return {x,y,hit:e.contains(document.elementFromPoint(x,y))}})()`);
  assert(hit.hit, `Real pointer target is covered: ${selector} ${JSON.stringify(hit)}`);
  await clickPoint(hit.x, hit.y);
}
async function wheel(selector, delta) {
  const point = await evaluate(`(()=>{const e=document.querySelector(${JSON.stringify(selector)}),r=e.getBoundingClientRect();return {x:r.left+Math.min(24,r.width/2),y:r.top+r.height/2,before:e.scrollTop}})()`);
  await client.command('Input.dispatchMouseEvent', { type: 'mouseWheel', x: point.x, y: point.y, deltaX: 0, deltaY: delta });
  const after = await evaluate(`new Promise(resolve=>{const e=document.querySelector(${JSON.stringify(selector)}),start=performance.now();let last=e.scrollTop,stable=0;function tick(){const n=e.scrollTop;stable=Math.abs(n-last)<.5?stable+1:0;last=n;if((stable>3&&Math.abs(n-${point.before})>1)||performance.now()-start>1500)resolve(n);else requestAnimationFrame(tick)}requestAnimationFrame(tick)})`);
  assert(Math.abs(after - point.before) > 1, `Real wheel failed: ${selector} ${point.before} -> ${after}`);
  return { type: 'mouseWheel', before: point.before, after, delta };
}
async function reveal(id) {
  for (let i = 0; i < 12; i++) {
    const g = await evaluate(`(()=>{const t=document.querySelector('#trigger-${id}').getBoundingClientRect(),s=document.querySelector('#settings-scroll').getBoundingClientRect();return {top:t.top,bottom:t.bottom,center:(s.top+s.bottom)/2,height:s.height}})()`);
    const delta = (g.top + g.bottom) / 2 - g.center;
    if (Math.abs(delta) < 10) return;
    await wheel('#settings-scroll', delta);
  }
  assert.fail(`Trigger ${id} did not reach settings viewport center`);
}
async function measure(id) {
  return evaluate(`(()=>{const rect=e=>{const r=e.getBoundingClientRect();return {left:r.left,right:r.right,top:r.top,bottom:r.bottom,width:r.width,height:r.height}};const p=document.querySelector('#settings-menu'),t=document.querySelector('#trigger-${id}'),h=document.documentElement,s=getComputedStyle(h);const a=rect(t),r=rect(p),bounds={left:(parseFloat(s.getPropertyValue('--dsh-app-inset-left'))||0)+8,right:innerWidth-(parseFloat(s.getPropertyValue('--dsh-app-inset-right'))||0)-8,top:(parseFloat(s.getPropertyValue('--dsh-app-safe-top'))||0)+8,bottom:innerHeight-(parseFloat(s.getPropertyValue('--dsh-app-safe-bottom'))||0)-8};return {menu:r,trigger:a,bounds,marked:p.hasAttribute('data-dsh-app-anchor-popup'),accountMarked:p.hasAttribute('data-dsh-app-account-menu'),unrelatedMarked:document.querySelector('#unrelated').hasAttribute('data-dsh-app-anchor-popup'),unrelated:rect(document.querySelector('#unrelated')),menuStyle:{position:getComputedStyle(p).position,top:getComputedStyle(p).top,left:getComputedStyle(p).left,anchor:getComputedStyle(p).positionAnchor,zIndex:getComputedStyle(p).zIndex},theme:{panel:getComputedStyle(document.querySelector('[data-shortcut-modal="settings"]')).backgroundColor,material:getComputedStyle(p.firstElementChild).backgroundColor,color:getComputedStyle(p.querySelector('button')).color,radius:getComputedStyle(p).borderRadius},overlayMatch:p.matches('body > [class*="_overlay"]'),items:[...p.querySelectorAll('[data-value]')].map(e=>{const q=rect(e),x=q.left+q.width/2,y=q.top+q.height/2;return {...q,value:e.dataset.value,hit:e.contains(document.elementFromPoint(x,y))}})}})()`);
}
function failures(g) {
  const r = g.menu, a = g.trigger, b = g.bounds;
  const list = [];
  if (r.left < b.left - 1 || r.right > b.right + 1 || r.top < b.top - 1 || r.bottom > b.bottom + 1) list.push('safe-viewport');
  const adjacent = Math.min(Math.abs(r.top - a.bottom - 4), Math.abs(r.bottom - a.top + 4)) <= 1;
  if (!adjacent) list.push('anchor-distance');
  const expectedRight = Math.min(b.right, Math.max(b.left + r.width, a.right));
  if (Math.abs(r.right - expectedRight) > 1) list.push('end-alignment');
  if (!g.items.every(item => item.hit)) list.push('item-hit');
  if (g.accountMarked || g.unrelatedMarked || g.overlayMatch) list.push('scope');
  if (!g.marked) list.push('exact-settings-anchor');
  return list;
}
const results = [];
try {
  for (let i = 0; i < 100 && !await available(); i++) { assert(edge.exitCode === null, 'Owned Edge exited'); await new Promise(r => setTimeout(r, 100)); }
  const version = await fetch(`${endpoint}/json/version`).then(r => r.json()); browser = await connect(version.webSocketDebuggerUrl);
  const target = (await fetch(`${endpoint}/json/list`).then(r => r.json())).find(t => t.type === 'page' && t.url === 'about:blank');
  assert(target, 'Owned blank settings page is required'); client = await connect(target.webSocketDebuggerUrl);
  for (const [width, height] of [[363, 800], [320, 640], [800, 363]]) for (const dark of [false, true]) for (const font of [14, 18]) {
    await client.command('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: true });
    // Each scenario needs a fresh window: setDocumentContent alone preserves
    // idempotence markers and global event handlers from the previous page.
    await client.command('Page.navigate', { url: 'about:blank' });
    await evaluate('new Promise(r=>document.readyState==="complete"?r():window.addEventListener("load",r,{once:true}))');
    const { frameTree } = await client.command('Page.getFrameTree');
    await client.command('Page.setDocumentContent', { frameId: frameTree.frame.id, html: fixture(dark, font) });
    await evaluate(phone); await paint();
    for (const item of cases) {
      await reveal(item.id); await click(`#trigger-${item.id}`);
      const initial = await measure(item.id), errors = failures(initial);
      const result = { width, height, dark, font, id: item.id, initial, errors };
      if (!before && !probe) assert.deepEqual(errors, [], `Initial settings menu: ${JSON.stringify(result)}`);
      // Menu choices are real pointer hits; only fixture values are mutated.
      if (!errors.length) {
        for (const [index, [value]] of item.choices.entries()) {
          if (index) await click(`#trigger-${item.id}`);
          await click(`#settings-menu [data-value="${value}"]`);
          assert.equal(await evaluate(`fixtureState.values.${item.id}`), value);
        }
        result.selected = await evaluate('structuredClone(fixtureState.clicks)');
        await click(`#trigger-${item.id}`);
      }
      const movement = await wheel('#settings-scroll', 20); await paint();
      const moved = await measure(item.id); result.movement = movement; result.moved = moved; result.movedErrors = failures(moved);
      if (!before && !probe) assert.deepEqual(result.movedErrors, [], `Scrolled settings menu: ${JSON.stringify(result)}`);
      // Keyboard uses WebPageInsets' actual CSS contract; it does not resize
      // the WebView or apply a fake translation/position to the Menu itself.
      await evaluate('fixtureDismiss()');
      const keyboard = Math.min(220, Math.round(height * .25));
      await evaluate(`document.documentElement.style.setProperty('--dsh-app-safe-bottom','${keyboard}px');document.querySelector('#fixture-keyboard').textContent=':root #root{bottom:${keyboard}px!important}:root body>[class*="_overlay"]{bottom:${keyboard}px!important}';window.dispatchEvent(new Event('resize'))`);
      await paint(); await reveal(item.id); await click(`#trigger-${item.id}`);
      result.keyboard = await measure(item.id); result.keyboardErrors = failures(result.keyboard);
      if (!before && !probe) assert.deepEqual(result.keyboardErrors, [], `Keyboard settings menu: ${JSON.stringify(result)}`);
      await evaluate('fixtureDismiss();document.documentElement.style.setProperty("--dsh-app-safe-bottom","24px");document.querySelector("#fixture-keyboard").textContent="";window.dispatchEvent(new Event("resize"))'); await paint();
      results.push(result);
    }
    if (font === 14) {
      await reveal('performance'); await click('#trigger-performance');
      const shot = await client.command('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
      fs.writeFileSync(`${output}/${before ? 'before' : probe ? 'probe' : 'after'}-${width}x${height}-${dark ? 'dark' : 'light'}.png`, Buffer.from(shot.data, 'base64'));
      await evaluate('fixtureDismiss()');
    }
  }
  const brokenCases = results.filter(r => r.errors.length || r.movedErrors.length || r.keyboardErrors.length);
  fs.writeFileSync(`${output}/${before ? 'before' : probe ? 'probe' : 'after'}.json`, JSON.stringify({ identity, browser: version.Browser, evidence: 'Owned Edge rc2 DOM/CSS contract + CDP pointer/wheel; not phone or real account validation', results }, null, 2));
  if (before) assert(brokenCases.length, 'Old implementation must fail a real geometry/hit-test invariant');
  console.log(`Settings ${before ? 'old implementation failures' : probe ? 'probe failures' : 'passed'}: ${before || probe ? brokenCases.length : results.length}/${results.length}; evidence ${output}`);
} finally {
  client?.ws.close();
  if (browser) { await browser.command('Browser.close').catch(() => {}); browser.ws.close(); } else edge.kill();
}
