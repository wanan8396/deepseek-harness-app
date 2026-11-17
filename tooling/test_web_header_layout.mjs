// Synthetic Chromium regression for the bundled DSH conversation header.
// Run: node tooling/test_web_header_layout.mjs [conversation/lib/client.js]
//      [--before-css .harness-tmp-header-layout/before-phone.css] [--before-only]
// Menus: --menu-only [--before-menu-css .harness-tmp-header-layout/before-menu-phone.css]
// Dock: --dock-only [--before-dock-css .harness-tmp-header-layout/before-menu-phone.css]
// Branch pill: --branch-only [--before-branch-css path/to/pre-fix-phone.css]
// Owns only port 19227 and its dedicated Edge profile. No live page is opened.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { runInNewContext } from 'node:vm';

function extractStaticCss(source, marker) {
  // Official bundles use either JSON strings or minified template literals.
  // Select by CSS content, not a build-dependent variable name or whitespace.
  const literals = [...source.matchAll(/\b(?:const|let|var)\s+[\w$]+\s*=\s*("(?:[^"\\]|\\.)*"|`(?:[^`\\]|\\.)*`)\s*;/g)]
    .map(match => match[1]).filter(literal => literal.includes(marker));
  assert.equal(literals.length, 1, `Expected one bundled CSS literal containing ${marker}`);
  const literal = literals[0];
  assert(!literal.startsWith('`') || !literal.includes('${'), 'Bundled CSS must be static');
  // The matched grammar is a single literal, with template interpolation barred.
  return literal.startsWith('"') ? JSON.parse(literal) : runInNewContext(literal, Object.create(null), { timeout: 1000 });
}

const args = process.argv.slice(2);
const option = name => { const i = args.indexOf(name); return i < 0 ? undefined : args[i + 1]; };
const bundle = path.resolve(args.find((x, i) => !x.startsWith('--') && !['--before-css', '--before-menu-css', '--before-dock-css', '--before-branch-css'].includes(args[i - 1])) || '.harness-tmp-rc2/linux-arm64-prefix/node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js');
const beforePath = option('--before-css');
const beforeMenuPath = option('--before-menu-css');
const beforeDockPath = option('--before-dock-css');
const beforeBranchPath = option('--before-branch-css');
const branchOnly = args.includes('--branch-only');
const menuOnly = args.includes('--menu-only');
const dockOnly = args.includes('--dock-only');
const beforeOnly = args.includes('--before-only');
assert(!beforeOnly || beforePath, '--before-only requires --before-css');
const output = path.resolve(process.env.DSH_HEADER_OUTPUT || '.harness-tmp-header-layout');
const profile = process.env.DSH_HEADER_PROFILE || 'D:\\Tools\\tmp\\dsh-header-19227';
const port = 19227;
const endpoint = `http://127.0.0.1:${port}`;
const edgePath = process.env.DSH_HEADER_EDGE || 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
const source = fs.readFileSync(bundle, 'utf8');
const css = extractStaticCss(source, '_titleCluster{');
const prefix = css.match(/\.([\w-]+)_titleRow\{/)[1];
const themeSource = fs.readFileSync(path.resolve(path.dirname(bundle), '../../dsh-client-ui-theme/lib/client.js'), 'utf8');
const theme = extractStaticCss(themeSource, 'body{--dsw-static-amber-100:');
const adaptation = fs.readFileSync('app/assets/web/dsh_web_phone.css', 'utf8');
const beforeCss = beforePath ? fs.readFileSync(beforePath, 'utf8') : undefined;
const beforeMenuCss = beforeMenuPath ? fs.readFileSync(beforeMenuPath, 'utf8') : undefined;
const beforeDockCss = beforeDockPath ? fs.readFileSync(beforeDockPath, 'utf8') : undefined;
const beforeBranchCss = beforeBranchPath ? fs.readFileSync(beforeBranchPath, 'utf8') : undefined;
const headerScript = fs.readFileSync('app/assets/web/dsh_web_header.js', 'utf8');
fs.mkdirSync(output, { recursive: true });

const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const canConnect = async () => { try { return (await fetch(`${endpoint}/json/version`, { signal: AbortSignal.timeout(500) })).ok; } catch { return false; } };
assert(!(await canConnect()), `Port ${port} is occupied; preserve that browser and use the dedicated port only when free`);
const edge = spawn(edgePath, [`--remote-debugging-port=${port}`, `--user-data-dir=${profile}`, '--headless=new', '--no-first-run', '--no-default-browser-check', '--disable-extensions', '--disable-background-networking', 'about:blank'], { stdio: 'ignore' });
let launchError;
edge.on('error', error => { launchError = error; });
let client;
let browserClient;
let closed = false;
const results = [];
function connect(url) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    const pending = new Map();
    let next = 0;
    ws.onerror = reject;
    ws.onopen = () => resolve({
      ws,
      command(method, params = {}) {
        return new Promise((r, j) => {
          const id = ++next;
          const timer = setTimeout(() => { pending.delete(id); j(Error(`CDP timeout: ${method}`)); }, 8000);
          pending.set(id, { r, j, timer });
          ws.send(JSON.stringify({ id, method, params }));
        });
      },
    });
    ws.onmessage = event => {
      const message = JSON.parse(event.data);
      const item = pending.get(message.id);
      if (!item) return;
      pending.delete(message.id);
      clearTimeout(item.timer);
      message.error ? item.j(Error(message.error.message)) : item.r(message.result);
    };
    ws.onclose = () => {
      for (const item of pending.values()) { clearTimeout(item.timer); item.j(Error('CDP connection closed')); }
      pending.clear();
    };
  });
}
const evaluate = async expression => {
  const r = await client.command('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
  if (r.exceptionDetails) throw Error(r.exceptionDetails.exception?.description || r.exceptionDetails.text);
  return r.result.value;
};
const paint = () => evaluate('new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)))');
const select = suffix => `.${prefix}_${suffix}`;
function fixture(dark, lite, adaptedCss) {
  const icon = '<svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true"><path d="M3 8h10M8 3v10" stroke="currentColor"/></svg>';
  const status = ['运行中 3 项', '上下文 128K / 200K', '工作区可编辑'].map((text, i) => `<button class="fixture_status" data-action="status-${i}" aria-label="${text}">${icon}<span>${text}</span></button>`).join('');
  const c = suffix => `${prefix}_${suffix}`;
  // Only synthetic control appearance and the real slot wrapper behavior are
  // supplied here. No header row/cluster/crumb layout is invented by the fixture.
  const base = `html,body{margin:0;height:100%;font:14px 'Segoe UI','Microsoft YaHei',sans-serif}body{background:var(--dsw-alias-bg-base);color:var(--dsw-alias-label-primary)}[data-slot]{display:contents}#root{height:100%;padding-top:40px;box-sizing:border-box}.fixture_status{display:inline-flex;align-items:center;gap:6px;white-space:nowrap;font:inherit;line-height:18px;border:0;border-radius:8px;padding:3px 2px;color:inherit;background:transparent}.fixture_icon{display:flex;align-items:center;justify-content:center;width:28px;height:28px;padding:0;border:0;border-radius:6px;color:inherit;background:transparent}.fixture_status svg,.fixture_icon svg{flex:none}.fixture_utilityRoot{display:inline-flex;align-items:center}.fixture_split{display:inline-flex;align-items:stretch;height:24px}:root{--dsh-app-safe-top:40px;--dsh-app-safe-bottom:24px;--dsh-app-inset-top:40px;--dsh-app-inset-bottom:24px;--dsh-app-lead:0px}`;
  // Menu geometry follows the captured upstream Menu structure: relative span,
  // absolute bottom/end surface, material and overflow:auto viewport children.
  const menuCss = '.fixture_menuRoot{position:relative;display:flex;flex:none}.fixture_menu{position:absolute;top:calc(100% + 4px);right:0;z-index:100;display:flex;flex-direction:column;width:174px;padding:4px;box-sizing:border-box;border-radius:8px;color:var(--dsw-alias-label-primary);background:var(--dsw-specific-menu);box-shadow:0 4px 16px #0003}.fixture_menuMaterial{position:absolute;inset:0;z-index:-1;border-radius:inherit;background:var(--dsw-specific-menu)}.fixture_menuViewport{display:flex;flex-direction:column;overflow:auto}.fixture_menu [role="menuitem"]{height:30px;min-height:30px;flex:none;text-align:left;white-space:nowrap;border:0;border-radius:4px;background:transparent;color:inherit;padding:4px 8px;font:inherit}';
  const fixtureScript = `window.fixtureClicks=[];window.fixtureMenusEnabled=false;delete window.__dshAppHeaderMenus;document.addEventListener('click',e=>{const b=e.target.closest('[data-action]');if(!b)return;fixtureClicks.push(b.dataset.action);if(!fixtureMenusEnabled)return;if(b.dataset.action==='more'){const existing=document.querySelector('[role="menu"]');if(existing){existing.remove();b.setAttribute('aria-expanded','false')}else{const menu=document.createElement('div');menu.setAttribute('role','menu');menu.className='fixture_menu';menu.innerHTML='<div class="fixture_menuMaterial"></div><div role="presentation" class="fixture_menuViewport"><button role="menuitem" data-action="menu-first">第一项合成动作</button><button role="menuitem" data-action="menu-middle">第二项合成动作</button><button role="menuitem" data-action="menu-last">末项合成动作</button></div>';b.parentElement.append(menu);b.setAttribute('aria-expanded','true')}}else if(b.getAttribute('role')==='menuitem'){b.closest('[role="menu"]').remove();document.querySelector('[data-action="more"]').setAttribute('aria-expanded','false')}})`;
  return `<!doctype html><html data-dsh-app-layout="drawer" ${lite ? 'data-dsh-app-lite' : ''}><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>${base}</style><style>${theme}</style><style>${css}</style><style>${menuCss}</style><style>${adaptedCss}</style></head><body ${dark ? 'data-ds-dark-theme' : ''}><div id="root"><div data-slot="root"><div class="fixture_frame" data-sidebar-drawer data-sidebar-collapsed><div class="${c('root')}" data-phase="active"><div data-slot="conversation.header"><header class="${c('header')}"><div class="${c('headerLeading')}"><div data-slot="conversation.header.leading"></div></div><div data-slot="conversation.session.header"><div class="${c('titleRow')}"><div class="${c('titleCluster')}"><nav class="${c('crumbs')}" aria-label="会话路径"><span class="${c('crumbSeg')}"><button class="${c('crumb')}" data-action="breadcrumb">Long workspace breadcrumb 这是用于验证手机页头的长路径</button></span><span class="${c('crumbSep')}">/</span><span class="${c('crumbSeg')}"><span class="${c('crumb')} ${c('crumbCurrent')}">A long synthetic session title 中文会话</span></span></nav><div class="${c('headerActions')}"><div data-slot="conversation.session.header.actions">${status}</div></div></div><div class="${c('headerUtilities')}"><div data-slot="conversation.session.header.utilities"><div class="fixture_utilityRoot"><div class="fixture_split"><button class="fixture_icon" aria-label="工具图标" data-action="utility">${icon}</button></div></div><span class="fixture_menuRoot"><button class="fixture_icon" aria-label="更多" aria-haspopup="menu" aria-expanded="false" data-action="more">${icon}</button></span></div></div><div class="${c('headerCorner')}"><div data-slot="conversation.session.header.corner"><button class="fixture_icon" aria-label="末端操作" data-action="corner">${icon}</button></div></div></div></div></header></div></div></div></div></div><script>${fixtureScript}</script></body></html>`;
}
async function setPage(width, height, dark, lite, adaptedCss) {
  await client.command('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: true });
  await client.command('Emulation.setTouchEmulationEnabled', { enabled: true, maxTouchPoints: 1 });
  const { frameTree } = await client.command('Page.getFrameTree');
  await client.command('Page.setDocumentContent', { frameId: frameTree.frame.id, html: fixture(dark, lite, adaptedCss) });
  await paint();
}
async function measure() {
  return evaluate(`(()=>{const rect=e=>{const b=e.getBoundingClientRect();return {left:b.left,right:b.right,top:b.top,bottom:b.bottom,width:b.width,height:b.height}};const row=document.querySelector(${JSON.stringify(select('titleRow'))}),cluster=document.querySelector(${JSON.stringify(select('titleCluster'))}),crumbs=document.querySelector(${JSON.stringify(select('crumbs'))}),s=getComputedStyle(row),cs=getComputedStyle(cluster),ns=getComputedStyle(crumbs);return {row:{...rect(row),clientWidth:row.clientWidth,scrollWidth:row.scrollWidth,scrollLeft:row.scrollLeft,scrollTop:row.scrollTop,overflowX:s.overflowX,overflowY:s.overflowY,minWidth:s.minWidth,flexWrap:s.flexWrap,touchAction:s.touchAction},cluster:{...rect(cluster),clientWidth:cluster.clientWidth,scrollWidth:cluster.scrollWidth,flex:cs.flex,margin:cs.margin,padding:cs.padding,maskImage:cs.maskImage,overflowX:cs.overflowX,overflowY:cs.overflowY},crumbs:{...rect(crumbs),flex:ns.flex,overflowX:ns.overflowX},buttons:[...row.querySelectorAll('button[aria-label]')].map(e=>({action:e.dataset.action,...rect(e)})),bodyWidth:document.body.scrollWidth,documentWidth:document.documentElement.scrollWidth,bg:getComputedStyle(document.body).backgroundColor}})()`);
}
async function wheel(delta) {
  const start = await measure();
  await client.command('Input.dispatchMouseEvent', { type: 'mouseWheel', x: start.row.left + 12, y: start.row.top + start.row.height / 2, deltaX: delta, deltaY: 0 });
  return evaluate(`new Promise(resolve=>{const e=document.querySelector(${JSON.stringify(select('titleRow'))}),start=performance.now();let last=e.scrollLeft,stable=0;function tick(){const now=e.scrollLeft;stable=Math.abs(now-last)<.5?stable+1:0;last=now;if(stable>=5&&performance.now()-start>150||performance.now()-start>1200){resolve(now);return}requestAnimationFrame(tick)}tick()})`);
}
async function capture(name) {
  const shot = await client.command('Page.captureScreenshot', { format: 'png', captureBeyondViewport: false });
  fs.writeFileSync(path.join(output, `${name}.png`), Buffer.from(shot.data, 'base64'));
}
async function checkBefore(width, height, dark) {
  await setPage(width, height, dark, true, beforeCss);
  const initial = await measure();
  const afterInput = await wheel(1200);
  assert.equal(afterInput, 0, 'Old title row unexpectedly responds to horizontal input');
  assert.equal(initial.row.overflowX, 'visible', 'Old control must reproduce the visible overflow row');
  assert.equal(initial.cluster.overflowX, 'clip', 'Old control must reproduce clipping in the title cluster');
  const naturalCrumbWidth = await evaluate(`(()=>{const source=document.querySelector(${JSON.stringify(select('crumbs'))}),clone=source.cloneNode(true);clone.style.cssText='position:fixed;visibility:hidden;width:max-content;flex:none;overflow:visible';source.parentElement.append(clone);const width=clone.getBoundingClientRect().width;clone.remove();return width})()`);
  assert(initial.crumbs.width < naturalCrumbWidth - 1 || initial.cluster.scrollWidth > initial.cluster.clientWidth + 1, `Old header fixture must demonstrate clipped content: ${JSON.stringify({ initial, naturalCrumbWidth })}`);
  const name = `before-${width}x${height}-${dark ? 'dark' : 'light'}`;
  await capture(name);
  results.push({ name, expectedRegression: 'Horizontal input leaves scrollLeft=0 while header content is clipped', input: { type: 'mouseWheel', deltaX: 1200, before: initial.row.scrollLeft, after: afterInput }, ...initial });
}
async function clickVisibleActions(visited) {
  const visible = await evaluate(`(()=>{const row=document.querySelector(${JSON.stringify(select('titleRow'))}).getBoundingClientRect();return [...document.querySelectorAll('button[data-action]')].filter(e=>{const r=e.getBoundingClientRect();return r.left>=row.left-.5&&r.right<=row.right+.5}).map(e=>{const r=e.getBoundingClientRect();return {action:e.dataset.action,x:(r.left+r.right)/2,y:(r.top+r.bottom)/2,hit:document.elementFromPoint((r.left+r.right)/2,(r.top+r.bottom)/2)?.closest('button')===e}})})()`);
  for (const button of visible) {
    assert(button.hit, `${button.action} is horizontally visible but fails hit testing`);
    if (visited.has(button.action)) continue;
    await client.command('Input.dispatchMouseEvent', { type: 'mousePressed', x: button.x, y: button.y, button: 'left', clickCount: 1 });
    await client.command('Input.dispatchMouseEvent', { type: 'mouseReleased', x: button.x, y: button.y, button: 'left', clickCount: 1 });
    visited.add(button.action);
  }
}
async function checkAfter(width, height, dark) {
  await setPage(width, height, dark, true, adaptation);
  const initial = await measure();
  assert(['auto', 'scroll'].includes(initial.row.overflowX), `Title row must accept horizontal input: ${JSON.stringify(initial.row)}`);
  assert.equal(initial.row.overflowY, 'hidden');
  assert.equal(initial.row.flexWrap, 'nowrap');
  assert.equal(initial.row.touchAction, 'pan-x');
  assert.equal(initial.cluster.overflowX, 'visible');
  assert.equal(initial.cluster.maskImage, 'none');
  assert.equal(initial.cluster.margin, '0px');
  assert.equal(initial.cluster.padding, '0px');
  assert.equal(initial.crumbs.overflowX, 'visible');
  assert(initial.row.scrollWidth > initial.row.clientWidth + 1, 'Long breadcrumb/status fixture must overflow even in landscape');
  assert(initial.bodyWidth <= width + 1 && initial.documentWidth <= width + 1, `Body must fit ${width}px: ${JSON.stringify(initial)}`);
  for (const button of initial.buttons) {
    assert(button.width >= 39.5 && button.height >= 39.5, `Touch target smaller than 40px: ${JSON.stringify(button)}`);
    assert(button.top >= initial.row.top - .5 && button.bottom <= initial.row.bottom + .5, `Vertically clipped button: ${JSON.stringify(button)} row=${JSON.stringify(initial.row)}`);
  }
  const visited = new Set();
  await clickVisibleActions(visited);
  let offset = initial.row.scrollLeft;
  let events = 0;
  while (offset < initial.row.scrollWidth - initial.row.clientWidth - 1 && events < 20) {
    const next = await wheel(Math.max(80, initial.row.clientWidth / 2));
    assert(next > offset + 1, `Horizontal input stalled at ${offset}`);
    offset = next;
    events++;
    await clickVisibleActions(visited);
  }
  const end = await measure();
  const last = end.buttons.find(b => b.action === 'corner');
  assert(end.row.scrollWidth - end.row.clientWidth - end.row.scrollLeft <= 1, 'Last action must be reachable by horizontal input');
  assert(last.left >= end.row.left - .5 && last.right <= end.row.right + .5, `Last action clipped at scroll end: ${JSON.stringify(last)}`);
  assert.equal(end.row.scrollTop, 0, 'Horizontal input must not move the row vertically');
  for (const action of ['status-0', 'status-1', 'status-2', 'utility', 'more', 'corner']) assert(visited.has(action), `Action was never clickable while scrolling: ${action}`);
  const clicks = await evaluate('window.fixtureClicks');
  for (const action of visited) assert(clicks.includes(action), `Real pointer click did not dispatch: ${action}`);
  assert(end.bodyWidth <= width + 1 && end.documentWidth <= width + 1, 'Horizontal scrolling must not widen the document');
  const name = `after-${width}x${height}-${dark ? 'dark' : 'light'}`;
  await capture(name);
  results.push({ name, initial, end, input: { type: 'mouseWheel', wheelEvents: events, scrollLeft: offset, clickedActions: [...visited] } });
}
async function checkFull(width, height, dark) {
  await setPage(width, height, dark, false, beforeCss || adaptation);
  const control = await measure();
  await setPage(width, height, dark, false, adaptation);
  const current = await measure();
  assert.deepEqual(current, control, 'Non-Lite full variant header geometry/style changed');
  assert.equal(current.row.overflowX, 'visible', 'Full variant must preserve the upstream row behavior');
  assert.equal(current.cluster.overflowX, 'clip', 'Full variant must preserve upstream title clipping');
  results.push({ name: `full-unaffected-${width}x${height}-${dark ? 'dark' : 'light'}`, unchanged: true, geometry: current });
}
async function clickAction(action) {
  const point = await evaluate(`(()=>{const e=document.querySelector('[data-action="'+${JSON.stringify(action)}+'"]');if(!e)throw Error('Missing fixture action');const r=e.getBoundingClientRect(),x=r.left+r.width/2,y=r.top+r.height/2;return {x,y,hit:document.elementFromPoint(x,y)?.closest('[data-action]')===e}})()`);
  assert(point.hit, `Synthetic action is obscured: ${action}`);
  for (const type of ['mousePressed', 'mouseReleased']) await client.command('Input.dispatchMouseEvent', { type, x: point.x, y: point.y, button: 'left', clickCount: 1 });
  await paint();
}
async function menuProbe() {
  return evaluate(`(()=>{const e=document.querySelector('[role="menu"]');if(!e)return null;const rect=e=>{const r=e.getBoundingClientRect();return {left:r.left,right:r.right,top:r.top,bottom:r.bottom,width:r.width,height:r.height}},r=rect(e),s=getComputedStyle(e);return {...r,position:s.position,marked:e.hasAttribute('data-dsh-app-header-menu'),centerHit:e.contains(document.elementFromPoint(r.left+r.width/2,r.top+r.height/2)),anchor:rect(e.parentElement),items:[...e.querySelectorAll('[role="menuitem"]')].map(b=>{const r=rect(b);return {action:b.dataset.action,...r,hit:b.contains(document.elementFromPoint(r.left+r.width/2,r.top+r.height/2))}}),bodyWidth:document.body.scrollWidth,rowLeft:document.querySelector(${JSON.stringify(select('titleRow'))}).scrollLeft}})()`);
}
function assertMenuVisible(menu, width, height) {
  assert(menu && menu.marked && menu.position === 'fixed', `Menu must be positioned by the production script: ${JSON.stringify(menu)}`);
  assert(menu.centerHit && menu.items.every(item => item.hit), `Menu center and all item centers must receive input: ${JSON.stringify(menu)}`);
  assert(menu.left >= 7.5 && menu.right <= width - 7.5 && menu.top >= 47.5 && menu.bottom <= height - 31.5, `Menu must fit the viewport and safe insets: ${JSON.stringify(menu)}`);
  const expectedLeft = Math.max(8, Math.min(menu.anchor.right - menu.width, width - menu.width - 8));
  assert(Math.abs(menu.left - expectedLeft) <= 1 && Math.abs(menu.top - menu.anchor.bottom - 4) <= 1, `Menu lost its trigger anchor: ${JSON.stringify(menu)}`);
  assert(menu.bodyWidth <= width + 1, 'Opening a menu must not widen the document');
}
async function checkMenus(width, height, dark) {
  const suffix = `${width}x${height}-${dark ? 'dark' : 'light'}`;
  if (beforeMenuCss) {
    await setPage(width, height, dark, true, beforeMenuCss);
    await evaluate('window.fixtureMenusEnabled=true');
    await wheel(1200);
    await clickAction('more');
    const before = await menuProbe();
    assert(before && !before.centerHit, `Menu control must reproduce clipping by the horizontal row: ${JSON.stringify(before)}`);
    await capture(`menu-before-${suffix}`);
    results.push({ name: `menu-before-${suffix}`, expectedRegression: 'Menu exists below the header but is excluded by the row clip', menu: before });
  }
  await setPage(width, height, dark, true, adaptation);
  await evaluate(headerScript);
  await evaluate('window.fixtureMenusEnabled=true');
  await wheel(1200);
  await clickAction('more');
  const opened = await menuProbe();
  assertMenuVisible(opened, width, height);
  await clickAction('menu-first');
  assert.equal(await menuProbe(), null, 'The existing first-item action must dismiss the menu');
  await clickAction('more');
  const beforeScroll = await menuProbe();
  const scrolledLeft = await wheel(-40);
  await paint();
  const followed = await menuProbe();
  assertMenuVisible(followed, width, height);
  assert(scrolledLeft < beforeScroll.rowLeft - 1 && Math.abs(followed.anchor.right - beforeScroll.anchor.right) > 1, 'Open-menu fixture must exercise a real row scroll');
  await capture(`menu-after-${suffix}`);
  await clickAction('menu-last');
  assert.equal(await menuProbe(), null, 'The existing last-item action must dismiss the menu');
  const resumedLeft = await wheel(-80);
  assert(resumedLeft < scrolledLeft - 1, 'Closing a menu must leave horizontal input working');
  const clicks = await evaluate('window.fixtureClicks');
  assert(clicks.includes('menu-first') && clicks.includes('menu-last'), 'Both edge menu items must receive real pointer clicks');
  results.push({ name: `menu-after-${suffix}`, opened, followed, input: { type: 'mouseWheel and pointer', clickedItems: ['menu-first', 'menu-last'], openMenuScrollLeft: scrolledLeft, afterDismissScrollLeft: resumedLeft } });
}
// Dock base geometry is reconstructed from header-independent runtime evidence
// in .harness-tmp-device/dock-structure.json, not extracted dock library CSS.
function dockFixture(dark, adaptedCss) {
  const base = `html,body{margin:0;height:100%;font:14px 'Segoe UI','Microsoft YaHei',sans-serif}body{background:var(--dsw-alias-bg-base);color:var(--dsw-alias-label-primary)}:root{--dsh-app-lead:0px}.fixture_rightbarCol{padding-top:40px;width:100%;box-sizing:border-box}.fixture_tabStrip{height:28px;padding:10px 6px 0 0;display:flex;align-items:center;gap:4px;border-bottom:1px solid var(--dsw-alias-border-l3)}.fixture_stripTabs{height:28px;display:flex;align-items:center;flex:none;min-width:0;overflow:auto}.fixture_tab{position:relative;display:flex;align-items:center;flex:none;height:28px;min-width:80px;padding:0 10px;font-size:13px;line-height:13px;background:var(--dsw-alias-interactive-bg-hover)}.fixture_tabTitle{display:flex;align-items:center;flex:1 1 auto;min-width:0;white-space:nowrap;overflow:hidden;line-height:18.2px}.fixture_tabClose{position:absolute;top:4px;right:4px}.fixture_tabStrip button{display:flex;align-items:center;justify-content:center;flex:none;width:22px;height:22px;padding:0;border:0;background:transparent;color:inherit}.fixture_stripFill{flex:1;min-width:0}.fixture_stripChrome{display:flex;align-items:center;height:28px;gap:8px}`;
  return `<!doctype html><html data-dsh-app-lite data-dsh-app-layout="drawer"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>${base}</style><style>${theme}</style><style>${adaptedCss}</style></head><body ${dark ? 'data-ds-dark-theme' : ''}><div class="fixture_rightbarCol" data-sidebar-right-panel="fullscreen"><div class="fixture_tabStrip" data-dockkit-strip role="tablist"><div class="fixture_stripTabs" role="presentation"><div class="fixture_tab" role="tab" data-dockkit-tab="fixture-browser" aria-selected="true"><span class="fixture_tabTitle">浏览器</span><button class="fixture_tabClose" data-action="dock-close" aria-label="关闭浏览器"><svg viewBox="0 0 16 16" width="14" height="14" aria-hidden="true"><path d="m4 4 8 8m0-8-8 8" stroke="currentColor"/></svg></button></div></div><button class="fixture_addTab" aria-label="添加标签">+</button><div class="fixture_stripFill"></div><span><button class="fixture_iconButton" aria-label="标签列表">≡</button></span><div class="fixture_stripChrome"><button class="fixture_iconButton" aria-label="面板尺寸">□</button><button class="fixture_iconButton" aria-label="关闭面板">×</button></div></div></div><script>window.fixtureClosed=false;document.querySelector('[data-action="dock-close"]').addEventListener('click',e=>{window.fixtureClosed=true;e.currentTarget.closest('[role="tab"]').remove()})</script></body></html>`;
}
async function setDockPage(width, height, dark, adaptedCss) {
  await client.command('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: true });
  const { frameTree } = await client.command('Page.getFrameTree');
  await client.command('Page.setDocumentContent', { frameId: frameTree.frame.id, html: dockFixture(dark, adaptedCss) });
  await paint();
}
async function dockProbe() {
  return evaluate(`(()=>{const rect=e=>{const r=e.getBoundingClientRect();return {left:r.left,right:r.right,top:r.top,bottom:r.bottom,width:r.width,height:r.height,centerY:r.top+r.height/2}},strip=document.querySelector('[data-dockkit-strip]'),tab=strip.querySelector('[data-dockkit-tab]'),close=tab.querySelector('button'),title=tab.querySelector('[class*="_tabTitle"]'),c=rect(close),range=document.createRange();range.selectNodeContents(title);return {strip:rect(strip),tab:rect(tab),close:c,title:rect(title),text:rect({getBoundingClientRect:()=>range.getBoundingClientRect()}),icon:rect(close.querySelector('svg')),centerHit:close.contains(document.elementFromPoint(c.left+c.width/2,c.centerY)),buttons:[...strip.querySelectorAll('button')].map(rect),bodyWidth:document.body.scrollWidth}})()`);
}
async function checkDock(width, height, dark) {
  const suffix = `${width}x${height}-${dark ? 'dark' : 'light'}`;
  if (beforeDockCss) {
    await setDockPage(width, height, dark, beforeDockCss);
    const before = await dockProbe();
    assert(Math.abs(before.close.centerY - before.tab.centerY) >= 9.5 && before.close.bottom > before.tab.bottom + 1, `Dock baseline must reproduce close-button displacement: ${JSON.stringify(before)}`);
    await capture(`dock-before-${suffix}`);
    results.push({ name: `dock-before-${suffix}`, fixtureSource: 'synthetic geometry from captured runtime dock-structure.json', expectedRegression: 'Enlarged close button is 10px below the 28px tab center', geometry: before });
  }
  await setDockPage(width, height, dark, adaptation);
  const after = await dockProbe();
  assert(Math.abs(after.close.centerY - after.tab.centerY) <= .5 && Math.abs(after.icon.centerY - after.title.centerY) <= .5, `Close icon and title must have the same vertical center: ${JSON.stringify(after)}`);
  assert(after.title.right <= after.close.left + .5 && after.text.right <= after.close.left + .5, `Browser title overlaps the close control: ${JSON.stringify(after)}`);
  assert(after.close.width >= 39.5 && after.close.height >= 39.5 && after.centerHit, `Close target must remain 40px and clickable: ${JSON.stringify(after)}`);
  assert(after.buttons.every(b => b.top >= after.strip.top - .5 && b.bottom <= after.strip.bottom + .5), `Panel controls must fit vertically in the strip: ${JSON.stringify(after)}`);
  assert(after.bodyWidth <= width + 1, 'Dock adaptation must fit the viewport');
  await capture(`dock-after-${suffix}`);
  await clickAction('dock-close');
  assert(await evaluate('window.fixtureClosed && !document.querySelector("[data-dockkit-tab]")'), 'Synthetic browser tab must close through a real pointer click');
  results.push({ name: `dock-after-${suffix}`, fixtureSource: 'synthetic geometry from captured runtime dock-structure.json', geometry: after, input: { type: 'pointer', action: 'synthetic dock-close', closed: true } });
}
// Contract reconstructed from the installed dsh-github-gate client artifact:
// .harness-tmp-rc2/r13-github-header-client.js:64-85,117-136,406-451.
// Its style element is a sibling of an unlabelled span/button inside .ghk-root.
// Unlike the old fixture_utilityRoot, that wrapper has no upstream flex display.
const branchCss = `.ghk-pill{display:inline-flex;align-items:center;gap:4px;height:24px;padding:0 6px;border:1px solid var(--dsw-alias-border-l1);border-radius:6px;background:var(--dsw-alias-bg-layer-1);color:var(--dsw-alias-label-secondary);font-size:12px;line-height:1;font-family:inherit;white-space:nowrap;max-width:220px;overflow:hidden;text-overflow:ellipsis;user-select:none}.ghk-pill-glyph{flex:none;opacity:.75}.ghk-pill-label{overflow:hidden;text-overflow:ellipsis}.ghk-pill-button{cursor:pointer;font:inherit}.ghk-pr{display:inline-flex;align-items:center;gap:3px;padding-left:5px;margin-left:1px;border-left:1px solid var(--dsw-alias-border-l1)}`;
const branchGlyph = '<svg class="ghk-pill-glyph" width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="4.5" cy="3.5" r="1.8"/><circle cx="4.5" cy="12.5" r="1.8"/><circle cx="11.5" cy="6" r="1.8"/><path d="M4.5 5.3v5.4"/><path d="M9.7 6.9c-.7 1.6-2.2 2.6-3.9 2.6"/></svg>';
async function addBranch(state) {
  await evaluate(`(()=>{window.fixtureBranchClicks=0;const root=document.createElement('span');root.className='ghk-root';root.innerHTML=${JSON.stringify(`<style>${branchCss}</style>`)};const pill=document.createElement(${JSON.stringify(state === 'idle' ? 'span' : 'button')});pill.className='ghk-pill'+${JSON.stringify(state === 'idle' ? '' : ' ghk-pill-button')};pill.title='Synthetic Git branch';pill.innerHTML=${JSON.stringify(branchGlyph + '<span class="ghk-pill-label">' + (state === 'idle' ? '—' : 'synthetic/very-long-branch-name-with-a-pull-request') + '</span>' + (state === 'idle' ? '' : '<span class="ghk-pr">#123</span>'))};if(pill.tagName==='BUTTON'){pill.type='button';pill.addEventListener('click',()=>{window.fixtureBranchClicks=(window.fixtureBranchClicks||0)+1})}root.append(pill);document.querySelector('[data-slot="conversation.session.header.utilities"]').prepend(root)})()`);
  await paint();
}
async function branchProbe() {
  return evaluate(`(()=>{const rect=e=>{const r=e.getBoundingClientRect();return {left:r.left,right:r.right,top:r.top,bottom:r.bottom,width:r.width,height:r.height,centerY:r.top+r.height/2}},pill=document.querySelector('.ghk-pill'),root=pill.parentElement,s=getComputedStyle(pill),row=document.querySelector(${JSON.stringify(select('titleRow'))});return {pill:{...rect(pill),tag:pill.tagName,ariaLabel:pill.getAttribute('aria-label'),display:s.display,color:s.color,background:s.backgroundColor,padding:s.padding,gap:s.gap,border:s.borderRadius},root:rect(root),icon:rect(pill.querySelector('svg')),more:rect(document.querySelector('[data-action="more"]')),corner:rect(document.querySelector('[data-action="corner"]')),row:{...rect(row),scrollLeft:row.scrollLeft},glyph:pill.querySelector('svg').outerHTML,label:pill.textContent,documentWidth:document.documentElement.scrollWidth}})()`);
}
function assertBranchAligned(probe) {
  assert(probe.pill.width >= 39.5 && probe.pill.height >= 39.5, `Branch pill must keep a 40px target: ${JSON.stringify(probe)}`);
  for (const control of [probe.more, probe.corner, probe.icon]) assert(Math.abs(control.centerY - probe.pill.centerY) <= .5, `Branch frame and glyph must share the header controls' center: ${JSON.stringify(probe)}`);
  assert(probe.pill.top >= probe.row.top - .5 && probe.pill.bottom <= probe.row.bottom + .5, 'Branch frame must fit the scroll row');
}
async function checkBranch(width, height, dark) {
  for (const state of ['idle', 'branch']) {
    const suffix = `${state}-${width}x${height}-${dark ? 'dark' : 'light'}`;
    await setPage(width, height, dark, true, beforeBranchCss || adaptation);
    await addBranch(state);
    const before = await branchProbe();
    if (beforeBranchCss) {
      assert.throws(() => assertBranchAligned(before), /Branch pill must keep|share the header controls/, 'Bad baseline must fail the same alignment/target contract');
      assert(before.more.centerY - before.pill.centerY >= 2, `Bad baseline must reproduce upward displacement: ${JSON.stringify(before)}`);
      await wheel(1200);
      await capture(`branch-before-${suffix}`);
    }
    await setPage(width, height, dark, true, adaptation);
    await addBranch(state);
    const initial = await branchProbe();
    assertBranchAligned(initial);
    assert.equal(initial.pill.tag, state === 'idle' ? 'SPAN' : 'BUTTON', 'Keep the plugin read-only versus interactive semantics');
    assert.equal(initial.pill.ariaLabel, null, 'Fixture must cover controls missed by aria-label touch selectors');
    for (const key of ['glyph', 'label']) assert.equal(initial[key], before[key], `Keep original branch ${key}`);
    for (const key of ['color', 'background', 'padding', 'gap', 'border']) assert.equal(initial.pill[key], before.pill[key], `Keep plugin appearance: ${key}`);
    await evaluate(headerScript);
    await evaluate('window.fixtureMenusEnabled=true');
    await wheel(1200);
    const scrolled = await branchProbe();
    assertBranchAligned(scrolled);
    assert(scrolled.row.scrollLeft > 0 && scrolled.documentWidth <= width + 1, 'Branch remains in a horizontally scrollable, viewport-contained row');
    if (state === 'branch') {
      await evaluate(`document.querySelector('.ghk-pill').scrollIntoView({block:'nearest',inline:'center'})`);
      await paint();
      const point = await evaluate(`(()=>{const e=document.querySelector('.ghk-pill'),r=e.getBoundingClientRect();return {x:r.left+r.width/2,y:r.top+r.height/2,hit:e.contains(document.elementFromPoint(r.left+r.width/2,r.top+r.height/2))}})()`);
      assert(point.hit, 'Branch button must receive pointer input');
      for (const type of ['mousePressed', 'mouseReleased']) await client.command('Input.dispatchMouseEvent', { type, x: point.x, y: point.y, button: 'left', clickCount: 1 });
      assert.equal(await evaluate('window.fixtureBranchClicks'), 1, 'Existing synthetic branch handler must dispatch once');
      await wheel(1200);
    }
    await clickAction('more');
    assertMenuVisible(await menuProbe(), width, height);
    assertBranchAligned(await branchProbe());
    await capture(`branch-after-${suffix}`);
    await clickAction('menu-first');
    assert.equal(await menuProbe(), null, 'Existing menu action must still dismiss');
    await setPage(width, height, dark, false, beforeBranchCss || adaptation);
    await addBranch(state);
    const fullBefore = await branchProbe();
    await setPage(width, height, dark, false, adaptation);
    await addBranch(state);
    assert.deepEqual(await branchProbe(), fullBefore, 'Non-Lite plugin frame, glyph and appearance must remain unchanged');
    results.push({ name: `branch-${suffix}`, kind: 'installed third-party wrapper contract with synthetic branch data and pointer action; not a Host branch switch', badBaselineFailed: Boolean(beforeBranchCss), fullUnchanged: true, before, initial, scrolled });
  }
}
let failure;
try {
  for (let i = 0; i < 100 && !(await canConnect()); i++) {
    if (launchError) throw launchError;
    if (edge.exitCode !== null) throw Error(`Owned Edge exited during launch: ${edge.exitCode}`);
    await delay(100);
  }
  assert(await canConnect(), 'Owned Edge failed to expose CDP');
  const version = await fetch(`${endpoint}/json/version`).then(r => r.json());
  browserClient = await connect(version.webSocketDebuggerUrl);
  const targets = await fetch(`${endpoint}/json`).then(r => r.json());
  const target = targets.find(t => t.type === 'page' && t.url === 'about:blank');
  assert(target, 'Owned Edge blank target is missing');
  client = await connect(target.webSocketDebuggerUrl);
  await client.command('Page.enable');
  for (const [width, height] of [[320, 640], [363, 800], [800, 363]]) {
    for (const dark of [false, true]) {
      if (branchOnly) { await checkBranch(width, height, dark); continue; }
      if (dockOnly) { await checkDock(width, height, dark); continue; }
      if (!menuOnly) {
        if (beforeCss) await checkBefore(width, height, dark);
        if (!beforeOnly) await checkAfter(width, height, dark);
        await checkFull(width, height, dark);
      }
      if (!beforeOnly) await checkMenus(width, height, dark);
      if (!beforeOnly && !menuOnly) await checkBranch(width, height, dark);
    }
  }
} catch (error) { failure = error; }
finally {
  client?.ws.close();
  if (browserClient) {
    try { await browserClient.command('Browser.close'); } catch { /* Closing the owned browser also closes CDP. */ }
    browserClient.ws.close();
  }
  for (let i = 0; i < 30 && await canConnect(); i++) await delay(100);
  if (await canConnect()) { try { edge.kill(); } catch {} await delay(300); }
  closed = !(await canConnect());
  const report = { bundle, extractedHeaderPrefix: prefix, adaptation: path.resolve('app/assets/web/dsh_web_phone.css'), headerScript: path.resolve('app/assets/web/dsh_web_header.js'), beforeCss: beforePath && path.resolve(beforePath), beforeMenuCss: beforeMenuPath && path.resolve(beforeMenuPath), beforeBranchCss: beforeBranchPath && path.resolve(beforeBranchPath), kind: 'synthetic DOM with bundled CSS and real CDP horizontal wheel/pointer input; separate from device evidence', edge: { pid: edge.pid, port, profile, closed }, passed: results.length, results, error: failure?.stack };
  fs.writeFileSync(path.join(output, branchOnly ? 'header-branch-regression.json' : dockOnly ? 'header-dock-regression.json' : menuOnly ? 'header-menu-regression.json' : 'header-layout-regression.json'), JSON.stringify(report, null, 2));
  console.log(`${failure ? 'FAILED' : 'PASSED'} ${results.length} header scenarios; owned Edge PID ${edge.pid}; port ${port} closed=${closed}; report ${output}`);
}
if (failure) throw failure;
assert(closed, 'Owned Edge must close before the regression exits');
