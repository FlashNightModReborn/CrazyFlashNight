'use strict';

const fs = require('fs');
const path = require('path');
const http = require('http');
const assert = require('assert/strict');
const repo = path.resolve(process.cwd());
const web = path.join(repo, 'launcher/web');
const outputRoot = path.resolve(repo, 'tmp/cf6-roguelike-20261021');
const args = process.argv.slice(2);
if (args.length && (args.length !== 2 || args[0] !== '--output-dir')) throw new Error('usage: node test_cf6_web_browser.js [--output-dir <fresh repository tmp directory>]');
const stamp = new Date().toISOString().replace(/[:.]/g, '-') + '-' + process.pid;
const output = args.length ? path.resolve(repo, args[1]) : path.join(outputRoot, 'validation/comic-headless', stamp);
const outputRelative = path.relative(outputRoot, output);
if (!outputRelative || outputRelative.startsWith('..') || path.isAbsolute(outputRelative)) throw new Error('unsafe output');
if (fs.existsSync(output) && fs.readdirSync(output).length) throw new Error('output directory must be fresh; preserve previous reports');
const { chromium } = require(path.join(repo, 'launcher/perf/node_modules/playwright'));
const mime = { '.css':'text/css', '.js':'text/javascript', '.svg':'image/svg+xml', '.png':'image/png', '.mp3':'audio/mpeg' };
const fixture = `<!doctype html>
<meta charset="utf-8">
<link rel="stylesheet" href="/css/panels.css">
<style>html,body{margin:0;width:100%;height:100%}.panel-scale-shell{position:absolute;transform:scale(var(--panel-scale));transform-origin:top left;width:var(--pss-w);height:var(--pss-h)}</style>
<div id="panel-container" data-panel="book-comic"><div id="panel-content"></div></div>
<script src="/modules/panel-scale.js"></script>
<script src="/modules/book-comic-content.js"></script>
<script src="/modules/book-comic-panel.js"></script>
<script>
window.comicRoot=spec.create();document.querySelector('#panel-content').append(comicRoot);
window.presentationSequence=0;window.instanceSequence=0;
window.openComic=function(pageId){spec.onClose();messages.length=0;session={v:1,presentationId:'bookcomic:'+(++presentationSequence),slot:'fixture',sceneId:'scene:1',pageId:pageId,panelInstanceId:'fixture:'+(++instanceSequence)};spec.onOpen(comicRoot,session);return session};
window.messageFor=function(cmd){return messages.filter(function(m){return m.cmd===cmd}).at(-1)};
window.ack=function(message,success,error){reply({type:'panel_resp',panel:'book-comic',domain:'book-comic',panelInstanceId:message.panelInstanceId,presentationId:message.payload.presentationId,callId:message.callId,cmd:message.cmd,success:success!==false,error:error||(success===false?'fixture failure':'')})};
window.hostClose=function(){spec.onClose()};
</script>`;

const server = http.createServer((request, response) => {
  if (request.url === '/fixture') {
    response.setHeader('Content-Type', 'text/html; charset=utf-8');
    response.end(fixture);
    return;
  }
  let pathname;
  try { pathname = decodeURIComponent(new URL(request.url, 'http://127.0.0.1').pathname); }
  catch { response.writeHead(400).end(); return; }
  const file = path.resolve(web, '.' + pathname);
  const relative = path.relative(web, file);
  if (relative.startsWith('..') || path.isAbsolute(relative)) { response.writeHead(403).end(); return; }
  fs.readFile(file, (error, bytes) => {
    response.writeHead(error ? 404 : 200, {'Content-Type':mime[path.extname(file)] || 'application/octet-stream'});
    response.end(error ? '' : bytes);
  });
});

