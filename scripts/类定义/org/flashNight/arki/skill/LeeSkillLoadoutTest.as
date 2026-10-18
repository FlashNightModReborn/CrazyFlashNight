import org.flashNight.arki.skill.LeeSkillLoadout;
import org.flashNight.arki.skill.SkillPanelService;
import org.flashNight.arki.unit.Action.Input.EnemyActionRuntime;
import org.flashNight.arki.unit.Action.Input.LeeActionProfile;
import org.flashNight.arki.ui.BookshelfPanelService;
class org.flashNight.arki.skill.LeeSkillLoadoutTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean, text:String):Void {
        if(value) passed++; else {failed++;trace("[FAIL] LeeSkillLoadout "+text);}
    }
    public static function runAllTests():Void {
        passed=failed=0;
        var saved:Object={world:_root.gameworld,ext:_root._saveExt,slot:_root.savePath,control:_root.控制目标,
            save:_root.存档系统,level:_root.等级,keyshow:_root.keyshow,table:_root.主角技能表,refresh:_root.刷新技能栏显示};
        var run:Object={bookId:"lee-trial",slot:"bookrun_loadout_fixture",outcome:"active"};
        var world:Object={__stageReturnWorldIdentity:{}}, unit:Object={__enemyActionPlayer:true,宠物属性:{},hp:100};
        unit.__controlledEnemyContext={run:run,slot:run.slot,world:world.__stageReturnWorldIdentity};
        var cooldowns:Object={hop:500,a1:300}, active:Object={actionId:"a1"};
        unit.__enemyActionRuntime={identity:{},enabled:true,profile:LeeActionProfile.create(true),cooldowns:cooldowns,active:active};
        world.hero=unit; _root.gameworld=world; _root._saveExt={bookRun:run};_root.savePath=run.slot;_root.控制目标="hero";
        _root.等级=35; _root.存档系统={markDirty:function():Void{}}; _root.刷新技能栏显示=function():Void{};
        _root.keyshow=function(value):String{return "K";};_root.主角技能表=[["保留主角技能",9,false,"武术",true]];
        LeeSkillLoadout.bind(unit);
        var s:Object=SkillPanelService.execute("snapshot",{v:1,view:"manage"});
        check(s.success && s.learned.length==6 && s.loadout.length==12,"existing manage protocol projects six native abilities");
        check(s.loadout[0].skillKey=="小跳" && s.loadout[7].skillKey==null,"default and empty positions");
        var result:Object=SkillPanelService.execute("moveSlot",{v:1,view:"manage",sourceSlot:1,targetSlot:8,expectedRevision:s.revision});
        check(result.success && result.changed && result.snapshot.loadout[7].skillKey=="小跳","existing drag command moves to slot eight");
        check(unit.__enemyActionRuntime.cooldowns===cooldowns && cooldowns.hop==500 && unit.__enemyActionRuntime.active===active,"rearrange preserves exact cooldown ledger and active move");
        check((unit.__enemyActionRuntime.inputMask & (1<<15)) != 0,"new slot participates in actual input mask");
        var mappings:Array=unit.__enemyActionRuntime.profile.inputs;var found:Boolean=false;
        for(var i:Number=0;i<mappings.length;i++) if(mappings[i].bit==(1<<15) && mappings[i].actionId=="hop") found=true;
        check(found && unit.__enemyActionRuntime.inputBlocked,"new mapping waits for release, no held-key accidental cast");
        check(SkillPanelService.execute("unequip",{v:1,view:"manage",slot:8,expectedRevision:s.revision}).error=="stale_state","old revision cannot undo new order");
        result=SkillPanelService.execute("equip",{v:1,view:"manage",skillKey:"冲腿·龙息",slot:12,expectedRevision:result.revision});
        check(result.success && result.snapshot.loadout[11].skillKey=="冲腿·龙息" && !EnemyActionRuntime.available(unit,"rush"),"unawakened move is rearrangeable without granting ability");
        unit.宠物属性.冲腿龙息=true;
        check(EnemyActionRuntime.hudAction(unit,12).name=="冲腿·龙息" && EnemyActionRuntime.available(unit,"rush"),"awakening keeps the selected slot");
        var beforeRevision:Number=result.revision;
        result=SkillPanelService.execute("unequip",{v:1,view:"manage",slot:8,expectedRevision:beforeRevision});
        check(result.success && result.snapshot.loadout[7].skillKey==null,"unequip uses existing skill page command");
        check(_root.主角技能表[0][0]=="保留主角技能" && _root.主角技能表[0][1]==9,"main-character skills untouched");
        check(run.leeLoadout[11]=="rush" && run.leeLoadout!==unit.__enemyActionRuntime.profile.quickSlots,"saved preference is an isolated scalar copy");
        check(SkillPanelService.execute("equip",{v:1,view:"manage",skillKey:"凭空招式",slot:1,expectedRevision:result.revision}).error=="skill_not_found","foreign ability rejected");
        check(SkillPanelService.execute("moveSlot",{v:1,view:"manage",sourceSlot:12,targetSlot:13,expectedRevision:result.revision}).error=="invalid_payload","out-of-range slot rejected");
        var restored:Array=LeeSkillLoadout.copySlots(run.leeLoadout);restored[0]="hop";
        check(run.leeLoadout[0]=="","restoring preference cannot alias origin save");
        var corrupt:Array=run.leeLoadout.concat();corrupt[0]=corrupt[1];
        check(LeeSkillLoadout.copySlots(corrupt)[0]=="hop","corrupt duplicate mapping restores a whole valid default");
        run.outcome="victory";
        check(SkillPanelService.execute("equip",{v:1,view:"manage",slot:1,skillKey:"寸拳",expectedRevision:result.revision}).error=="service_not_ready","ended run cannot fall through into hero skills");
        _root.gameworld=saved.world;_root._saveExt=saved.ext;_root.savePath=saved.slot;_root.控制目标=saved.control;
        _root.存档系统=saved.save;_root.等级=saved.level;_root.keyshow=saved.keyshow;_root.主角技能表=saved.table;_root.刷新技能栏显示=saved.refresh;
        var intel:Object={value:4,toObject:function():Object{return {黑龙令:this.value};}};
        var root:Object={收集品栏:{情报:intel},主角被动技能:{解密:{启用:true,等级:4}}};
        check(!BookshelfPanelService.leeStoryUnlocked(root),"fourth decrypt level stays locked");
        root.主角被动技能.解密.等级=5;check(BookshelfPanelService.leeStoryUnlocked(root),"complete intelligence plus fifth decrypt level unlocks");
        root.主角被动技能.解密.启用=false;check(!BookshelfPanelService.leeStoryUnlocked(root),"disabled passive stays locked");
        root.主角被动技能.解密.启用=true;intel.value=3;check(!BookshelfPanelService.leeStoryUnlocked(root),"incomplete intelligence stays locked at maximum skill");
        trace("LeeSkillLoadoutTest Tests Passed: "+passed);trace("LeeSkillLoadoutTest Tests Failed: "+failed);
    }
}
