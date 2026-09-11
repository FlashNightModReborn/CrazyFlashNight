'use strict';
// 只给固定 cf7_agent_* 验收槽建立/复位克隆；真实玩家档只读。
const fs = require('fs'), path = require('path'), crypto = require('crypto'), cp = require('child_process'), assert = require('assert/strict');
const guards = require('../prepare-loot-target-full-save');
const root = path.resolve(__dirname, '../..');
const bundle = path.join(root, 'tmp/quest-return-acceptance');
const slots = ['cf7_agent_return_university', 'cf7_agent_return_egg', 'cf7_agent_return_recovery'];
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex').toUpperCase();
const clone = value => JSON.parse(JSON.stringify(value));
function assertStopped() {
  const source = '$r=$env:CF7_QUEST_CANDIDATE_ROOT; $p=@(Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($r+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) }); if($p.Count -gt 0){throw "请先退出验收目录中的游戏，再复位验收存档。"}';
  cp.execFileSync('powershell.exe', ['-NoProfile','-EncodedCommand',Buffer.from(source,'utf16le').toString('base64')],
    {windowsHide:true,env:{...process.env,CF7_QUEST_CANDIDATE_ROOT:root},stdio:'pipe'});
}
function active(id, stage) {return {id,requirements:{stages:stage ? [{name:stage,difficulty:'简单'}] : []}};}
function make(seed, index) {
  const d = clone(seed);
  d['0'][0] = ['验收一·大学返回','验收二·彩蛋交付','验收三·奖励恢复'][index];
  // 沿用只读种子的装备与等级，便于快速通关；不修改游戏数据、伤害或剧情锁。
  d.ext.stageSettlement = {v:1,nextSeq:1};
  d.ext.rewardInbox = {v:1,sequence:0,authorityRevision:1,batches:[],receipts:[],migrations:[],supplyKeys:[],activeClaimRoot:null,claimRootTerminal:null};
  d.tasks.tasks_finished['10014']=1;
  delete d.tasks.tasks_finished['10015'];
  if (index === 1) {
    d.tasks.tasks_to_do=[active(10015),active(20033,'AVP'),active(1000003,'AVP')];
    d.tasks.tasks_finished['1000001']=1; d.tasks.tasks_finished['1000002']=1;
    delete d.tasks.tasks_finished['1000003']; delete d.tasks.tasks_finished['20033'];
    d.tasks.task_chains_progress['彩蛋']=2;
  } else {
    d.tasks.tasks_to_do=[active(10015),active(40002,'大学城周边')];
    d.tasks.tasks_finished['40001']=1; delete d.tasks.tasks_finished['40002'];
    d.tasks.task_chains_progress['大学']=1;
  }
  if (index === 2) {
    // 留一个空位：先领取一个真实战利品，再因容量不足暂停/重启/续领。
    const donor=clone(d.inventory['装备栏']['长枪']); assert(donor && donor.name);
    d.inventory['背包']={};
    for(let i=0;i<49;i++) d.inventory['背包'][String(i)]={...clone(donor),lastUpdate:Date.now()+i};
  }
  assert(guards.isValidSaveData(d));
  assert.equal(d.tasks.task_chains_progress['主线'], seed.tasks.task_chains_progress['主线']);
  assert.equal(d.tasks.tasks_to_do[0].requirements.stages.length,0);
  assert(d.tasks.tasks_to_do.slice(1).every(t=>t.requirements.stages.length===1));
  assert(!d.ext.stageSettlement.pending);
  d.lastSaved = new Date().toISOString().slice(0,19).replace('T',' ');
  return d;
}
function install() {
  assertStopped();
  const manifest=JSON.parse(fs.readFileSync(path.join(bundle,'manifest.json'),'utf8'));
  assert.deepEqual(manifest.slots.map(s=>s.key),slots);
  const backup=path.join(bundle,'backups',new Date().toISOString().replace(/[:.]/g,'-'));
  for(const entry of manifest.slots) {
    const source=path.join(bundle,'seeds',entry.key+'.json'), bytes=fs.readFileSync(source);
    assert.equal(hash(bytes),entry.sha256,'验收种子已发生变化');
    assert(guards.isValidSaveData(JSON.parse(bytes)));
    const target=path.join(root,'saves',entry.key+'.json');
    const solFiles=guards.findSolFiles(root,entry.key);
    const files=[target,path.join(root,'saves',entry.key+'.tombstone'),...solFiles];
    for(const file of files) if(fs.existsSync(file)) {
      if(file.endsWith('.sol')) assert(guards.isOwnedSolPath(root,entry.key,file),'拒绝移动非本验收目录的 SOL');
      fs.mkdirSync(backup,{recursive:true});
      const dest=path.join(backup,hash(Buffer.from(file)).slice(0,12)+'-'+path.basename(file));
      fs.copyFileSync(file,dest); assert.equal(hash(fs.readFileSync(dest)),hash(fs.readFileSync(file)));
      fs.unlinkSync(file);
    }
    fs.mkdirSync(path.dirname(target),{recursive:true}); fs.writeFileSync(target,bytes,{flag:'wx'});
  }
  console.log(JSON.stringify({success:true,root,slots,manifest:path.join(bundle,'manifest.json'),physicalJourneys:'pending'}));
}
const args=process.argv.slice(2);
if(args.length===1&&args[0]==='--reset') install();
else {
  assert(args.length===2&&args[0]==='--seed','用法：--seed <只读玩家 JSON>，或 --reset');
  assertStopped(); assert(!fs.existsSync(path.join(bundle,'manifest.json')),'已存在验收包，请使用 --reset');
  const source=path.resolve(args[1]), raw=fs.readFileSync(source), seed=JSON.parse(raw.toString('utf8').replace(/^\uFEFF/,''));
  assert(guards.isValidSaveData(seed));
  fs.mkdirSync(path.join(bundle,'seeds'),{recursive:true});
  const entries=slots.map((key,index)=>{
    const data=make(seed,index), bytes=Buffer.from(JSON.stringify(data));
    fs.writeFileSync(path.join(bundle,'seeds',key+'.json'),bytes,{flag:'wx'});
    return {key,name:data['0'][0],sha256:hash(bytes),tasks:data.tasks.tasks_to_do.map(t=>t.id),backpackOccupied:Object.keys(data.inventory['背包']).length};
  });
  assert.equal(hash(fs.readFileSync(source)),hash(raw),'原存档必须保持原样');
  fs.writeFileSync(path.join(bundle,'manifest.json'),JSON.stringify({version:1,source,sourceSha256:hash(raw),createdAt:new Date().toISOString(),slots:entries,
    limitation:'模板不含伪造的待领取奖励；必须通过真实关卡产生结算。未验证真机保存重启。'},null,2),{flag:'wx'});
  install();
}
