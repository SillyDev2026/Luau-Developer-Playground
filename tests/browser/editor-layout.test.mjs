import test, { before, after } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
const { chromium } = createRequire(import.meta.url)('playwright');

let server, browser, base;
before(async()=>{
  server=createServer(async(req,res)=>{
    if(req.url==='/fixture'){
      res.setHeader('Content-Type','text/html');
      res.end('<meta name="viewport" content="width=device-width, initial-scale=1"><link rel="stylesheet" href="/src/v1.css"><div class="editor-stage" style="width:320px;height:160px"><div class="line-gutter" id="gutter"></div><div class="code-stack"><div class="highlight-scroll"><pre id="highlight"></pre></div><textarea id="code-input"></textarea></div></div>');
      return;
    }
    if(!/^\/src\/[\w.-]+\.(js|css)$/.test(req.url)){res.writeHead(404).end();return;}
    try{
      const text=await readFile(new URL('../..'+req.url,import.meta.url));
      res.setHeader('Content-Type',req.url.endsWith('.js')?'text/javascript':'text/css');
      res.end(text);
    }catch{res.writeHead(404).end();}
  });
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  base=`http://127.0.0.1:${server.address().port}`;
  browser=await chromium.launch({headless:true,...(process.env.CHROMIUM_PATH?{executablePath:process.env.CHROMIUM_PATH}:{})});
});
after(async()=>{await browser?.close();await new Promise(resolve=>server?server.close(resolve):resolve());});

async function fixture(mobile=false){
  const page=await browser.newPage({viewport:{width:mobile?412:1280,height:915},isMobile:mobile,hasTouch:mobile});
  await page.goto(base+'/fixture');
  await page.evaluate(async()=>{
    const {CodeEditor}=await import('/src/v1-editor.js');
    const input=document.querySelector('textarea'),highlight=document.querySelector('#highlight'),gutter=document.querySelector('#gutter');
    window.editor=new CodeEditor({input,highlight,gutter,onChange(){},onCursor(){},onShortcut(){}});
    input.wrap='soft';
    for(const node of [input,highlight]){node.style.whiteSpace='pre-wrap';node.style.overflowWrap='anywhere';}
  });
  return page;
}

for(const mobile of [false,true])test(`Go to line reveals wrapped target (${mobile?'phone':'desktop'})`,async()=>{
  const page=await fixture(mobile);
  try{
    const result=await page.evaluate(async()=>{
      const {input,gutter}=editor;
      input.value=Array.from({length:40},(_,i)=>`local value${i} = "${'long '.repeat(20)}"`).join('\n');
      editor.render();await new Promise(requestAnimationFrame);
      editor.selectLine(35);await new Promise(requestAnimationFrame);
      const row=gutter.children[34].getBoundingClientRect(),view=input.getBoundingClientRect();
      return {line:editor.position.line,top:row.top-view.top,height:input.clientHeight,lineHeight:parseFloat(getComputedStyle(input).lineHeight)};
    });
    assert.equal(result.line,35);
    assert.ok(result.top>=0&&result.top+result.lineHeight<=result.height,JSON.stringify(result));
  }finally{await page.close();}
});

test('highlight and gutter wrap at the same width as a textarea with a scrollbar',async()=>{
  const page=await fixture();
  try{
    const result=await page.evaluate(async()=>{
      const {input,highlight,gutter}=editor;
      input.style.scrollbarGutter='stable';
      input.value=Array.from({length:35},()=> 'x'.repeat(29)).join('\n');
      editor.render();await new Promise(requestAnimationFrame);
      const range=document.createRange();range.setStart(highlight.firstChild,30);range.setEnd(highlight.firstChild,31);
      const first=document.createRange();first.setStart(highlight.firstChild,0);first.setEnd(highlight.firstChild,1);
      return {inputWidth:input.clientWidth,highlightWidth:highlight.clientWidth,highlightLineHeight:range.getBoundingClientRect().top-first.getBoundingClientRect().top,gutterLineHeight:gutter.children[0].getBoundingClientRect().height};
    });
    assert.equal(result.highlightWidth,result.inputWidth);
    assert.ok(Math.abs(result.highlightLineHeight-result.gutterLineHeight)<1,JSON.stringify(result));
  }finally{await page.close();}
});

test('seven-line phone script stays aligned through wrapping, font changes and rotation',async()=>{
  const page=await fixture(true);
  try{
    for(const width of [220,360]){
      for(const font of [16,20]){
        const result=await page.evaluate(async({width,font})=>{
          const {input,gutter,highlight}=editor;
          input.closest('.editor-stage').style.width=width+'px';
          document.documentElement.style.setProperty('--editor-font',font+'px');
          input.value=['--!native','--!optimize 2','local NewModule = require("../modules/NewModule.luau")','','','local data = NewModule.Data','print(data)'].join('\n');
          editor.render();await new Promise(requestAnimationFrame);
          input.scrollTop=input.scrollHeight;
          input.dispatchEvent(new Event('scroll'));
          const first=document.createRange(),last=document.createRange();
          first.selectNodeContents(highlight.querySelector('.comment'));
          last.selectNodeContents([...highlight.querySelectorAll('.builtin')].find(node=>node.textContent==='print'));
          return {numbers:[...gutter.children].map(node=>node.textContent),drift:(last.getBoundingClientRect().top-first.getBoundingClientRect().top)-(gutter.children[6].getBoundingClientRect().top-gutter.children[0].getBoundingClientRect().top),scroll:input.scrollTop,gutterScroll:gutter.scrollTop,highlightScroll:highlight.parentElement.scrollTop};
        },{width,font});
        assert.deepEqual(result.numbers,['1','2','3','4','5','6','7']);
        assert.ok(Math.abs(result.drift)<1,JSON.stringify(result));
        assert.ok(Math.abs(result.scroll-result.gutterScroll)<=1);
        assert.ok(Math.abs(result.scroll-result.highlightScroll)<=1);
      }
    }
  }finally{await page.close();}
});

test('Wrap off keeps horizontal scrolling aligned after resizing with a scrollbar',async()=>{
  const page=await fixture();
  try{
    for(const width of [320,260]){
      const result=await page.evaluate(async(width)=>{
        const {input,highlight}=editor;
        input.closest('.editor-stage').style.width=width+'px';
        input.wrap='off';input.style.scrollbarGutter='stable';
        for(const node of [input,highlight]){node.style.whiteSpace='pre';node.style.overflowWrap='normal';}
        input.value=Array.from({length:20},()=> 'x'.repeat(300)).join('\n');
        editor.render();await new Promise(requestAnimationFrame);
        input.scrollLeft=input.scrollWidth;input.dispatchEvent(new Event('scroll'));
        return {inputScroll:input.scrollLeft,highlightScroll:highlight.parentElement.scrollLeft};
      },width);
      assert.equal(result.highlightScroll,result.inputScroll);
    }
  }finally{await page.close();}
});