async function installFixture(page, base, errors, fakeClock) {
  if (fakeClock) await page.clock.install();
  await page.addInitScript(() => {
    window.messages=[];window.cameras=[];window.audioInstances=[];window.audioEvents=[];window.audioPlayDeferreds=[];window.audioPlayMode='resolve';window.foreignEvents=[];
    window.Panels={register:(id,value)=>window.spec=value};
    window.Bridge={on:(name,handler)=>window.reply=handler,off:()=>{},send:message=>{messages.push(message);return true}};
    const draw=CanvasRenderingContext2D.prototype.drawImage;
    CanvasRenderingContext2D.prototype.drawImage=function(...args){
      if(args.length===9)cameras.push({source:args.slice(1,5),destination:args.slice(5,9),width:args[0].naturalWidth,height:args[0].naturalHeight});
      else cameras.push({whole:true});
      if(cameras.length>10000)cameras.splice(0,1000);
      return draw.apply(this,args);
    };
    window.Audio=class {
      constructor(){this.id=audioInstances.length+1;this._time=0;this.paused=true;this.ended=false;this.loop=false;this.volume=1;audioInstances.push(this)}
      set src(value){this._src=value}get src(){return this._src}
      set currentTime(value){this._time=value;audioEvents.push({id:this.id,type:'time',value:value,kind:this.__comicKind})}get currentTime(){return this._time}
      play(){this.paused=false;audioEvents.push({id:this.id,type:'play',kind:this.__comicKind,src:this.src,time:this.currentTime,loop:this.loop});if(audioPlayMode==='pending'){const deferred={audio:this};deferred.promise=new Promise((resolve,reject)=>{deferred.resolve=resolve;deferred.reject=reject});audioPlayDeferreds.push(deferred);return deferred.promise}if(audioPlayMode==='reject')return Promise.reject(new Error('mock audio rejection'));return Promise.resolve()}
      pause(){this.paused=true;audioEvents.push({id:this.id,type:'pause',kind:this.__comicKind,src:this.src})}
    };
    window.foreignAudio={pause:()=>foreignEvents.push('pause'),play:()=>foreignEvents.push('play')};
  });
  page.on('pageerror', error => errors.push(error.message));
  await page.goto(`${base}/fixture`);
  await page.setViewportSize({width:1024,height:576});
}

async function waitForCommand(page, cmd, pageId) {
  await page.waitForFunction(({cmd,pageId}) => messages.some(message => message.cmd===cmd&&message.payload.pageId===pageId), {cmd,pageId});
  return page.evaluate(cmd => messageFor(cmd), cmd);
}

async function openAndPrepare(page, pageId) {
  await page.evaluate(id => openComic(id), pageId);
  const prepared = await waitForCommand(page, 'prepared', pageId);
  await page.evaluate(message => ack(message, true), prepared);
  await page.waitForFunction(id => {
    const content=id.indexOf('cf6-')===0?BOOK_COMIC_CF6_CONTENT:BOOK_COMIC_CONTENT;
    const data=content.pages.find(page=>page.id===id);
    return data&&document.querySelector('[data-comic=whole]').src.endsWith(data.image);
  }, pageId);
  return prepared;
}

async function closeAfterTerminal(page, message) {
  assert(message, 'terminal request exists');
  await page.evaluate(() => hostClose());
}

function near(actual, expected, label) {
  assert(Math.abs(actual-expected)<0.02, `${label}: ${actual} != ${expected}`);
}

async function checkTranscript(page, pageId) {
  const actual = await page.evaluate(id => {
    const data=BOOK_COMIC_CF6_CONTENT.pages.find(page=>page.id===id);
    return {expected:data.panels.map(panel=>panel.texts.map(text=>text.text)),actual:Array.from(document.querySelectorAll('[data-comic=transcript] article')).map(article=>Array.from(article.querySelectorAll('p')).map(p=>p.textContent))};
  }, pageId);
  assert.deepEqual(actual.actual, actual.expected, `${pageId} transcript retains original text`);
}

