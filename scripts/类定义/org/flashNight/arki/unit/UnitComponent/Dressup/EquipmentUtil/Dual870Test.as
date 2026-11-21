import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.equipment.EquipmentCalculator;
import org.flashNight.arki.item.equipment.EquipmentConfigManager;
import org.flashNight.arki.item.equipment.ModRegistry;
import org.flashNight.arki.item.equipment.TagManager;
import org.flashNight.arki.unit.Action.Skill.ManualCooldownService;
import org.flashNight.arki.unit.Action.Skill.WeaponSkillInputService;
import org.flashNight.arki.unit.Action.Shoot.ShootCore;
import org.flashNight.arki.unit.Action.Shoot.ShootInitCore;
import org.flashNight.arki.unit.Action.Shoot.WeaponFireCore;
import org.flashNight.arki.unit.Action.Shoot.WeaponAmmoRuntime;
import org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer;
import org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.FireEventComponent;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.Dual870Controller;
import org.flashNight.arki.bullet.BulletComponent.Type.BulletTypesetter;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.gesh.xml.XMLParser;
import org.flashNight.neur.Event.EventDispatcher;

class org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.Dual870Test {
    private static var passed:Number = 0;
    private static var failed:Number = 0;
    private static var guns:Object = {};
    private static var pressed:Boolean = false;
    private static var rounds:Array = [];
    private static var dual:String = "雷明登870双态型";
    private static var slug:String = "独头弹";

    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++;
        else { failed++; trace("[FAIL] Dual870Test " + label); }
    }

    public static function runAllTests():Void {
        loadXml("武器_长枪_霰弹枪.xml", function(root:Object):Void {
            var items:Array = XMLParser.configureDataAsArray(root.item);
            for (var i:Number = 0; i < items.length; i++) Dual870Test.guns[items[i].name] = items[i];
            Dual870Test.loadXml("equipment_mods/中等材料_枪械专用.xml", function(modRoot:Object):Void {
                var firearmMods:Array = XMLParser.configureDataAsArray(modRoot.mod);
                Dual870Test.loadXml("equipment_mods/低级材料_通用.xml", function(universal:Object):Void {
                    Dual870Test.exercise(firearmMods.concat(XMLParser.configureDataAsArray(universal.mod)));
                });
            });
        });
    }

    private static function loadXml(file:String, callback:Function):Void {
        var xml:XML = new XML();
        xml.ignoreWhite = true;
        xml.onLoad = function(ok:Boolean):Void {
            Dual870Test.check(ok, "load " + file);
            if (!ok) { Dual870Test.finish(); return; }
            callback(XMLParser.parseXMLNode(this.firstChild));
        };
        xml.load("../data/items/" + file);
    }

    private static function exercise(mods:Array):Void {
        var oldMods:Array = ModRegistry.getModList();
        var oldItems:Object = ItemUtil.itemDataDict;
        var oldEquipment:Object = ItemUtil.equipmentDict;
        var keys:Array = ["gameworld","帧计时器","暂停","按键输入检测","子弹区域shoot传递","控制目标",
            "全局健身HP加成","全局健身MP加成","全局健身空攻加成","全局健身防御加成","全局健身内力加成",
            "经脉HP加成","经脉MP加成","经脉防御加成","经脉内力加成","敌人函数"];
        var before:Object = {};
        for (var i:Number = 0; i < keys.length; i++) before[keys[i]] = _root[keys[i]];
        var world:MovieClip = _root.createEmptyMovieClip("dual870World", _root.getNextHighestDepth());
        try {
            ItemUtil.itemDataDict = guns;
            ItemUtil.equipmentDict = {};
            for (var name:String in guns) ItemUtil.equipmentDict[name] = true;
            mods.push({name:"fixturePower", stats:{flat:{power:10,split:2}}});
            ModRegistry.loadModData(mods);
            checkPanels();
            _root.gameworld = world;
            _root.帧计时器 = {当前帧数:10};
            _root.暂停 = false;
            _root.按键输入检测 = function():Boolean { return Dual870Test.pressed; };
            _root.控制目标 = "other";
            for (i = 6; i < keys.length - 1; i++) _root[keys[i]] = 0;
            _root.敌人函数 = {魔法伤害种类:["基础","能","热","冷"]};
            _root.子弹区域shoot传递 = function(prop:Object):Void {
                BulletTypesetter.setTypeFlags(prop);
                Dual870Test.rounds.push({bullet:prop.子弹种类,split:prop.霰弹值,power:prop.子弹威力,speed:prop.子弹速度,flags:prop.flags});
            };
            ManualCooldownService.setSchedulerForTests(function():Void {});
            checkCombat(world.createEmptyMovieClip("shooter",1));
        } catch (error) { check(false, "exception " + error); }
        finally {
            ManualCooldownService.resetForTests();
            ItemUtil.itemDataDict = oldItems;
            ItemUtil.equipmentDict = oldEquipment;
            ModRegistry.loadModData(oldMods || []);
            for (i = 0; i < keys.length; i++) _root[keys[i]] = before[keys[i]];
            world.removeMovieClip();
        }
        finish();
    }

    private static function checkPanels():Void {
        var host:BaseItem = new BaseItem("雷明登870警用型",{level:1,mods:[]});
        var rifle:BaseItem = new BaseItem(dual,{level:1,mods:[]});
        check(TagManager.checkModAvailability(host,host.getData(),slug) == 1, "compatible host installs");
        check(TagManager.checkModAvailability(rifle,rifle.getData(),slug) < 0, "integral ammo slot");
        check(rifle.getData().skill == undefined && TagManager.checkModAvailability(rifle,rifle.getData(),"骨芯颅印") == 1,
            "bare 870 leaves the active weapon skill slot available");
        rifle.value.mods = ["骨芯颅印"];
        check(rifle.getData().skill.skillname == "滑步", "installed attachment owns the F skill");
        var special:BaseItem = new BaseItem("SPAS12战术版",{level:1,mods:[]});
        check(TagManager.checkModAvailability(special,special.getData(),slug) < 0, "reject explosive single");
        host.value.mods = ["八门金锁镇暴弹"];
        check(TagManager.checkModAvailability(host,host.getData(),slug) < 0, "ammo slot conflict");
        host.value.mods = [slug];
        var d:Object = host.getData().data;
        check(d.power == 1120 && d.split == 1 && d.bullet == "巴雷特子弹", "eight into one");
        check(d.velocity == 80, "slug attachment has the Barrett base velocity");
        host.value.mods = [slug,"霰弹枪口收束器"];
        check(host.getData().data.velocity == 92, "existing +15% muzzle still applies to slug speed");
        host.value.mods.reverse();
        check(host.getData().data.velocity == 92, "speed unaffected by installation order");
        host.value.mods = [];
        check(host.getData().data.velocity == 30, "uninstall restores buckshot velocity");
        check(host.getData().data.power == 560 && host.getData().data.split == 8, "uninstall restores");
        var fast:BaseItem = new BaseItem("雷明登870急速型",{level:1,mods:[slug]});
        check(fast.getData().data.power == 500, "four pellets yield the original single-pellet power");
        check(fast.getData().data.velocity == 80, "45-speed host uses the same slug speed");
        var slow:BaseItem = new BaseItem("雷明登870",{level:1,mods:[slug]});
        check(slow.getData().data.velocity == 80, "15-speed host reaches the same baseline");
        var many:BaseItem = new BaseItem("DBHshotgun",{level:1,mods:[slug]});
        check(many.getData().data.power == 356, "round 95 x 15 / 4 on the base panel");
        var three:BaseItem = new BaseItem("ZUX197",{level:1,mods:[slug]});
        check(three.getData().data.power == 900, "three pellets convert below the original single-pellet power");
        host.value.level = 3;
        var expected:Number = Math.round(1120 * EquipmentConfigManager.getLevelMultiplier(3)) + 10;
        host.value.mods = [slug,"fixturePower"];
        check(host.getData().data.power == expected && host.getData().data.split == 1, "level and fixed power apply after folding original pellets");
        host.value.mods.reverse();
        check(host.getData().data.power == expected, "installation order independent");
        rifle.value = {level:3,mods:["fixturePower"],slugMode:true};
        check(rifle.getData().data.power == expected, "native and attachment share final stat");
        rifle.value.mods = ["强化金属管","fixturePower"];
        var barrelPower:Number = Math.round(1120 * (EquipmentConfigManager.getLevelMultiplier(3) + 0.07)) + 10;
        check(rifle.getData().data.power == barrelPower && rifle.getData().data.split == 1, "normal barrel percentage and flat apply to the slug base");
        rifle.value.mods = ["霰弹枪口收束器","骨芯颅印"];
        check(rifle.getData().data.velocity == 92 && rifle.getData().skill.skillname == "滑步", "native fast slug keeps muzzle and skill");
        var tierGun:Object = ObjectUtil.clone(guns["雷明登870警用型"]);
        tierGun.data_test = {split:3,power:305,velocity:100};
        var cfg:Object = {tierNameToKeyDict:{选档:"data_test"},defaultTierDataDict:{},levelStatList:[1,1]};
        var tier:Object = EquipmentCalculator.calculatePure(tierGun,{level:1,tier:"选档",mods:[slug]},cfg,ModRegistry.getModDict());
        check(tier.data.power == 229 && tier.data.split == 1, "tier count before conversion");
        check(tier.data.velocity == 100, "already-faster tier retains its base velocity");
    }

    private static function checkCombat(u:MovieClip):Void {
        u.version = 1; u.hp = 600; u.hp满血值 = u.hp基本满血值 = 1000;
        u.mp = 200; u.mp满血值 = u.mp基本满血值 = 500;
        u.等级 = 20; u.基本空手攻击力 = u.基本防御力 = 100; u.体重 = 50;
        u.基础命中率 = u.基础躲闪率 = 10; u.基础韧性系数 = 1;
        u.label = {}; u.魔法抗性 = {}; u.area = {_height:136};
        u.攻击模式 = "长枪"; u.状态 = "长枪站立"; u.根据模式重新读取武器加成 = function():Void {};
        u.被动技能 = {枪械攻击:{启用:true,等级:1}}; u.dispatcher = new EventDispatcher();
        var slots:Array = ["头部装备","上装装备","手部装备","下装装备","脚部装备","颈部装备","长枪","手枪","手枪2","刀","手雷"];
        var gun:BaseItem = new BaseItem(dual,{level:1,mods:["骨芯颅印"],shot:2});
        var load:Function = function(t:Object,k:String):Object { return k == "长枪" ? gun : null; };
        for (var i:Number = 0; i < slots.length; i++) DressupInitializer.loadEquipmentData(u,slots[i],load,1);
        RuntimeEquipmentProjection.beginCanonical(u);
        RuntimeEquipmentProjection.completeCanonical(u);
        u.长枪弹匣容量 = 5;
        u.man = u.createEmptyMovieClip("man",1); u.man.射击许可标签 = true;
        u.man.是否单发 = true; u.man.prepareStandardShotPose = function():Void {};
        var holder:MovieClip = u.man.createEmptyMovieClip("枪",1).createEmptyMovieClip("枪",1);
        var skin:MovieClip = holder.createEmptyMovieClip("装扮",1); u.长枪_引用 = skin;
        skin.createEmptyMovieClip("枪口位置",1);
        u.长枪射击 = WeaponFireCore.LONG_GUN_SHOOT;
        u.enableShoot = true; FireEventComponent.initialize(u); u.动作A = true;
        var state:Object = WeaponAmmoRuntime.ensure(u,"长枪");
        state.reserve = 4;
        u.man.子弹属性 = ShootInitCore.generateBulletProps(u,"长枪",u.长枪属性,{});
        var releases:Number = 0;
        u.主动战技 = {长枪:{名字:u.长枪数据.skill.skillname,冷却时间:u.长枪数据.skill.cd}};
        u.释放主动战技 = function():Boolean { releases++; return true; };
        var ref:Object = {自机:u,版本号:1,是否为主角:true,生命周期函数列表:[]};
        _root.装备生命周期函数.双态870初始化(ref);
        shot(u);
        check(rounds[0].split == 8 && (rounds[0].flags & 2) != 0 && gun.value.shot == 3, "scatter shot spends one");
        check(rounds[0].speed == 30, "buckshot fired at the original speed");
        check(ManualCooldownService.isReady(ManualCooldownService.WEAPON_SKILL_KEY), "F is initially ready");
        var oldTemplate:Object = u.man.子弹属性;
        pressed = true;
        _root.装备生命周期函数.双态870周期(ref);
        check(gun.value.slugMode === true && ref.remaining > 0 && gun.value.shot == 3, "Q sets target during transition");
        check(releases == 0 && ManualCooldownService.isReady(ManualCooldownService.WEAPON_SKILL_KEY),
            "Q does not use the attached skill or start the shared cooldown");
        check(u.长枪 === gun && gun.value.ammoState === state && state.reserve == 4, "same tube and paid reserve");
        check(u.man.子弹属性 !== oldTemplate && u.长枪_装扮 == "枪-长枪-雷明登870急速型", "target body and fresh firing template");
        check(gun.getData().icon == "雷明登870急速型" && u.长枪数据.data.power == 1120, "instance panel and icon");
        shot(u);
        check(rounds[1].bullet == "巴雷特子弹" && rounds[1].split == 1 && (rounds[1].flags & 2) == 0, "mid-transition slug clears chain flag");
        check(rounds[1].speed == 80 && u.长枪属性.velocity == 80, "live slug reaches 80 on the first shot");
        check(Math.abs(rounds[1].power - (1120 * 1.53 + 30)) < 0.01, "passive flat added once");
        check(ref.remaining == 0 && gun.value.shot == 4 && state.reserve == 4, "fire finishes transition and consumes one");
        _root.帧计时器.当前帧数++;
        _root.装备生命周期函数.双态870周期(ref);
        check(gun.value.slugMode === true, "held Q does not toggle again");
        var restored:BaseItem = BaseItem.createFromObject({name:dual,value:ObjectUtil.clone(gun.value),lastUpdate:gun.lastUpdate});
        check(restored.getData().data.power == 1120 && restored.value.shot == 4, "saved mode and magazine restore");
        pressed = false; _root.帧计时器.当前帧数++; Dual870Controller.tick(ref);
        var f:Object = WeaponSkillInputService.updateUnit(u,true,true,null,_root.帧计时器.当前帧数);
        check(f.released && f.skill.名字 == "滑步" && releases == 1 && gun.value.slugMode === true,
            "F releases its own skill and preserves the slug form");
        check(!ManualCooldownService.isReady(ManualCooldownService.WEAPON_SKILL_KEY), "F has its normal cooldown");
        pressed = true; _root.帧计时器.当前帧数++;
        shot(u); // Q before next equipment tick
        check(rounds[2].bullet == "横向联弹-普通子弹" && rounds[2].split == 8 && gun.value.shot == 5, "same-frame reverse and last round");
        check(rounds[2].speed == 30 && releases == 1 && !ManualCooldownService.isReady(ManualCooldownService.WEAPON_SKILL_KEY),
            "Q restores scatter velocity while F is cooling down");
        check(gun.getData().data.power == 560 && u.长枪_装扮 == "枪-长枪-雷明登870警用型", "return restores panel and body");
        shot(u);
        check(rounds.length == 3 && state.reserve == 4, "empty tube rejects free shot");
        Dual870Controller.dispose(ref);
        check(!Dual870Controller.canSwitch(u), "disposed weapon cannot switch");
    }

    private static function shot(u:MovieClip):Void {
        ShootCore.continuousShoot(u,"长枪",1500,ShootCore.primaryParams,1500,true);
    }

    private static function finish():Void {
        trace("Dual870Test Tests Passed: " + passed);
        trace("Dual870Test Tests Failed: " + failed);
        _root.dual870Complete();
    }
}
