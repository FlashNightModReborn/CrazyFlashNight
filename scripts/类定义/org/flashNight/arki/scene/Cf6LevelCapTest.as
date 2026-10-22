import org.flashNight.arki.scene.BookRunService;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import org.flashNight.arki.component.Effect.EffectSystem;
import org.flashNight.arki.item.PlayerAssetTransaction;

/** 真正 include 经验引擎后的根函数回归；只替换存盘、动效与查找演员外围。 */
class org.flashNight.arki.scene.Cf6LevelCapTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var saved:Object;
    private static var present:Object;
    private static var keys:Array;
    private static var fixture:MovieClip;
    private static var saves:Number;
    private static var effects:Number;
    private static var refreshes:Number;
    private static var statRefreshes:Number;
    private static var oldFind:Function;
    private static var oldEffect:Function;
    private static var oldSave:Function;
    private static function check(value:Boolean,label:String):Void {
        if (value) passed++; else { failed++; trace("[FAIL] Cf6LevelCap: "+label); }
    }
    /** 模板必须在生产 #include 前调用，连生产赋值的根函数与等级常量一起恢复。 */
    public static function captureRoot():Void {
        keys=["最大等级","等级限制","根据等级得升级所需经验","根据等级计算获得技能点",
            "健身房主角是否升级","投影已提交任务成长","主角是否升级","经验值计算","宠物升级加载",
            "等级","经验值","技能点数","升级需要经验值","上次升级需要经验值","身价","基础身价值",
            "玩家信息界面","isChallengeMode","存档系统","出战宠物id库","宠物mc库","宠物信息",
            "战宠UI函数","宠物库","难度等级","_saveExt","savePath","当前关卡名","gameworld"];
        saved={}; present={};
        for (var i:Number=0;i<keys.length;i++) { saved[keys[i]]=_root[keys[i]]; present[keys[i]]=_root.hasOwnProperty(keys[i]); }
    }
    private static function setup(book:String, route:String, sameSlot:Boolean):Void {
        _root.gameworld=fixture;
        _root.savePath="bookrun_0123456789abcdef01234567";
        _root._saveExt=book=="" ? {} : {bookRun:{bookId:book,routeId:route,
            slot:sameSlot ? _root.savePath : "bookrun_ffffffffffffffffffffffff",outcome:"active"}};
        _root.当前关卡名=book=="cf6-sting" ? "书中历险-毒刺行动" : "fixture-other-stage";
        _root.等级=60; _root.经验值=157526193; _root.技能点数=0; _root.身价=600; _root.基础身价值=10;
        _root.存档系统={dirtyMark:false}; _root.出战宠物id库=[]; _root.宠物mc库=[]; _root.宠物信息=[];
        _root.宠物库=[]; _root.战宠UI函数={}; _root.难度等级=1;
        _root.isChallengeMode=function():Boolean { return false; };
        _root.玩家信息界面={主角经验值显示界面:{frame:0},刷新经验值显示:function():Void { refreshes++; },
            刷新hp显示:function():Void {},刷新mp显示:function():Void {}};
        fixture.hero.hp=100; fixture.hero.mp=30; fixture.hero.hp满血值=100; fixture.hero.mp满血值=30;
        fixture.hero.等级=60;
        fixture.hero.根据等级初始数值=function(level:Number):Void {
            statRefreshes++; this.hp满血值=level*10; this.mp满血值=level;
        };
        saves=0; effects=0; refreshes=0; statRefreshes=0;
    }
    private static function includedFunctions():Void {
        check(typeof _root.根据等级得升级所需经验=="function" && _root.根据等级得升级所需经验(59)==157526193,
            "production include supplies real level 59 cumulative XP formula");
        check(typeof _root.主角是否升级=="function" && typeof _root.健身房主角是否升级=="function"
            && typeof _root.经验值计算=="function","three production entry functions are installed");
        check(_root.最大等级==60 && _root.等级限制==100,"include retains ordinary global level ceiling 100");
    }
    private static function fixedSixty():Void {
        setup("cf6-sting","historical",true);
        check(BookRunService.playerLevelCapReached(),"exact CF6 historical slot is capped at 60");
        _root.经验值=1000000000000;
        _root.主角是否升级(_root.等级,_root.经验值);
        check(_root.等级==60 && _root.技能点数==0,"ordinary upgrade entry cannot exceed CF6 level 60 under high XP");
        check(_root.经验值==1000000000000,"upgrade lock does not rewrite existing XP");
        check(saves==0 && effects==0 && statRefreshes==0 && refreshes==0,"capped upgrade has no save, effect, healing or UI mutation");
        setup("cf6-sting","historical",true); _root.经验值=1000000000000;
        _root.健身房主角是否升级();
        check(_root.等级==60 && _root.技能点数==0,"gym entry cannot exceed CF6 level 60 under high XP");
        check(saves==0 && effects==0 && statRefreshes==0,"capped gym has no upgrade side effects");
        setup("cf6-sting","historical",true);
        _root.经验值计算(100,100,60,100);
        check(_root.经验值==157526193 && _root.等级==60,"real kill XP entry grants no player XP in capped CF6 run");
        check(_root.存档系统.dirtyMark===false && saves==0 && _root.技能点数==0,"capped player kill does not dirty or save player growth");
        _root.经验值=NaN; _root.经验值计算(100,100,60,100);
        check(isNaN(_root.经验值),"capped kill does not repair unknown XP by writing a new value");
        setup("cf6-sting","historical",true); _root.经验值=1000000000000;
        _root.主角是否升级(1,1000000000000);
        check(_root.等级==60 && saves==0,"caller-supplied stale level cannot bypass current-slot cap");
    }
    private static function loopBoundary():Void {
        setup("cf6-sting","historical",true); _root.等级=59; fixture.hero.等级=59; _root.经验值=1000000000000;
        check(!BookRunService.playerLevelCapReached(),"level 59 has not reached CF6 ceiling");
        _root.主角是否升级(59,_root.经验值);
        check(_root.等级==60 && _root.技能点数==80,"ordinary multi-level loop stops exactly at 60");
        check(saves==1 && effects==1 && statRefreshes==1 && fixture.hero.等级==60,"one allowed boundary upgrade projects and requests save once");
        setup("cf6-sting","historical",true); _root.等级=59; fixture.hero.等级=59; _root.经验值=1000000000000;
        _root.健身房主角是否升级();
        check(_root.等级==60 && _root.技能点数==80,"gym multi-level loop stops exactly at 60");
        check(saves==1 && effects==1 && statRefreshes==1,"gym boundary upgrade requests one projection/save");
    }
    private static function unaffected(book:String,label:String):Void {
        setup(book,"historical",true);
        check(!BookRunService.playerLevelCapReached(),label+" does not inherit CF6 cap");
        _root.经验值=_root.根据等级得升级所需经验(60);
        _root.主角是否升级(60,_root.经验值);
        check(_root.等级==61 && _root.技能点数==90,label+" ordinary upgrade retains 60-to-61 growth");
        check(saves==1 && effects==1 && fixture.hero.等级==61,label+" ordinary upgrade retains projection/save request");
        setup(book,"historical",true); _root.经验值=_root.根据等级得升级所需经验(60);
        _root.健身房主角是否升级();
        check(_root.等级==61 && _root.技能点数==90 && saves==1,label+" gym retains 60-to-61 growth");
        setup(book,"historical",true); var before:Number=_root.经验值;
        _root.经验值计算(100,100,60,100);
        check(_root.经验值==before+100 && _root.等级==60,label+" kill retains ordinary player XP calculation");
        check(_root.存档系统.dirtyMark===true && saves==0,label+" non-level-up kill marks dirty without strong save");
        setup(book,"historical",true); _root.经验值=_root.根据等级得升级所需经验(60)-50;
        _root.经验值计算(100,100,60,100);
        check(_root.等级==61 && _root.技能点数==90 && saves==1,label+" kill crossing threshold still levels via real upgrade entry");
    }
    private static function foreignIdentities():Void {
        setup("cf6-sting","historical",false);
        check(!BookRunService.playerLevelCapReached(),"stale run for a different slot does not impose cap");
        _root.经验值=_root.根据等级得升级所需经验(60); _root.主角是否升级(60,_root.经验值);
        check(_root.等级==61 && saves==1,"foreign-slot ordinary upgrade remains available");
        setup("cf6-sting","historical",false); var before:Number=_root.经验值;
        _root.经验值计算(100,100,60,100);
        check(_root.经验值==before+100 && _root.存档系统.dirtyMark===true,"foreign-slot kill XP remains available");
        setup("cf6-sting","plan61",true);
        check(!BookRunService.playerLevelCapReached(),"different route does not inherit historical cap");
        _root.经验值=_root.根据等级得升级所需经验(60); _root.健身房主角是否升级();
        check(_root.等级==61 && saves==1,"different-route gym growth remains available");
        setup("cf6-sting","plan61",true); before=_root.经验值; _root.经验值计算(100,100,60,100);
        check(_root.经验值==before+100 && _root.存档系统.dirtyMark===true,"different-route kill XP remains available");
        setup("cf6-sting","historical",true); var oldRun:Object=_root._saveExt.bookRun;
        _root._saveExt={}; _root.savePath="cf7_agent_level_cap_fixture";
        check(!BookRunService.playerLevelCapReached(),"departed run reference cannot cap restored ordinary character");
        _root.经验值=_root.根据等级得升级所需经验(60); _root.主角是否升级(60,_root.经验值);
        check(_root.等级==61 && oldRun.bookId=="cf6-sting","old detached identity does not participate in current root call");
    }
    private static function petIndependence():Void {
        setup("cf6-sting","historical",true);
        _root.出战宠物id库=[0]; _root.宠物mc库=[{hp:1,兵种:"fixture",等级:1}];
        _root.宠物信息=[[1,1,100,0,1,{宠物升级经验:0,宠物升级所需经验:1000}]];
        _root.经验值计算(100,100,60,100);
        check(_root.经验值==157526193 && _root.等级==60,"pet participation cannot bypass player cap");
        check(_root.宠物信息[0][5].宠物升级经验==100 && _root.存档系统.dirtyMark===true,
            "existing independent pet XP behavior survives player cap");
        check(saves==0,"pet-only non-level-up growth has no player strong-save request");
    }
    private static function restore():Void {
        fixture.removeMovieClip();
        var target:Object=TargetCacheManager,effect:Object=EffectSystem,transaction:Object=PlayerAssetTransaction;
        target.findHero=oldFind; effect.Effect=oldEffect; transaction.requestStrongSave=oldSave;
        for (var i:Number=0;i<keys.length;i++) {
            if (present[keys[i]]) _root[keys[i]]=saved[keys[i]]; else delete _root[keys[i]];
        }
    }
    public static function runAllTests():Void {
        passed=0; failed=0;
        if (saved==null) { trace("[FAIL] Cf6LevelCap captureRoot must precede include"); trace("Cf6LevelCapTest Tests Passed: 0"); trace("Cf6LevelCapTest Tests Failed: 1"); return; }
        var target:Object=TargetCacheManager,effect:Object=EffectSystem,transaction:Object=PlayerAssetTransaction;
        oldFind=target.findHero; oldEffect=effect.Effect; oldSave=transaction.requestStrongSave;
        fixture=_root.createEmptyMovieClip("__cf6LevelCapFixture",_root.getNextHighestDepth());
        fixture.createEmptyMovieClip("hero",1);
        target.findHero=function():MovieClip { return fixture.hero; };
        effect.Effect=function():MovieClip { effects++; return undefined; };
        transaction.requestStrongSave=function():Void { saves++; };
        try { includedFunctions(); fixedSixty(); loopBoundary(); unaffected("repair-campus","campus");
            unaffected("lee-trial","Lee trial"); unaffected("","ordinary character"); foreignIdentities(); petIndependence(); }
        finally { restore(); }
        var restored:Boolean=true;
        for (var i:Number=0;i<keys.length;i++) {
            if (_root.hasOwnProperty(keys[i]) !== present[keys[i]]) restored=false;
            if (present[keys[i]] && _root[keys[i]] !== saved[keys[i]]) restored=false;
        }
        check(restored,"fixture restores exact root values and original property presence after production include");
        check(target.findHero===oldFind && effect.Effect===oldEffect && transaction.requestStrongSave===oldSave,
            "fixture restores all three overridden class functions");
        saved=null;
        trace("Cf6LevelCapTest Tests Passed: "+passed);
        trace("Cf6LevelCapTest Tests Failed: "+failed);
    }
}