async function checkCurrentViewport(page, pageId, panelIndex) {
  const current = await page.evaluate(() => ({camera:cameras.filter(camera=>camera.source).at(-1),tag:document.querySelector('[data-comic=tag]').textContent}));
  const panel = await page.evaluate(({pageId,panelIndex}) => BOOK_COMIC_CF6_CONTENT.pages.find(page=>page.id===pageId).panels[panelIndex], {pageId,panelIndex});
  assert(current.camera, `${pageId} page ${panelIndex+1} drew a cropped original viewport`);
  assert(current.tag.startsWith(String(panelIndex+1).padStart(2,'0')), current.tag);
  const expected=[panel.rect[0]*current.camera.width,panel.rect[1]*current.camera.height,panel.rect[2]*current.camera.width,panel.rect[3]*current.camera.height];
  current.camera.source.forEach((value,index)=>near(value,expected[index],`${pageId}/${panel.id} viewport ${index}`));
}

async function checkCanvasHasImage(page) {
  const colors = await page.evaluate(() => {
    const canvas=document.querySelector('[data-comic=canvas]');
    const data=canvas.getContext('2d').getImageData(0,0,canvas.width,canvas.height).data;
    const colors=new Set();
    for(let y=0;y<canvas.height;y+=32)for(let x=0;x<canvas.width;x+=32){const i=(y*canvas.width+x)*4;colors.add(`${data[i]},${data[i+1]},${data[i+2]},${data[i+3]}`)}
    return colors.size;
  });
  assert(colors>4, `canvas has rendered artwork, color buckets=${colors}`);
}

async function checkAllReadablePages(page, report) {
  for(let segment=1;segment<=7;segment++) {
    const pageId=`cf6-s${segment}`;
    await openAndPrepare(page,pageId);
    const panelCount=await page.evaluate(id=>BOOK_COMIC_CF6_CONTENT.pages.find(page=>page.id===id).panels.length,pageId);
    await checkTranscript(page,pageId);
    for(let index=0;index<panelCount;index++) {
      if(index)await page.locator('[data-comic=next]').click();
      await checkCurrentViewport(page,pageId,index);
      if((pageId==='cf6-s1'&&index===0)||(pageId==='cf6-s2'&&index===0)||(pageId==='cf6-s7'&&index===panelCount-1)) {
        const name=`${pageId}-page-${index+1}.png`;
        await page.screenshot({path:path.join(output,name)});report.screenshots.push(name);
      }
    }
    await checkCanvasHasImage(page);
    const terminal=await page.evaluate(()=>{document.querySelector('[data-comic=continue]').click();return messageFor('continue')});
    await closeAfterTerminal(page,terminal);
    const stopped=await page.evaluate(()=>audioInstances.every(audio=>audio.paused&&audio.currentTime===0));
    assert(stopped,`${pageId} continue stops only its owned audio`);
    report.checkedSegments.push({pageId,pages:panelCount});
  }
}

async function runNaturalCf6(page, pageId) {
  const duration=await page.evaluate(id=>BOOK_COMIC_CF6_CONTENT.pages.find(page=>page.id===id).panels.reduce((sum,panel)=>sum+panel.duration,0),pageId);
  await page.clock.runFor(Math.ceil((duration+3)*1000));
  const terminal=await waitForCommand(page,'continue',pageId);
  await page.clock.runFor(1000);
  assert.equal(await page.evaluate(()=>messages.filter(message=>message.cmd==='continue').length),1,`${pageId} natural completion sends one continue`);
  assert.equal(await page.evaluate(()=>messages.some(message=>message.cmd==='skip'||message.cmd==='failed')),false,`${pageId} natural completion has no skip/failure`);
  assert.equal(await page.locator('[data-comic=reading]').isVisible(),false,`${pageId} natural completion does not force overview`);
  assert(await page.evaluate(()=>audioInstances.every(audio=>audio.paused&&audio.currentTime===0)),`${pageId} natural completion stops owned audio`);
  return terminal;
}

