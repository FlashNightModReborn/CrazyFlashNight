import org.flashNight.arki.component.Damage.*;
import org.flashNight.neur.InputCommand.*;
import org.flashNight.dev.*;

/** 产品域收束的旧/新差分：实际处理器组合、缓存、状态、三个模块的 DfaModuleData。 */
class org.flashNight.dev.ProductionDomainDebtTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean, name:String):Void {
        if (value) passed++; else { failed++; trace("[FAIL] ProductionDomainDebt " + name); }
    }
    private static function compareManagers(old:Object, next:Object, name:String):Void {
        var a:Array=old._handles;var b:Array=next._handles;
        check(a.length==b.length,name+" count");
        for(var i:Number=0;i<a.length;i++) check(a[i]===b[i],name+" ordered handler "+i);
    }
    private static function damage():Void {
        // 每次测试播放器是独立进程；本地注册表不访问存档。
        DamageManagerFactory.clearAllFactories();LegacyDamageManagerFactory.clearAllFactories();
        var oldBasic:Object=LegacyDamageManagerFactory.createBasic();
        var basic:Object=DamageManagerFactory.createBasic();
        var oldTerminal:Object=LegacyDamageManagerFactory.createActualTerminal();
        var terminal:Object=DamageManagerFactory.createActualTerminal();
        for(var mask:Number=0;mask<64;mask++) {
            var bullet:Object={暴击:(mask&1)?function():Number{return 1.5;}:null,
                flags:(mask&2)?2:0,nanoToxic:(mask&4)?5:0,吸血:(mask&8)?10:0,
                击溃:(mask&16)?4:0,斩杀:(mask&32)?20:0};
            var mgr:Object=basic.getDamageManager(bullet);
            compareManagers(oldBasic.getDamageManager(bullet),mgr,"Basic "+mask);
            check(mgr===basic.getDamageManager(bullet),"Basic cached identity "+mask);
            if(mask<4) compareManagers(oldTerminal.getDamageManager(bullet),terminal.getDamageManager(bullet),"Terminal "+mask);
        }
        // 保留缺省值/NaN 的原始 canHandle 行为，尤其吸血 undefined 的语义。
        var edges:Array=[{}, {吸血:null}, {吸血:Number.NaN}, {nanoToxic:-1,吸血:-1,击溃:-1,斩杀:-1}];
        for(var e:Number=0;e<edges.length;e++) compareManagers(oldBasic.getDamageManager(edges[e]),basic.getDamageManager(edges[e]),"edge "+e);
        var ref:Object=basic.getDamageManager({吸血:0});
        ref.update(0.5,"躲闪");ref.reset();
        check(ref.overlapRatio==1&&ref.dodgeState=="","manager reset");
        basic.resetFactory(null,null,false);check(ref===basic.getDamageManager({吸血:0}),"reset preserves cache when requested");
        basic.resetFactory(null,null,true);check(ref!==basic.getDamageManager({吸血:0}),"reset clears cache");
        var rejected:Boolean=false;
        try { new DamageManager(new Array(9)); } catch(error) { rejected=true; }
        check(rejected,"9-handler production manager rejected");
        var handlers:Array=[];
        for(var i:Number=0;i<8;i++) handlers.push(probeHandle(i));
        var oldProbe:Object=new LegacyDamageManagerFactory(handlers,64);
        var probe:Object=new DamageManagerFactory(handlers,64);
        var a:Object={selected:255,calls:[],executed:[]};
        var b:Object={selected:255,calls:[],executed:[]};
        var am:Object=oldProbe.getDamageManager(a);var bm:Object=probe.getDamageManager(b);
        check(a.calls.join(",")==b.calls.join(","),"canHandle order");
        am.execute(a,{}, {},new DamageResult());bm.execute(b,{}, {},new DamageResult());
        check(a.executed.join(",")==b.executed.join(","),"execute order");
        check(b.executed.join(",")=="0,1,2,3,4,5,6,7","all eight handlers executed");
        DamageHandlersTest.runTests(true);
        check(DamageHandlersTest.getFailedCount()==0,"existing handler behavior suite");
        DamageManagerTest.testBurstQueueContract();
    }
    private static function probeHandle(index:Number):Object {
        return {skipCheck:index==0,
            canHandle:function(bullet:Object):Boolean {bullet.calls.push(index);return (bullet.selected&(1<<index))!=0;},
            handleBulletDamage:function(bullet:Object):Void {bullet.executed.push(index);}};
    }
    private static function dfa():Void {
        var configs:Array=[CommandConfig.getBarehanded(),CommandConfig.getLightWeapon(),CommandConfig.getHeavyWeapon()];
        for(var module:Number=0;module<configs.length;module++) {
            var old:LegacyCommandRegistry=new LegacyCommandRegistry(64);
            var next:CommandRegistry=new CommandRegistry(64);
            old.loadConfig(configs[module]);next.loadConfig(configs[module]);old.compile();next.compile();
            check(old.serializeForLauncher()==next.serializeForLauncher(),"wire bytes module "+module);
            trace("DFA_WIRE "+module+" "+next.serializeForLauncher());
            var compiler:Object=next.getDFA();
            check(compiler.matchPositions==undefined&&compiler.matchPatternIds==undefined,"compiler no match buffers "+module);
            var matcher:Object=new CommandDFAMatcher(64,next.getDFA());
            var methods:Array=["update","updateFast","updateWithDynamicTimeout","updateWithHistory"];
            var frames:Array=[[InputEvent.DOWN_FORWARD],[InputEvent.A_PRESS],[],[InputEvent.FORWARD],[],[],[],[InputEvent.SHIFT_FORWARD]];
            for(var m:Number=0;m<methods.length;m++) {
                var unitA:Object={};var unitB:Object={};
                old.getDFA().resetUnit(unitA);matcher.resetUnit(unitB);
                for(var f:Number=0;f<96;f++) {
                    var events:Array=frames[f%frames.length];
                    var oldMatcher:Object=old.getDFA();
                    oldMatcher[methods[m]](unitA,events);matcher[methods[m]](unitB,events);
                    check(unitA.commandId==unitB.commandId&&unitA.commandState==unitB.commandState&&
                        unitA.lastCommandId==unitB.lastCommandId&&unitA.stepTimer==unitB.stepTimer&&
                        unitA.lastMatchEndPos==unitB.lastMatchEndPos,"matcher state "+module+"/"+m+"/"+f);
                }
            }
        }
        var suite:InputCommandTest=new InputCommandTest();suite.runTests();
        check(suite.getFailedCount()==0,"existing input command suite");
    }
    public static function runAllTests():Void {
        passed=0;failed=0;damage();dfa();
        trace("ProductionDomainDebtTest passed="+passed+" failed="+failed);
    }
}
