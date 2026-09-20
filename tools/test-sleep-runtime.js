'use strict';
const assert = require('assert');
const R = require('../launcher/web/modules/sleep-runtime.js');
const P = require('../launcher/web/modules/panel-runtime.js');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
let passed = 0;
function check(value, label) { assert(value, label); passed++; }
check(R.format(0) === '00:00' && R.format(1439) === '23:59', 'midnight and end of day');
check(R.wrap(-1) === 1439 && R.wrap(1440) === 0, 'minute adjustments wrap');
check(R.angles(390).hour === 195 && R.angles(390).minute === 180, 'hour follows minute continuously');
check(R.angles(1110).hour === 195, 'AM and PM share dial geometry');
check(R.angleDelta(359, 1) === 2 && R.angleDelta(1, 359) === -2, 'continuous drag across twelve');
check(R.dragMinutes(1435, 'minute', 60, false) === 5, 'minute hand advances next day');
check(R.dragMinutes(5, 'minute', -60, false) === 1435, 'reverse minute drag crosses midnight');
check(R.dragMinutes(363, 'minute', 12, false) === 365, 'five minute absolute snapping');
check(R.dragMinutes(363, 'minute', 6, true) === 364, 'fine drag to exact minute');
check(R.dragMinutes(393, 'hour', 30, false) === 453, 'hour hand preserves minutes');
check(R.dragMinutes(0, 'minute', 720, false) === 120, 'two full turns remain continuous');
check(R.dragPreview(1020,'hour',14.9) < R.dragPreview(1020,'hour',15.1)
    && R.dragPreview(1020,'hour',15.1)-R.dragPreview(1020,'hour',14.9) < 1
    && R.dragMinutes(1020,'hour',15.1)-R.dragMinutes(1020,'hour',14.9) === 60, 'visual drag stays continuous across hour snap');
check(R.dragPreview(1435,'minute',60) === 5 && R.dragPreview(5,'minute',-60) === 1435, 'visual drag wraps midnight in either direction');
check(R.visualPhase(0).day === 0 && R.visualPhase(720).day === 1, 'midnight and noon moods');
check(R.visualPhase(300).day < R.visualPhase(330).day && R.visualPhase(330).day < R.visualPhase(360).day, 'sunrise is gradual');
check(R.visualPhase(1050).day > R.visualPhase(1095).day && R.visualPhase(1095).day > R.visualPhase(1140).day, 'sunset is gradual');
check(R.visualPhase(1095).day > .4 && R.visualPhase(1095).day < .6, 'twilight has a true intermediate palette');
check(R.visualPhase(1095).sun === 0 && R.visualPhase(1095).moon === 0, 'faces do not overlap in twilight');
check(R.visualPhase(0).day === R.visualPhase(1439).day, 'midnight palette is continuous');
const paletteText = fs.readFileSync(path.resolve(__dirname,'../launcher/web/css/sleep/tokens.css'),'utf8');
function palette(key) {
    const match = new RegExp('--sleep-'+key+':#([0-9a-f]{3,6});','i').exec(paletteText);
    assert(match, 'missing authored palette: '+key);
    const hex = match[1].length === 3 ? [...match[1]].map(c=>c+c).join('') : match[1];
    return [0,2,4].map(i=>parseInt(hex.slice(i,i+2),16));
}
const generatedPalette = require('../launcher/web/assets/sleep/palette.js');
check(generatedPalette.v === 1 && Object.keys(generatedPalette.colors).every(key => generatedPalette.colors[key].length === 3
    && generatedPalette.colors[key].every(value=>Number.isFinite(value) && value>=0 && value<=255)), 'generated palette contains only finite RGB values');