async function checkAutomaticPlayback(browser, base, errors, report) {
  const page=await browser.newPage();
  try {
    await installFixture(page,base,errors,true);
    await checkContentTimeout(page,report);
    await openAndPrepare(page,'cf6-s1');
    await page.clock.runFor(4000);
    assert((await page.locator('[data-comic=tag]').innerText()).startsWith('02'),'original frame clock advances to page 2');
    await page.locator('[data-comic=read]').click();
    await page.clock.runFor(30000);
    assert.equal(await page.locator('[data-comic=reading]').isVisible(),true,'user-selected overview remains available');
    assert.equal(await page.evaluate(()=>messages.some(message=>message.cmd==='continue')),false,'user-selected reading pauses natural completion');
    await page.evaluate(()=>hostClose());

    await openAndPrepare(page,'cf6-s4');
    await runNaturalCf6(page,'cf6-s4');
    await openAndPrepare(page,'cf6-s5');
    assert.equal(await page.evaluate(()=>session.pageId),'cf6-s5','s4 natural continue lets Host open s5');
    await page.evaluate(()=>hostClose());

    await openAndPrepare(page,'cf6-s7');
    await runNaturalCf6(page,'cf6-s7');
    await openAndPrepare(page,'cf6-end');
    assert(await page.locator('[data-comic=play]').isDisabled());
    assert(await page.locator('[data-comic=next]').isDisabled());
    await page.clock.runFor(5000);
    assert.equal(await page.evaluate(()=>messages.some(message=>message.cmd==='continue')),false,'manual credits never invent an automatic duration');
    await page.locator('[data-comic=continue]').click();
    await closeAfterTerminal(page,await page.evaluate(()=>messageFor('continue')));

    await openAndPrepare(page,'prologue');
    const campusDuration=await page.evaluate(()=>BOOK_COMIC_CONTENT.pages.find(page=>page.id==='prologue').panels.reduce((sum,panel)=>sum+Math.max(2,panel.duration||8,panel.lines.reduce((n,line)=>n+Math.max(2,line.text.length/5+1),0)),0));
    await page.clock.runFor(Math.ceil((campusDuration+3)*1000));
    assert.equal(await page.locator('[data-comic=reading]').isVisible(),true,'campus retains natural browsable overview');
    assert.equal(await page.evaluate(()=>messages.some(message=>message.cmd==='continue'||message.cmd==='skip')),false,'campus natural overview does not authorize completion');
    await page.locator('[data-comic=continue]').click();
    await closeAfterTerminal(page,await page.evaluate(()=>messageFor('continue')));
    report.automaticPlayback={readingPause:true,s4ToS5:true,s7ToCredits:true,naturalContinueCount:1,creditsManual:true,campusOverview:true};
  } finally {await page.close()}
}

async function checkContentLoading(page, report) {
  const pattern='**/modules/book-comic-cf6-content.js';
  await page.evaluate(()=>{delete window.BOOK_COMIC_CF6_CONTENT});
  await page.route(pattern,route=>route.abort());
  try {
    await page.evaluate(()=>openComic('cf6-s3'));
    const failed=await waitForCommand(page,'failed','cf6-s3');
    assert.equal(await page.evaluate(()=>messages.some(message=>message.cmd==='prepared')),false);
    assert.equal(await page.evaluate(()=>typeof window.BOOK_COMIC_CF6_CONTENT),'undefined','failed script loading is not cached as empty content');
    await closeAfterTerminal(page,failed);
  } finally {await page.unroute(pattern)}
  await openAndPrepare(page,'cf6-s3');
  await page.evaluate(()=>hostClose());

  await page.evaluate(()=>{delete window.BOOK_COMIC_CF6_CONTENT});
  let contentRequests=0;
  const delayed=async route=>{contentRequests++;await new Promise(resolve=>setTimeout(resolve,50));await route.continue()};
  await page.route(pattern,delayed);
  try {
    await page.evaluate(()=>{const current=openComic('cf6-s1');spec.onRebind(comicRoot,current);spec.onRebind(comicRoot,current)});
    const prepared=await waitForCommand(page,'prepared','cf6-s1');
    assert.equal(contentRequests,1,'two rebinds share one in-flight content script');
    assert.equal(await page.evaluate(()=>messages.filter(message=>message.cmd==='prepared').length),1,'only the latest rebind prepares the panel');
    await page.evaluate(message=>ack(message,true),prepared);
    await page.evaluate(()=>hostClose());
  } finally {await page.unroute(pattern)}
  report.contentLoading={failureRetried:true,rebindRequests:contentRequests,latestRebindOnly:true};
}

