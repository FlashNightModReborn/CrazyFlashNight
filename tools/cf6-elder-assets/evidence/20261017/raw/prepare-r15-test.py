from evidence_utils import *

for row in js(TMP/'matrix-r14/input-identity.json')['sourceBindings']:
    assert sha(ROOT/row['path'])==row['sha256'],'Unexpected source drift: '+row['path']
for relative in ['tools/cf6-elder-assets/ElderAI.as','tools/cf6-elder-assets/native-manifest.json',
    'tools/cf6-elder-assets/README.md','flashswf/arts/new/Codex老头素材.swf',
    'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderAssetTest.as']:
    put(TMP/'r14-before-ai'/relative,read(ROOT/relative))
file=ROOT/'scripts/类定义/org/flashNight/arki/unit/Action/Melee/Cf6ElderAssetTest.as'
raw=read(file);assert raw.startswith(b'\xef\xbb\xbf')
source=raw[3:].decode('utf8')
needle='import org.flashNight.arki.component.Damage.*;'
assert source.count(needle)==1
source=source.replace(needle,needle+'\nimport org.flashNight.arki.unit.UnitComponent.Status.ImpactStateHandler;')
needle='        if(ticks==16)for(i=0;i<cases.length;i++){'
assert source.count(needle)==1
addition='''        if(ticks==45)for(i=0;i<cases.length;i++){
            c=cases[i];if(c.form==1 && c.move=="beam"){
                u=c.actor;
                check(u.man._currentframe>29 && u.man._currentframe<64 && u.刚体===true && u.免疫击退===false,
                    "beam recovery retains rigidity but releases displacement brace "+c.side);
                var beamBody:MovieClip=u.man,beamOwner:Object=u.elderAttackOwner;
                var impact:MovieClip=library.createEmptyMovieClip("beamRecoveryImpact"+i,library.getNextHighestDepth());
                impact.伤害类型="物理";impact.破坏力=60;impact.击倒率=0;
                impact.水平击退速度=6;impact.垂直击退速度=0;
                u.防御力=300;u.韧性系数=40;u.躲闪率=50;u.remainingImpactForce=0;u.被击移动=nativeKnockback;
                var impactResult:DamageResult=DamageResult.getIMPACT(),hpBefore:Number=u.hp;
                UniversalDamageHandle.getInstance().handleBulletDamage(impact,null,u,null,impactResult);
                // Fixture settlement applies the production handler's result; production actor code never writes a target's HP.
                u.hp-=u.损伤值;
                check(u.hp==hpBefore-30,"recovery rigidity does not reduce physical damage "+c.side);
                c.record.recoveryImpactX=u._x;
                ImpactStateHandler.handleImpactState(u,impact,impactResult,c.side==0?"右":"左",true);
                check(u.状态=="空手攻击" && u.man===beamBody && u.elderAttackOwner===beamOwner,
                    "production forced impact preserves the committed beam recovery "+c.side);
                check(u.speed==6 && u.减速度==0.5,"post-shot knockback remains enabled "+c.side);
                impact.removeMovieClip();
            }
        }
        if(ticks==50)for(i=0;i<cases.length;i++){
            c=cases[i];if(c.form==1 && c.move=="beam")
                check(Math.abs(c.actor._x-c.record.recoveryImpactX)>1 && c.actor.刚体===true && c.actor.免疫击退===false,
                    "actual production knockback moves the recovering beam actor "+c.side);
        }
'''
source=source.replace(needle,addition+needle)
lp(file).write_bytes(raw[:3]+source.encode('utf8'))
assert read(file).startswith(b'\xef\xbb\xbf')
print('R15 recovery fixture prepared against unchanged R12 published resource; no Worker inputs changed.')