check(JSON.stringify(generatedPalette.colors['day-bg']) === JSON.stringify(palette('day-bg')), 'palette module matches CSS authority without computed-style parsing');
let smoothMood = true, readableMood = true, readableAction = true;
for (let minute=0;minute<1440;minute++) {
    const mood=R.visualPhase(minute), next=R.visualPhase((minute+1)%1440);
    smoothMood = smoothMood && Math.abs(next.day-mood.day)<.013;
    const bg=R.moodColor(palette('night-bg'),palette('twilight-bg'),palette('day-bg'),mood.day);
    const ink=R.readable([bg],palette('day-ink'),palette('night-ink'));
    readableMood = readableMood && R.contrast(ink,bg)>=4.5;
    const action=palette('night-brass'), label=palette('needle-dark');
    readableAction = readableAction && R.contrast(label,action)>=4.5;
}
check(smoothMood,'all 1440 minute boundaries avoid binary palette jumps');
check(readableMood,'text contrast stays readable through every intermediate mood');
check(readableAction,'primary action label never becomes white on white at any target minute');
function follow(rate, targetAt, duration) {
    const frames = []; let value = 1;
    for (let time = 0; time < duration; time += 1000/rate) {
        const target = targetAt(time); value = R.followMood(value,target,1000/rate,1800);
        frames.push({value,target,bg:R.moodColor(palette('night-bg'),palette('twilight-bg'),palette('day-bg'),value),...R.phaseAtDay(value)});
    }
    return frames;
}
for (const rate of [30,60,144]) {
    const frames = follow(rate,()=>0,4000);
    check(frames[0].value < 1 && frames[0].value > .95 && frames.at(-1).value === 0, rate+'Hz transition converges without an initial jump');
    check(frames.every((item,i)=>!i || item.value<=frames[i-1].value && Math.max(...item.bg.map((v,c)=>Math.abs(v-frames[i-1].bg[c])))<=Math.ceil(800/rate)), rate+'Hz palette is monotonic with bounded per-frame color changes');
    check(frames.every(item=>!(item.sun>0 && item.moon>0)), rate+'Hz sun and moon never overlap during animation');
}
const reversed = follow(60,t=>t<450?0:1,4000);
check(reversed.at(-1).value === 1 && reversed.every((item,i)=>!i || Math.abs(item.value-reversed[i-1].value)<.019), 'fast reversal continues smoothly and settles to latest target');
check(Math.abs(R.followMood(.9,0,10000,1800)-.9)<.056, 'resuming a delayed frame cannot skip the whole transition');
check(R.followMood(.5,0,0,1800) === .5 && R.followMood(.5,0,-1,1800) === .5, 'retargeting without elapsed time does not change the current picture');
const state = {v:1, token:'sleep.test.1', operation:'snapshot', phase:'editing', success:true, changed:false,
    currentMinutes:360, targetMinutes:360, cycleEnabled:true, cyclePaused:false, canSleep:true, reason:''};
check(R.normalizeState(state) !== null, 'valid editing');
check(R.normalizeState({...state,cycleEnabled:false,canSleep:false,reason:'cycle_disabled'}) !== null, 'disabled clock snapshot');
check(R.normalizeState({...state,phase:'expired',success:false,canSleep:false,reason:'context_changed'}) !== null, 'expired authority proof');
check(R.normalizeState({...state,operation:'commit',phase:'applied',changed:true,canSleep:false}) !== null, 'complete applied proof');
for (const patch of [{v:2},{token:'other.1'},{currentMinutes:1440},{targetMinutes:'360'},{changed:true},{success:'true'},
    {operation:'commit'},{cycleEnabled:false},{canSleep:false},{reason:'wrong'}, {phase:'applied',changed:true,canSleep:false,targetMinutes:361}]) {
    check(R.normalizeState({...state,...patch}) === null, 'invalid state rejected ' + JSON.stringify(patch));
}
const router = new P.PanelResponseRouter();
let sent, replies = 0;
const mux = new R.RequestMux({panelInstanceId:'sleep.panel.1',router,send:message => { sent=message;return true; }});
mux.request('snapshot',{v:1,token:state.token},() => replies++);
const response = {...state,type:'panel_resp',panel:'sleep',domain:'sleep',cmd:'snapshot',callId:sent.callId,panelInstanceId:'old.panel'};
router.handleResponse(response);check(replies === 0, 'old panel response ignored');
router.handleResponse({...response,panelInstanceId:'sleep.panel.1'});check(replies === 1,'exact response accepted');
router.handleResponse({...response,panelInstanceId:'sleep.panel.1'});check(replies === 1,'duplicate reply ignored');
mux.request('snapshot',{v:1,token:state.token},() => replies++);const late=sent.callId;mux.destroy();
router.handleResponse({...response,callId:late,panelInstanceId:'sleep.panel.1'});check(replies === 1,'destroyed session ignores late response');
console.log('Sleep runtime: '+passed+' passed');
const root = path.resolve(__dirname, '..'), art = path.join(root, 'launcher/web/assets/sleep');
const manifest = JSON.parse(fs.readFileSync(path.join(art, 'manifest.json'), 'utf8'));
const sha = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
assert.deepStrictEqual(fs.readdirSync(art).sort(), ['manifest.json', ...Object.keys(manifest.files)].sort(), 'exact sleep art closure');
assert.strictEqual(manifest.sourceHashEncoding,'utf8-lf','explicit canonical text source hashing');
for (const [file,hash] of Object.entries(manifest.sources)) {
    const canonical = fs.readFileSync(path.join(root,file),'utf8').replace(/\r\n/g,'\n');
    assert.strictEqual(crypto.createHash('sha256').update(canonical,'utf8').digest('hex'),hash,'source changed: '+file);
}
for (const [file,info] of Object.entries(manifest.files)) { assert.strictEqual(sha(path.join(art,file)),info.sha256,'art changed: '+file); assert.strictEqual(fs.statSync(path.join(art,file)).size,info.bytes); }
console.log('Sleep original-art closure: '+Object.keys(manifest.files).filter(name=>name.endsWith('.svg')).length+' SVG assets and generated palette verified');