async function checkContentTimeout(page, report) {
  const pattern='**/modules/book-comic-cf6-content.js';
  let stalled=null;
  await page.route(pattern,route=>{stalled=route});
  try {
    await page.evaluate(()=>{delete window.BOOK_COMIC_CF6_CONTENT;openComic('cf6-s1')});
    await page.clock.runFor(10000);
    const failed=await waitForCommand(page,'failed','cf6-s1');
    assert(stalled,'content request actually stalled');
    assert.equal(await page.evaluate(()=>messages.some(message=>message.cmd==='prepared')),false);
    await closeAfterTerminal(page,failed);
  } finally {
    if(stalled)await stalled.abort().catch(()=>{});
    await page.unroute(pattern);
  }
  await openAndPrepare(page,'cf6-s1');
  await page.evaluate(()=>hostClose());
  report.contentTimeout={timeoutMs:10000,failed:true,retrySucceeded:true};
}

async function checkAudioOwnershipAndSeek(page, report) {
  await openAndPrepare(page,'cf6-s1');
  await page.locator('[data-comic=play]').click();
  assert(await page.evaluate(()=>audioInstances.slice(-2).every(audio=>audio.paused)),'pause suspends narration and music');
  await page.evaluate(()=>{audioInstances.slice(-2).find(audio=>audio.__comicKind==='music').currentTime=12.5});
  await page.locator('[data-comic=next]').click();
  const expected=await page.evaluate(()=>BOOK_COMIC_CF6_CONTENT.pages.find(page=>page.id==='cf6-s1').panels[0].duration);
  assert(await page.evaluate(()=>audioInstances.slice(-2).every(audio=>audio.paused)),'manual next remains paused');
  await page.locator('[data-comic=play]').click();
  const times=await page.evaluate(()=>{const owned=audioInstances.slice(-2);return{narration:owned.find(audio=>audio.__comicKind==='narration').currentTime,music:owned.find(audio=>audio.__comicKind==='music').currentTime}});
  near(times.narration,expected,'resume seeks narration to the new page frame clock');
  near(times.music,12.5,'resume never seeks music to narration time');
  await page.evaluate(()=>hostClose());

  await page.evaluate(()=>{audioPlayDeferreds=[];audioPlayMode='pending'});
  await openAndPrepare(page,'cf6-s1');
  const pendingCount=await page.evaluate(()=>audioPlayDeferreds.length);
  assert.equal(pendingCount,2,'fixture holds the old narration and music play promises');
  await page.evaluate(()=>{audioPlayMode='resolve'});
  await openAndPrepare(page,'cf6-s2');
  await page.evaluate(count=>{audioPlayDeferreds.slice(0,count).forEach(deferred=>deferred.reject(new Error('old session rejected')))},pendingCount);
  await page.waitForTimeout(20);
  assert.equal(await page.locator('[data-comic=status]').innerText(),'','old audio rejection cannot overwrite replacement session UI');
  await page.evaluate(()=>{hostClose();audioPlayDeferreds=[];audioPlayMode='resolve'});
  report.audioOwnershipAndSeek={pauseResume:true,manualNextNarrationSeek:true,musicNotSeeked:true,lateRejectionIsolated:true};
}

