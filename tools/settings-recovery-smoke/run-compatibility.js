'use strict';
const fs=require('fs'),path=require('path'),cp=require('child_process'),crypto=require('crypto');
const sha=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const [dotnet,fixtureArg,newArg,oldArg]=process.argv.slice(2);
if(!dotnet||!fixtureArg||!newArg||!oldArg)throw Error('dotnet fixture.json new-candidate older-candidate required');
const fixturePath=path.resolve(fixtureArg),fixture=JSON.parse(fs.readFileSync(fixturePath,'utf8'));
if(!/^cf7_env_set_[0-9a-f]{20}$/.test(fixture.slot))throw Error('Only this run\'s native owned-SOL fixture is admitted');
const sourceJournal=path.join(fixture.evidenceDirectory,'journal');
const context=fixture.metadata.contextId,recordName=sha(Buffer.from(context))+'.json';
const recordBytes=fs.readFileSync(path.join(sourceJournal,recordName));
const sourceRecord=JSON.parse(recordBytes);
const base=path.join(fixture.evidenceDirectory,'compatibility','matrix-'+new Date().toISOString().replace(/[^0-9TZ]/g,''));
fs.mkdirSync(base,{recursive:false});
const candidates={current:path.resolve(newArg),older:path.resolve(oldArg)};
const report={schema:'cf7-settings-candidate-compatibility.v1',status:'running',fixtureSha256:sha(fs.readFileSync(fixturePath)),
  originalJournalSha256:sha(recordBytes),evidenceKind:'new-old-new candidate cold recovery and admission; no UI rollback or business writer execution',cases:[]};
function persist(){fs.writeFileSync(path.join(base,'report.json'),JSON.stringify(report,null,2));}
persist();
try {
  for(const [name,candidate] of Object.entries(candidates)) {
    const result=cp.spawnSync(path.join(candidate,'CRAZYFLASHER7MercenaryEmpire.exe'),['--verify-runtime-only'],{encoding:'utf8',timeout:30000,windowsHide:true});
    fs.writeFileSync(path.join(base,name+'-runtime-verify.log'),String(result.stdout||'')+String(result.stderr||''));
    if(result.status!==0)throw Error(name+' candidate runtime integrity verification failed');
  }
  const roundTrip=['current','older','current'];
  const cases=[['applied-unconfirmed-exact',true,roundTrip],['unknown-exact',true,roundTrip],
    ['unknown-unrecorded-receipt',false,roundTrip],['confirmed-exact',true,roundTrip],['future-journal-schema',false,roundTrip],
    ['applied-unconfirmed-old-first',true,['older','current']],['unknown-old-first',true,['older','current']],
    ['future-receipt-noncanonical',false,roundTrip]];
  for(const [name,expectedAllowed,sequence] of cases) {
    const caseRoot=path.join(base,name),journal=path.join(caseRoot,'journal');fs.mkdirSync(journal,{recursive:true});
    for(const entry of fs.readdirSync(sourceJournal,{withFileTypes:true})) {
      if(!entry.isFile()||entry.name==='writer.lock')continue;
      fs.copyFileSync(path.join(sourceJournal,entry.name),path.join(journal,entry.name),fs.constants.COPYFILE_EXCL);
    }
    const record=JSON.parse(recordBytes);
    record.rootOperationState='AppliedUnconfirmed';record.confirmation='none';record.lastObservation=null;
    record.currentAttempt.dispatchPhase='Dispatching';record.currentAttempt.attemptOutcome='Unknown';
    if(name.startsWith('unknown-'))record.rootOperationState='Unknown';
    if(name==='unknown-unrecorded-receipt')record.currentAttempt.saveAttemptId='save.unrecorded.'+fixture.slot.slice(-20);
    if(name==='confirmed-exact'||name==='future-receipt-noncanonical') {
      record.rootOperationState='Confirmed';record.confirmation='flush_true';
      record.currentAttempt.dispatchPhase='Returned';record.currentAttempt.attemptOutcome='Confirmed';
    }
    if(name==='future-journal-schema')record.schema=2;
    fs.writeFileSync(path.join(journal,recordName),JSON.stringify(record));
    const journalBefore=sha(fs.readFileSync(path.join(journal,recordName)));
    const row={name,expectedAllowed,journalBeforeRootState:record.rootOperationState,journalBeforeSchema:record.schema,
      parserBoundaryInjection:name==='future-receipt-noncanonical',steps:[]};report.cases.push(row);persist();
    for(const [index,label] of sequence.entries()) {
      const output=path.join(caseRoot,String(index+1)+'-'+label);
      const command=[path.join(__dirname,'bin/Release/net10.0-windows/SettingsRecovery.Smoke.dll'),candidates[label],fixturePath,journal,output];
      if(row.parserBoundaryInjection)command.push('future-receipt-noncanonical');
      const child=cp.spawnSync(dotnet,command,
        {encoding:'utf8',timeout:30000,windowsHide:true});
      fs.writeFileSync(path.join(caseRoot,String(index+1)+'-'+label+'.log'),String(child.stdout||'')+String(child.stderr||''));
      if(child.status!==0)throw Error(name+' '+label+' recovery process failed');
      const observed=JSON.parse(fs.readFileSync(path.join(output,'report.json'),'utf8'));
      const errors=[];
      if(observed.status!=='observed'||observed.allowed!==expectedAllowed||observed.mayWrite!==expectedAllowed)errors.push('admission differs from state contract');
      if(observed.sourceBeforeSha256!==observed.sourceAfterSha256)errors.push('raw SOL changed');
      if(observed.rawReceipt.operationToken!==sourceRecord.operationToken)errors.push('source business token changed');
      if(expectedAllowed&&(observed.record?.rootOperationState!=='Confirmed'||observed.confirmation!=='cold_read_exact'))errors.push('exact receipt did not retain confirmed state');
      if(!expectedAllowed&&sha(fs.readFileSync(path.join(journal,recordName)))!==journalBefore)errors.push('blocked journal was rewritten');
      row.steps.push({candidate:label,report:path.relative(base,path.join(output,'report.json')),pid:observed.pid,
        allowed:observed.allowed,mayWrite:observed.mayWrite,confirmation:observed.confirmation,error:observed.error,errors});persist();
    }
  }
  if(sha(fs.readFileSync(path.join(sourceJournal,recordName)))!==report.originalJournalSha256)throw Error('Original native fixture journal changed');
  report.status=report.cases.some(c=>c.steps.some(s=>s.errors.length))?'incompatible':'passed';
  process.exitCode=report.status==='passed'?0:1;
} catch(error) { report.status='failed';report.error=String(error.stack||error);process.exitCode=1; }
finally {report.completedUtc=new Date().toISOString();persist();console.log(base);}
