// Chromium layout regression using the CSS from the exact bundled DSH build.
// Run against an owned blank CDP page, never a logged-in page. No network data,
// credentials, or real settings are needed: fixture content is synthetic.
import fs from 'node:fs';
import path from 'node:path';
import { runInNewContext } from 'node:vm';
function decodeStaticCss(literal) {
  // Official bundles use JSON strings or minified, non-interpolated templates.
  if(literal.startsWith('`')&&literal.includes('${'))throw Error('Bundled CSS must be static');
  return literal.startsWith('"') ? JSON.parse(literal) : runInNewContext(literal, Object.create(null), { timeout: 1000 });
}
const bundle=process.argv[2];
if(!bundle)throw Error('Pass the bundled dsh-client-ui-settings-general/lib/client.js path');
const port=process.env.DSH_LAYOUT_CDP_PORT||'19224';
const out=path.resolve(process.env.DSH_LAYOUT_OUTPUT||'.harness-tmp-layout');fs.mkdirSync(out,{recursive:true});
const source=fs.readFileSync(bundle,'utf8');
const css=[...source.matchAll(/\bconst\s+css(?:\$\d+)?\s*=\s*("(?:[^"\\]|\\.)*"|`(?:[^`\\]|\\.)*`)\s*;/g)].map(m=>decodeStaticCss(m[1])).join('\n');
if(!css.includes('_panel{')||!source.includes('data-shortcut-modal'))throw Error('Unexpected settings artifact');
const adaptation=fs.readFileSync('app/assets/web/dsh_web_phone.css','utf8');
const themePath=path.resolve(path.dirname(bundle),'../../dsh-client-ui-theme/lib/client.js');
const themeSource=fs.readFileSync(themePath,'utf8');
const themeMatches=[...themeSource.matchAll(/\b(?:const|let|var)\s+[\w$]+\s*=\s*("(?:[^"\\]|\\.)*"|`(?:[^`\\]|\\.)*`)\s*;/g)].filter(m=>m[1].includes('body{--dsw-static-amber-100:'));
if(themeMatches.length!==1)throw Error('Unexpected bundled theme artifact');
const themeCss=decodeStaticCss(themeMatches[0][1]);
const id=css.match(/\.([\w-]+)_panel\{/)[1];
const rowid=css.match(/\.([\w-]+)_row\{border-bottom:/)[1];
const targets=await fetch(`http://127.0.0.1:${port}/json`).then(r=>r.json());
const target=targets.find(t=>t.type==='page'&&t.url==='about:blank');
if(!target)throw Error('An owned about:blank target is required');
const ws=new WebSocket(target.webSocketDebuggerUrl);await new Promise((r,j)=>{ws.onopen=r;ws.onerror=j});
let next=0;const pending=new Map();ws.onmessage=e=>{const m=JSON.parse(e.data),p=pending.get(m.id);if(p){pending.delete(m.id);m.error?p.j(Error(m.error.message)):p.r(m.result)}};
const cmd=(method,params={})=>new Promise((r,j)=>{const id=++next;pending.set(id,{r,j});ws.send(JSON.stringify({id,method,params}))});
const evaluate=async expression=>{const r=await cmd('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(r.exceptionDetails)throw Error(`Fixture evaluation failed: ${r.exceptionDetails.exception?.description||r.exceptionDetails.text}`);return r.result.value};
const paint=()=>evaluate('new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)))');
// Dispatch input through Chromium's hit testing/compositor. Assigning scrollTop
// would also move an overflow:hidden box and miss the touch/wheel regression.
async function wheelScroll(selector,axis,delta){
 const property=axis==='y'?'scrollTop':'scrollLeft';
 const before=await evaluate(`(()=>{const e=document.querySelector(${JSON.stringify(selector)}),r=e.getBoundingClientRect();return {offset:e.${property},x:r.left+Math.min(24,r.width/2),y:r.top+r.height/2}})()`);
 await cmd('Input.dispatchMouseEvent',{type:'mouseWheel',x:before.x,y:before.y,deltaX:axis==='x'?delta:0,deltaY:axis==='y'?delta:0});
 const after=await evaluate(`new Promise(resolve=>{const e=document.querySelector(${JSON.stringify(selector)}),start=performance.now();let last=e.${property},stable=0;function check(){const current=e.${property};stable=current>${before.offset}+1&&Math.abs(current-last)<0.5?stable+1:0;last=current;if(stable>=3||performance.now()-start>1500){resolve(current);return}requestAnimationFrame(check)}check()})`);
 if(after<=before.offset+1)throw Error(`Real ${axis} wheel input did not scroll ${selector}: ${before.offset} -> ${after}`);
 return after;
}
async function scrollToLastRow(selector,lastSelector){
 const initial=await evaluate(`(()=>{const e=document.querySelector(${JSON.stringify(selector)});return {top:e.scrollTop,max:e.scrollHeight-e.clientHeight,height:e.clientHeight}})()`);
 if(initial.top!==0||initial.max<=1)throw Error(`Vertical fixture must start at the top and overflow: ${JSON.stringify(initial)}`);
 const firstScrollTop=await wheelScroll(selector,'y',Math.max(160,Math.floor(initial.height/2)));
 let endScrollTop=firstScrollTop,wheelEvents=1;
 while(endScrollTop<initial.max-1&&wheelEvents<20){endScrollTop=await wheelScroll(selector,'y',Math.max(320,initial.height));wheelEvents++}
 const end=await evaluate(`(()=>{const e=document.querySelector(${JSON.stringify(selector)}),s=e.getBoundingClientRect(),last=document.querySelector(${JSON.stringify(lastSelector)}).getBoundingClientRect();return {top:e.scrollTop,max:e.scrollHeight-e.clientHeight,viewportTop:s.top,viewportBottom:s.bottom,lastRow:{top:last.top,bottom:last.bottom}}})()`);
 if(end.max-end.top>1||end.lastRow.bottom>end.viewportBottom+1||end.lastRow.bottom<end.viewportTop)throw Error(`Last row unreachable by wheel input: ${JSON.stringify(end)}`);
 return {type:'mouseWheel',firstScrollTop,endScrollTop,maxScrollTop:end.max,wheelEvents,lastRow:end.lastRow};
}
async function checkHorizontalTabs(selector){
 const nav=await evaluate(`(()=>{const e=document.querySelector(${JSON.stringify(selector)}),s=getComputedStyle(e),r=e.getBoundingClientRect();return {direction:s.flexDirection,wrap:s.flexWrap,overflowX:s.overflowX,overflowY:s.overflowY,scrollWidth:e.scrollWidth,clientWidth:e.clientWidth,top:e.scrollTop,tabs:[...e.children].map(x=>{const b=x.getBoundingClientRect();return {top:b.top,bottom:b.bottom,left:b.left,right:b.right}}),left:r.left,right:r.right}})()`);
 if(nav.direction!=='row'||nav.wrap!=='nowrap'||!['auto','scroll'].includes(nav.overflowX)||nav.overflowY!=='hidden'||nav.tabs.some(t=>Math.abs(t.top-nav.tabs[0].top)>1))throw Error(`Settings tabs must remain horizontal: ${JSON.stringify(nav)}`);
 if(nav.scrollWidth>nav.clientWidth+1){
  nav.wheelScrollLeft=await wheelScroll(selector,'x',nav.scrollWidth);
  const end=await evaluate(`(()=>{const e=document.querySelector(${JSON.stringify(selector)}),r=e.getBoundingClientRect(),last=e.lastElementChild.getBoundingClientRect();return {left:e.scrollLeft,max:e.scrollWidth-e.clientWidth,lastRight:last.right,right:r.right,top:e.scrollTop}})()`);
  if(end.max-end.left>1||end.lastRight>end.right+1||end.top!==0)throw Error(`Last tab unreachable horizontally: ${JSON.stringify(end)}`);
 }else if(nav.tabs.at(-1).right>nav.right+1)throw Error('Settings tabs clipped without horizontal scrolling');
 return nav;
}
function page(dark,purge=false,lite=true){
 const c=dark?{bg:'#151517',card:'#2c2c2e',ink:'#f9fafb',muted:'#cfd3d6',edge:'#ffffff1f',hover:'#43454a'}:{bg:'#f7f8fa',card:'#fff',ink:'#0f1115',muted:'#61666b',edge:'#0000001a',hover:'#ebeef2'};
 const base=`*{box-sizing:border-box}html,body{margin:0;height:100%;font-family:'Microsoft YaHei','Segoe UI',sans-serif;font-size:14px;background:${c.bg};color:${c.ink}}:root{--dsw-alias-bg-layer-2:${c.card};--dsw-alias-label-primary:${c.ink};--dsw-alias-label-secondary:${c.muted};--dsw-alias-border-l2:${c.edge};--dsw-specific-sidebar-nav-item-active:${c.hover};--dsw-radius-md:12px;--dsw-radius-panel:16px;--dsh-app-safe-top:40px;--dsh-app-safe-bottom:24px;--dsh-app-inset-top:96px;--dsh-app-inset-bottom:72px}button,select{font:inherit;color:inherit;border:1px solid ${c.edge};background:${c.card};border-radius:10px;padding:6px 10px}label{display:flex;gap:8px;align-items:center}h2{font-size:22px;margin:0 0 16px}.dshpp-welcome-mask{position:fixed;inset:0;display:grid;place-items:center;overflow:auto;padding:24px;background:#0004}.dshpp-welcome-card{background:${c.card};width:min(600px,100%);padding:24px;border-radius:16px;max-height:calc(100vh - 48px);overflow:auto}.dshpp-welcome-lead,.dshpp-welcome-warn{margin-bottom:16px}.dshpp-welcome-legal{line-height:1.7}.dshpp-welcome-checks{padding:12px 0}.dshpp-welcome-ops{display:flex;justify-content:flex-end;gap:8px}.dshpp-welcome-ops button{background:${c.ink};color:${c.card};min-height:40px}`;
 const rows=[['权限','选择新会话的默认权限模式','工作区内修改'],['语言','','中文'],['外观','','跟随系统'],['字号大小','仅影响会话内容的字号','14 px'],['工作步骤展示','选择希望看到多少工具调用详情','详细'],['工作步骤收起时机','选择何时自动收起工作步骤','回答结束后'],['测试长页','这是合成测试内容，不是个人配置','默认']];
 const row=([title,desc,value])=>`<div data-slot="settings.general.item"><div class="${rowid}_row"><div><div class="${rowid}_title">${title}</div><div class="${rowid}_description">${desc}</div></div><select aria-label="${title}"><option>${value}</option></select></div></div>`;
 const settings=`<div class="${id}_overlay" role="presentation"><div class="${id}_mask"></div><div class="${id}_panel" role="dialog" aria-modal="true" data-shortcut-modal="settings"><div class="${id}_navTitle">设置</div><nav class="${id}_nav"><div class="${id}_navList">${['通用设置','模型','内置插件','会话日志','其他插件'].map((s,i)=>`<button class="${id}_navCell ${i===0?id+'_active':''}">${s}</button>`).join('')}</div></nav><div class="${id}_header"><div class="${id}_actions"><button>打开配置文件</button><button class="${id}_close" aria-label="关闭">×</button></div></div><div class="${id}_options"><div data-slot="settings.section"><div class="fixture_section">${rows.map(row).join('')}</div></div></div></div>`;
 const welcome=`<div class="dshpp-welcome-mask" role="dialog" aria-modal="true"><div class="dshpp-welcome-card"><h2>用户须知</h2><div class="dshpp-welcome-lead">首次打开，请阅读以下说明。</div><div class="dshpp-welcome-warn">这是布局测试用文本。</div><div class="dshpp-welcome-legal">${'<p>较长的说明应在正文区域滚动，底部勾选和确认保持可见。</p>'.repeat(12)}</div><div class="dshpp-welcome-checks"><label><input type="checkbox">我已阅读并理解</label></div><div class="dshpp-welcome-ops"><button disabled>我已知晓并继续</button></div></div></div>`;
 return `<!doctype html><html data-dsh-app-layout="drawer" ${lite?'data-dsh-app-lite':''}><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><style>${base}</style><style>${themeCss}</style><style>${css}</style><style>${adaptation}</style><body ${dark?'data-ds-dark-theme':''}><div data-slot="root"><div class="fixture_frame" data-sidebar-drawer data-sidebar-collapsed></div></div>${purge?welcome:settings}</body></html>`;
}
const results=[];
try{
 for(const [width,height,dark,purge] of [[363,800,false,false],[363,800,true,false],[800,363,false,false],[320,640,false,false],[363,800,false,true],[363,800,true,true],[800,363,false,true]]){
  const name=`${purge?'dialog':'web-settings'}-${width}x${height}-${dark?'dark':'light'}`;
  await cmd('Emulation.setDeviceMetricsOverride',{width,height,deviceScaleFactor:1,mobile:true});
  const {frameTree}=await cmd('Page.getFrameTree');await cmd('Page.setDocumentContent',{frameId:frameTree.frame.id,html:page(dark,purge)});
  await paint();
  // Seven rows may fit when extracted artifact CSS has compact rows. Repeat
  // synthetic content until real input has a meaningful distance to scroll.
  const repeatedRows=purge?0:await evaluate(`(()=>{const s=document.querySelector('.${id}_options'),section=s.querySelector('.fixture_section'),original=[...section.children];let added=0;while(s.scrollHeight-s.clientHeight<Math.max(160,s.clientHeight/2)&&added<100){section.append(original[added%original.length].cloneNode(true));added++}return added})()`);
  await paint();
  const r=await evaluate(`(()=>{const r=e=>{const x=e.getBoundingClientRect();return {top:x.top,bottom:x.bottom,left:x.left,right:x.right,w:x.width,h:x.height}};const p=document.querySelector('${purge?'.dshpp-welcome-card':'[data-shortcut-modal="settings"]'}');const scroll=document.querySelector('${purge?'.dshpp-welcome-legal':'.'+id+'_options'}');const action=document.querySelector('${purge?'.dshpp-welcome-ops button':'.'+id+'_close'}');const s=getComputedStyle(scroll);return {panel:r(p),action:r(action),scroll:{...r(scroll),scrollHeight:scroll.scrollHeight,clientHeight:scroll.clientHeight,overflowX:s.overflowX,overflowY:s.overflowY},disabled:action.disabled,checkbox:document.querySelector('.dshpp-welcome-checks input')?.checked,bodyWidth:document.body.scrollWidth}})()`);
  if(r.panel.top<39||r.panel.bottom>height-23||r.panel.left<0||r.panel.right>width+1||r.bodyWidth>width+1)throw Error(`Fixture panel overflow ${name}: ${JSON.stringify(r)}`);
  if(r.action.top<40||r.action.bottom>height-24)throw Error(`Action obscured ${name}: ${JSON.stringify(r)}`);
  if(purge&&(!r.disabled||r.checkbox!==false||r.scroll.scrollHeight<=r.scroll.clientHeight))throw Error(`Welcome checkbox, disabled confirmation, or text scrolling changed ${name}`);
  if(!purge){
   r.coverage=await evaluate(`(()=>{const p=document.querySelector('[data-shortcut-modal="settings"]'),o=p.parentElement,s=getComputedStyle(o),b=o.getBoundingClientRect();return {background:s.backgroundColor,panelBackground:getComputedStyle(p).backgroundColor,top:b.top,bottom:b.bottom,corners:[[2,2],[innerWidth-2,2],[2,innerHeight-2],[innerWidth-2,innerHeight-2]].map(([x,y])=>document.elementFromPoint(x,y)===o)}})()`);
    if(r.coverage.top!==0||Math.abs(r.coverage.bottom-height)>1||r.coverage.background!==r.coverage.panelBackground||r.coverage.corners.some(v=>!v))throw Error(`Settings leaks underlying colors at screen corners ${name}: ${JSON.stringify(r.coverage)}`);
    if(!['auto','scroll'].includes(r.scroll.overflowY))throw Error(`Settings options must allow vertical input scrolling ${name}: overflowY=${r.scroll.overflowY}`);
   r.repeatedRows=repeatedRows;
   r.verticalInput=await scrollToLastRow('.'+id+'_options','.fixture_section > :last-child');
   r.tabs=await checkHorizontalTabs('.'+id+'_navList');
  }
  const shot=await cmd('Page.captureScreenshot',{format:'png',captureBeyondViewport:false});fs.writeFileSync(path.join(out,name+'.png'),Buffer.from(shot.data,'base64'));
  results.push({name,...r});
 }
 fs.writeFileSync(path.join(out,'layout-regression.json'),JSON.stringify({source:bundle,kind:'synthetic DOM with extracted bundled CSS and CDP wheel input; not device evidence',results},null,2));
 console.log(`Passed ${results.length} Chromium layout/input scenarios; screenshots in ${out}`);
}finally{await cmd('Page.navigate',{url:'about:blank'});ws.close()}