async function checkLeaseDegradation(page, report) {
  await page.evaluate(()=>openComic('cf6-s1'));
  const prepared=await waitForCommand(page,'prepared','cf6-s1');
  assert(await page.evaluate(()=>audioInstances.slice(-2).every(audio=>audio.paused)),'prepared response gates owned audio start');
  await page.evaluate(message=>ack(message,true,'bgm_lease_unavailable'),prepared);
  await page.waitForFunction(()=>{const owned=audioInstances.slice(-2);return owned.some(audio=>audio.__comicKind==='narration'&&!audio.paused)});
  const degraded=await page.evaluate(()=>{const owned=audioInstances.slice(-2),ids=owned.map(audio=>audio.id);return{plays:audioEvents.filter(event=>event.type==='play'&&ids.includes(event.id)).map(event=>event.kind),musicPaused:owned.find(audio=>audio.__comicKind==='music').paused,status:document.querySelector('[data-comic=status]').textContent}});
  assert.deepEqual(degraded.plays,['narration'],'lease failure suppresses only this segment music');
  assert.equal(degraded.musicPaused,true,'unconfirmed lease never starts comic music');
  assert.match(degraded.status,/外部音乐状态未确认/,'degradation is visible without claiming external silence');
  await checkTranscript(page,'cf6-s1');
  await page.evaluate(()=>hostClose());

  await openAndPrepare(page,'cf6-s2');
  const recovered=await page.evaluate(()=>{const owned=audioInstances.slice(-2),ids=owned.map(audio=>audio.id);return{plays:audioEvents.filter(event=>event.type==='play'&&ids.includes(event.id)).map(event=>event.kind),status:document.querySelector('[data-comic=status]').textContent}});
  assert.deepEqual(recovered.plays,['narration','music'],'next segment reacquires its own music capability');
  assert.equal(recovered.status,'','next segment clears the previous degradation');
  await page.evaluate(()=>hostClose());
  report.leaseDegradation={musicSuppressed:true,narrationContinues:true,originalTextRetained:true,nextSegmentMusicRecovered:true};
}

async function checkOriginalAudioTiming(browser, base, errors, report) {
  const page=await browser.newPage();
  try {
    await installFixture(page,base,errors,true);
    await openAndPrepare(page,'cf6-s3');
    const state=()=>page.evaluate(()=>{const owned=audioInstances.slice(-2),n=owned.find(a=>a.__comicKind==='narration'),m=owned.find(a=>a.__comicKind==='music');return{narrationId:n.id,paused:n.paused,time:n.currentTime,plays:audioEvents.filter(e=>e.id===n.id&&e.type==='play'),musicLoop:m.loop}});
    assert.equal((await state()).plays.length,0,'s3 does not start narration before source frame110');
    await page.clock.runFor(3000);
    assert.equal((await state()).plays.length,0,'s3 first three seconds retain original silence');
    await page.locator('[data-comic=play]').click();
    await page.clock.runFor(10000);
    assert.equal((await state()).plays.length,0,'paused wall time cannot consume the narration offset');
    await page.locator('[data-comic=play]').click();
    await page.clock.runFor(1000);
    const started=await state();
    assert.equal(started.plays.length,1,'narration starts once when the comic clock crosses frame110');
    assert(started.plays[0].time>=0&&started.plays[0].time<0.05,'delayed narration starts at the beginning of its unchanged MP3');
    assert.equal(started.musicLoop,true,'owned comic music retains looping behavior');
    await page.locator('[data-comic=play]').click();
    await page.locator('[data-comic=next]').click();
    const seek=await page.evaluate(()=>{const p=BOOK_COMIC_CF6_CONTENT.pages.find(p=>p.id==='cf6-s3');return p.panels.slice(0,2).reduce((n,p)=>n+p.duration,0)-p.audio.narrationStartSec});
    await page.locator('[data-comic=play]').click();
    near((await state()).time,seek,'manual next resumes narration at comic time minus its original offset');
    await page.evaluate(()=>hostClose());

    await openAndPrepare(page,'cf6-s3');
    const retired=(await state()).narrationId;
    await page.clock.runFor(1000);
    await openAndPrepare(page,'cf6-s1');
    await page.clock.runFor(4000);
    assert.equal(await page.evaluate(id=>audioEvents.some(e=>e.id===id&&e.type==='play'),retired),false,'retired delayed narration cannot start in a replacement session');
    await page.evaluate(()=>hostClose());

    await openAndPrepare(page,'cf6-s7');
    const finalMusic=await page.evaluate(()=>{const p=BOOK_COMIC_CF6_CONTENT.pages.find(p=>p.id==='cf6-s7');return{duration:p.timeline.durationSec,loop:audioInstances.slice(-2).find(a=>a.__comicKind==='music').loop,narrationLoop:audioInstances.slice(-2).find(a=>a.__comicKind==='narration').loop}});
    assert(finalMusic.duration>40.62,'s7 extends past the original music03 track length');
    assert.equal(finalMusic.loop,true,'s7 music is configured to loop beyond the first track');
    assert.equal(finalMusic.narrationLoop,false,'narration does not loop');
    await page.evaluate(()=>hostClose());
    await openAndPrepare(page,'cf6-end');
    assert.equal(await page.evaluate(()=>audioInstances.at(-1).loop),true,'manual credits keep their original music loop');
    await page.evaluate(()=>hostClose());
    report.originalAudioTiming={s3FirstFrame:110,startOffsetSec:109/30,pausePreservesOffset:true,manualSeekSubtractsOffset:true,retiredDelayedAudioSilent:true,s7MusicLoops:true,creditsMusicLoops:true,narrationNeverLoops:true};
  } finally {await page.close()}
}

