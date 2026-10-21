"""Read immutable Worker receipts; never turn transport failures into combat losses."""
import json
import hashlib
from pathlib import Path
import statistics
import sys

ROOT=Path(__file__).resolve().parents[2]

def local_path(path):
    path=Path(path).absolute()
    return Path('\\\\?\\'+str(path)) if sys.platform=='win32' and not str(path).startswith('\\\\?\\') else path

def load(path):
    return json.loads(local_path(path).read_text('utf-8-sig'))

def summarize(experiment):
    experiment=Path(experiment)
    report=load(experiment/'experiment-report.json')
    results=[]
    rejected=[]
    identities=[]
    for group in report['groups']:
        for outcome in group['outcomes']:
            receipt=load(outcome['expectedReceiptPath'])
            identities.append(dict(group=group['groupId'],receipt=outcome['expectedReceiptPath'],
                status=receipt['status'],sha256=outcome.get('receiptSha256'),
                cleanupVerified=outcome.get('cleanupVerified'),
                protectedSavesVerified=outcome.get('protectedSavesVerified'),
                runtimeResourcesVerified=outcome.get('runtimeResourcesVerified')))
            if not receipt.get('resultPath'):
                rejected.append(dict(group=group['groupId'],reason='no raw combat results'))
                continue
            raw=local_path(receipt['resultPath']).read_bytes()
            expected=receipt.get('resultSha256','').removeprefix('sha256:').lower()
            if hashlib.sha256(raw).hexdigest()!=expected:raise ValueError('Raw result identity mismatch')
            for line in raw.decode('utf-8-sig').splitlines():
                if not line.strip():continue
                row=json.loads(line)
                side=row.get('authorityContext',{}).get('militarySide')
                if row.get('status') not in ('finished','timeout') or side not in ('blue','red'):
                    rejected.append(dict(group=group['groupId'],runId=row.get('runId'),status=row.get('status')))
                    continue
                own=row[side]
                other='red' if side=='blue' else 'blue'
                units=row.get(side+'UnitResults',[])
                enemy=row.get(other+'UnitResults',[])
                soldiers=[u for u in units if u.get('sourceId','').startswith('soldier-')]
                dog=next((u for u in units if u.get('sourceId')=='iron-guard'),None)
                results.append(dict(group=group['groupId'],militarySide=side,runId=row['runId'],
                    status=row['status'],winner=row['winner'],militaryWin=row['winner']==side,
                    frames=row.get('frames'),durationMs=row.get('durationMs'),
                    militaryRemainHp=own.get('remainHp'),militaryMaxHp=own.get('maxHp'),
                    militaryAlive=own.get('aliveCount'),
                    soldierAlive=sum(bool(u['alive']) for u in soldiers),
                    soldierRemainRatio=(sum(u['remainHp'] for u in soldiers)/sum(u['startMaxHp'] for u in soldiers))
                        if sum(u['startMaxHp'] for u in soldiers)>0 else None,
                    dog=dog,terminators=enemy,
                    terminatorKills=sum(not bool(u['alive']) for u in enemy),
                    enemyRemainHp=row[other].get('remainHp'),
                    enemyStartMaxHp=row[other].get('startMaxHp'),
                    enemyNetHpLossRatio=1-row[other]['remainHp']/row[other]['startMaxHp']
                        if row[other].get('startMaxHp',0)>0 else None,
                    errorCount=len(row.get('errors',[]))))
    aggregates=[]
    for kind in sorted({r['group'] for r in results}):
        for side in ('blue','red'):
            rows=[r for r in results if r['group']==kind and r['militarySide']==side]
            if not rows:continue
            aggregates.append(dict(group=kind,militarySide=side,n=len(rows),
                wins=sum(r['militaryWin'] for r in rows),
                timeouts=sum(r['status']=='timeout' for r in rows),
                meanFrames=statistics.mean(r['frames'] for r in rows if r['frames'] is not None),
                meanSoldierAlive=statistics.mean(r['soldierAlive'] for r in rows),
                meanSoldierRemainRatio=statistics.mean(r['soldierRemainRatio'] for r in rows if r['soldierRemainRatio'] is not None),
                runsWithTerminatorKill=sum(r['terminatorKills']>0 for r in rows),
                meanTerminatorKills=statistics.mean(r['terminatorKills'] for r in rows),
                dogSurvivors=sum(bool(r['dog'] and r['dog']['alive']) for r in rows),
                meanEnemyNetHpLossRatio=statistics.mean(r['enemyNetHpLossRatio'] for r in rows if r['enemyNetHpLossRatio'] is not None),
                meanEnemyRemainHp=statistics.mean(r['enemyRemainHp'] for r in rows)))
    summary=dict(schema='iron-guard.combat-summary.v1',experimentId=report['experimentId'],
        experimentQualified=report['qualified'],status=report['status'],
        usableCombatRows=len(results),rejectedRows=rejected,aggregates=aggregates,runs=results,receipts=identities,
        limitations=['Display coverage must be qualified separately for the entire GUI interval.',
            'Arena faction HP rules apply; compare sides separately.',
            'Dog tier2.5 and assault soldier tier0.6 are not equal budget.',
            'First bite/discharge/first kill timings are not present in standard Worker unit results.',
            'Human art, input and story-stage experience remain separate.'])
    output=experiment/'iron-guard-combat-summary.json'
    output.write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n','utf-8')
    return {k:summary[k] for k in ('experimentId','experimentQualified','status','usableCombatRows','rejectedRows','aggregates')}

if __name__=='__main__':
    if len(sys.argv)!=2:raise SystemExit('Usage: summarize_combat.py <terminal experiment directory>')
    print(json.dumps(summarize(sys.argv[1]),ensure_ascii=False))