async function checkSkipAndLateResponse(page, report) {
  await openAndPrepare(page,'cf6-s2');
  await page.evaluate(()=>document.activeElement.blur());
  await page.keyboard.press('Space');
  const skipped=await waitForCommand(page,'skip','cf6-s2');
  await page.keyboard.press('Space');
  await page.locator('[data-comic=continue]').evaluate(button=>button.click());
  assert.equal(await page.evaluate(()=>messages.filter(message=>message.cmd==='skip').length),1,'busy duplicate space cannot finish twice');
  assert.equal(await page.evaluate(()=>messages.some(message=>message.cmd==='continue')),false,'disabled continue cannot bypass skip');
  assert(await page.evaluate(()=>audioInstances.every(audio=>audio.paused&&audio.currentTime===0)),'space skip stops the whole segment audio');
  await closeAfterTerminal(page,skipped);
  await openAndPrepare(page,'cf6-s4');
  await page.evaluate(message=>ack(message,false),skipped);
  assert.equal(await page.locator('[data-comic=play]').innerText(),'暂停','late response cannot alter replacement presentation');
  const current=await page.evaluate(()=>{document.querySelector('[data-comic=continue]').click();return messageFor('continue')});
  await closeAfterTerminal(page,current);
  report.skipAndLateResponse={skipCount:1,duplicateIgnored:true,lateResponseIgnored:true};
}

async function checkFailureCancellationAndCredits(page, report) {
  await openAndPrepare(page,'cf6-s5');
  await page.evaluate(()=>spec.onRequestClose());
  const failed=await waitForCommand(page,'failed','cf6-s5');
  assert.equal(await page.evaluate(()=>messages.some(message=>message.cmd==='continue'||message.cmd==='skip')),false);
  await closeAfterTerminal(page,failed);

  await openAndPrepare(page,'cf6-s6');
  const before=await page.evaluate(()=>messages.length);
  await page.evaluate(()=>hostClose());
  assert.equal(await page.evaluate(()=>messages.length),before,'world/panel cleanup emits no completion');
  assert(await page.evaluate(()=>audioInstances.every(audio=>audio.paused&&audio.currentTime===0)),'cleanup stops owned audio');

  await page.route('**/assets/book-comic/cf6/cf6-s3/comic.svg',route=>route.abort());
  await page.evaluate(()=>openComic('cf6-s3'));
  const loadFailed=await waitForCommand(page,'failed','cf6-s3');
  assert.equal(await page.evaluate(()=>messages.some(message=>message.cmd==='prepared')),false);
  await closeAfterTerminal(page,loadFailed);
  await page.unroute('**/assets/book-comic/cf6/cf6-s3/comic.svg');

  await openAndPrepare(page,'cf6-end');
  assert(await page.locator('[data-comic=play]').isDisabled());
  assert(await page.locator('[data-comic=next]').isDisabled());
  await checkTranscript(page,'cf6-end');
  await checkCurrentViewport(page,'cf6-end',0);
  await checkCanvasHasImage(page);
  await page.screenshot({path:path.join(output,'cf6-end.png')});report.screenshots.push('cf6-end.png');
  const terminal=await page.evaluate(()=>{document.querySelector('[data-comic=continue]').click();return messageFor('continue')});
  await closeAfterTerminal(page,terminal);
  assert(await page.evaluate(()=>audioInstances.every(audio=>audio.paused&&audio.currentTime===0)));
  report.failureCancellationAndCredits={closeUsesFailed:true,cleanupSilent:true,imageFailure:true,manualCredits:true};
}

async function checkCampusRegression(page, report) {
  await openAndPrepare(page,'prologue');
  const audioCount=await page.evaluate(()=>audioInstances.length);
  await page.evaluate(()=>document.activeElement.blur());
  await page.keyboard.press('Space');
  assert.equal(await page.locator('[data-comic=play]').innerText(),'播放');
  await page.keyboard.press('Space');
  assert.equal(await page.locator('[data-comic=play]').innerText(),'暂停');
  assert.equal(await page.evaluate(()=>messages.some(message=>message.cmd==='skip')),false);
  assert.equal(await page.evaluate(()=>audioInstances.length),audioCount,'campus does not acquire CF6 audio');
  await page.evaluate(()=>hostClose());
  report.campusRegression={spacePausesAndResumes:true,noCf6Audio:true};
}

async function main() {
  fs.mkdirSync(output,{recursive:true});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const base=`http://127.0.0.1:${server.address().port}`;
  const browser=await chromium.launch({executablePath:path.join(process.env['ProgramFiles(x86)'],'Microsoft/Edge/Application/msedge.exe'),headless:true,args:['--mute-audio']});
  const errors=[];
  const report={schema:'cf6-r14-headless.v1',audio:'mocked; no audible validation',checkedSegments:[],screenshots:[],checks:[]};
  try {
    const page=await browser.newPage();
    await installFixture(page,base,errors,false);
    await checkAllReadablePages(page,report);
    await checkContentLoading(page,report);
    await checkAudioOwnershipAndSeek(page,report);
    await checkLeaseDegradation(page,report);
    await checkSkipAndLateResponse(page,report);
    await checkFailureCancellationAndCredits(page,report);
    await checkCampusRegression(page,report);
    await checkAutomaticPlayback(browser,base,errors,report);
    await checkOriginalAudioTiming(browser,base,errors,report);
    assert.deepEqual(errors,[]);
    assert.deepEqual(await page.evaluate(()=>foreignEvents),[],'foreign audio was never touched');
    report.pageErrors=errors;
    report.foreignAudioUntouched=true;
    report.passed=true;
    fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2)+'\n');
    console.log(`PASS: ${report.checkedSegments.reduce((sum,item)=>sum+item.pages,0)} CF6 comic viewports + credits; natural s4/s5 and s7/credits chains, content failure/timeout/rebind, audio ownership/seek, lease degradation/recovery, skip/continue/failed/cancel/late response, campus regression. Screenshots: ${output}`);
  } catch(error) {
    report.pageErrors=errors;report.passed=false;report.error={message:error.message,stack:error.stack};
    fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2)+'\n');
    throw error;
  } finally {await browser.close();server.close()}
}

main().catch(error=>{console.error(error);server.close();process.exitCode=1});
