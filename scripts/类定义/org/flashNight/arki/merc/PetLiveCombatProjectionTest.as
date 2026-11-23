import LiteJSON;
import org.flashNight.arki.merc.PetPanelService;
import org.flashNight.arki.unit.PlayerInfoProvider;
import org.flashNight.arki.unit.PlayerStatRefreshCoordinator;

class org.flashNight.arki.merc.PetLiveCombatProjectionTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;

    private static function check(cond:Boolean, label:String):Void {
        if (cond) {
            passed++;
            trace("[PASS] " + label);
        } else {
            failed++;
            trace("[FAIL] " + label);
        }
    }

    private static function makeReadyUnit(
        world:Object,
        name:String,
        slotIndex:Number,
        petId:Number,
        identifier:String,
        level:Number,
        hp:Number,
        maxHp:Number,
        unarmed:Number,
        defense:Number,
        walkSpeed:Number,
        hasDressup:Boolean
    ):Object {
        var u:Object = {
            _name: name,
            _parent: world,
            兵种: identifier,
            等级: level,
            hp: hp,
            hp满血值: maxHp,
            空手攻击力: unarmed,
            防御力: defense,
            行走X速度: walkSpeed,
            version: 1,
            __unitInitializedVersion: 1,
            dispatcher: { publish: function():Void {} },
            aabbCollider: {},
            unitAI: {},
            shield: {},
            宠物属性: {
                宠物库数组号: petId,
                宠物信息数组号: slotIndex
            }
        };
        if (hasDressup) {
            u.hasDressup = true;
            u.mp = 0;
            u.mp满血值 = 0;
            u.装载生命周期函数 = function():Void {};
            u.完成生命周期函数装载 = function():Void {};
            u.生命周期函数列表 = [];
        }
        world[name] = u;
        return u;
    }

    public static function runAllTests():Void {
        passed = 0;
        failed = 0;

        var oldWorld = _root.gameworld;
        var oldPetUnits = _root.宠物mc库;
        var oldDeployedIds = _root.出战宠物id库;
        var oldPetInfo = _root.宠物信息;
        var oldPetLib = _root.宠物库;
        var oldEnemyTable = _root.敌人属性表;
        var oldAdvFns = _root.战宠进阶函数;
        var oldLevelLimit = _root.等级限制;
        var oldLevel = _root.等级;
        var oldMoney = _root.金钱;
        var oldKpoint = _root.虚拟币;
        var oldSave = _root.存档系统;
        var oldServer = _root.server;
        var oldSpawn = _root.加载游戏世界人物;
        var oldDeferred = _root.战宠UI函数 != undefined ? _root.战宠UI函数._宠物刷新待处理 : undefined;
        var oldCombatMap = _root.当前为战斗地图;
        var oldDifficulty = _root.难度等级;
        var oldPetLimit = _root.宠物领养限制;
        var oldCalcXp = _root.战宠UI函数 != undefined ? _root.战宠UI函数.计算战宠升级所需经验 : undefined;

        var coordinator:Object = PlayerStatRefreshCoordinator.production();
        var oldFlush:Function = coordinator.flush;
        var flushCalls:Number = 0;
        var spawnCalls:Number = 0;
        var promoExecCalls:Number = 0;

        try {
            if (_root.战宠UI函数 == undefined) _root.战宠UI函数 = {};
            _root.战宠UI函数._宠物刷新待处理 = {};
            _root.战宠UI函数.计算战宠升级所需经验 = function(kind:String, lv:Number):Number { return 1000 * lv; };
            _root.等级限制 = 100;
            _root.等级 = 60;
            _root.金钱 = 88888;
            _root.虚拟币 = 123;
            _root.宠物领养限制 = 12;
            _root.当前为战斗地图 = false;
            _root.难度等级 = 1;
            _root.存档系统 = { dirtyMark: false };
            _root.加载游戏世界人物 = function():Object {
                spawnCalls++;
                return null;
            };
            coordinator.flush = function():Object {
                flushCalls++;
                return null;
            };

            // 故意给敌人属性表塞旧武装JK小区间与负起点，验证新投影完全不被通用表污染
            var enemyTable:Object = {};
            enemyTable["敌人-僵尸1-狗"] = { hp_min: 100, hp_max: 500, 空手攻击力_min: 5, 空手攻击力_max: 20, 基本防御力_min: 10, 基本防御力_max: 50, 速度_min: 20, 速度_max: 40 };
            enemyTable["敌人-武装JK"] = { hp_min: -83, hp_max: 6000, 空手攻击力_min: -6, 空手攻击力_max: 1000, 基本防御力_min: 10, 基本防御力_max: 50, 速度_min: 30, 速度_max: 70 };
            _root.敌人属性表 = enemyTable;
            _root.战宠进阶函数 = {
                基础训练: {
                    次数上限: 1,
                    消耗金币: 1000,
                    解锁等级: 1,
                    描述: "基础训练",
                    执行: function():Void { promoExecCalls++; },
                    单位进阶执行: function():Void { promoExecCalls++; }
                }
            };
            _root.宠物库 = [];
            _root.宠物库[0] = { Name: "狗狗", Identifier: "敌人-僵尸1-狗", Height: 175, Promotion: { Item: "基础训练" } };
            _root.宠物库[78] = { Name: "武装JK", Identifier: "敌人-武装JK", Height: 160, Promotion: undefined };
            _root.宠物库[66] = { Name: "终结者T800", Identifier: "敌人-终结者T800", Height: 185, Promotion: { Item: "基础训练" } };

            var world:Object = {};
            _root.gameworld = world;

            var dogUnit:Object = makeReadyUnit(world, "宠物0敌人-僵尸1-狗", 0, 0, "敌人-僵尸1-狗", 20, 412.8, 980.9, 74.6, 132.7, 4.35, false);
            var jkUnit:Object = makeReadyUnit(world, "宠物1敌人-武装JK", 1, 78, "敌人-武装JK", 100, 1850420.9, 3770762.5, 2480.4, 1119.8, 5.82, false);
            var t800Unit:Object = makeReadyUnit(world, "宠物2敌人-终结者T800", 2, 66, "敌人-终结者T800", 55, 19500.2, 24000.9, 360.8, 720.4, 4.10, true);
            _root.宠物mc库 = [dogUnit, jkUnit, t800Unit];
            _root.出战宠物id库 = [0, 1, 2];

            // 1. 普通战宠 oracle 对照
            var dogRef = dogUnit;
            var dogProj:Object = PetPanelService.buildLiveCombatStats(0, 0, "敌人-僵尸1-狗", 20, true);
            check(dogProj.status == "ready"
                    && dogProj.hp == Math.floor(dogUnit.hp)
                    && dogProj.maxHp == Math.floor(PlayerInfoProvider.getMaxHP(dogRef))
                    && dogProj.unarmedAttack == Math.floor(PlayerInfoProvider.getUnarmedAttack(dogRef))
                    && dogProj.defense == PlayerInfoProvider.getTotalDefense(dogRef)
                    && dogProj.speed == PlayerInfoProvider.getMovementSpeedValue(dogRef)
                    && dogProj.speed == 8.7 && dogProj.speedUnit == "m/s",
                "普通战宠实时投影与 ready 实例和 PlayerInfoProvider 口径逐项一致");

            // 2. 武装 JK (>=50 级特殊成长路径) oracle 对照
            var jkProj:Object = PetPanelService.buildLiveCombatStats(1, 78, "敌人-武装JK", 100, true);
            check(jkProj.status == "ready"
                    && jkProj.hp == 1850420 && jkProj.maxHp == 3770762
                    && jkProj.unarmedAttack == 2480 && jkProj.defense == 1119
                    && jkProj.speed == 11.6 && jkProj.speedUnit == "m/s",
                "武装 JK 100 级真实实例投影精确一致且不被敌人属性表污染");

            // 3. 进阶/装扮型战宠 (hasDressup=true, 合法 0/0 MP) oracle 对照
            var t800Proj:Object = PetPanelService.buildLiveCombatStats(2, 66, "敌人-终结者T800", 55, true);
            check(t800Proj.status == "ready"
                    && t800Proj.hp == 19500 && t800Proj.maxHp == 24000
                    && t800Proj.unarmedAttack == 360 && t800Proj.defense == 720
                    && t800Proj.speed == 8.2 && t800Proj.speedUnit == "m/s",
                "装扮型进阶战宠 (hasDressup) 实时投影精确一致");

            // 4. handleSnapshot 端到端 wire 协议 + 无旧 combat + 顶层 levelLimit
            PetPanelService.install();
            _root.宠物信息 = [
                [0, 20, 180, 0, 1, { 基础训练: { 次数: 1 } }],
                [78, 100, 200, 0, 1, {}],
                [66, 55, 160, 0, 1, { 基础训练: { 次数: 1 } }],
                [78, 60, 200, 0, 0, {}]
            ];
            var rawPayload:String = "";
            _root.server = {
                sendSocketMessage: function(s:String):Boolean {
                    rawPayload = s;
                    return true;
                }
            };
            PetPanelService.handleSnapshot({ callId: "live_snap_1" });
            var codec:LiteJSON = new LiteJSON();
            var parsed:Object = codec.parse(rawPayload);
            check(parsed != null && parsed.success === true
                    && parsed.snapshot.levelLimit == 100
                    && parsed.snapshot.pets.length == 4
                    && parsed.snapshot.pets[0].combat == undefined
                    && parsed.snapshot.pets[1].combat == undefined
                    && parsed.snapshot.pets[1].liveCombat.status == "ready"
                    && parsed.snapshot.pets[1].liveCombat.maxHp == 3770762
                    && parsed.snapshot.pets[3].liveCombat.status == "not_deployed"
                    && parsed.snapshot.pets[3].liveCombat.maxHp == undefined,
                "handleSnapshot 输出纯 liveCombat + levelLimit，彻底移除旧 combat 三点结构");

            // 5. 未出战即便宠物mc库残留该 slot 实例也不复用旧 live 值
            var restProj:Object = PetPanelService.buildLiveCombatStats(1, 78, "敌人-武装JK", 100, false);
            check(restProj.status == "not_deployed" && restProj.hp == undefined && restProj.maxHp == undefined,
                "未出战战宠返回 not_deployed 且绝不复用残留 MC 数值");

            // 6. 已出战但场上无实例（阵亡移除/换图/禁同行）
            var missingProj:Object = PetPanelService.buildLiveCombatStats(5, 78, "敌人-武装JK", 60, true);
            check(missingProj.status == "unavailable" && missingProj.reason == "instance_missing",
                "已出战但无场景实例返回 unavailable/instance_missing");

            // 7. attachMovie 同步栈后尚未执行第 0 帧 (deferred init)
            var deferredUnit:Object = makeReadyUnit(world, "宠物6敌人-武装JK", 6, 78, "敌人-武装JK", 60, 100, 100, 10, 10, 4, false);
            delete deferredUnit.__unitInitializedVersion;
            _root.宠物mc库.push(deferredUnit);
            var defProj:Object = PetPanelService.buildLiveCombatStats(6, 78, "敌人-武装JK", 60, true);
            check(defProj.status == "pending" && defProj.reason == "initializing",
                "attachMovie 未进入第 0 帧 (__unitInitializedVersion=undefined) 返回 pending/initializing");

            // 8. StaticInitializer 进行中 (null) 与 version 失配
            deferredUnit.__unitInitializedVersion = null;
            var nullInitProj:Object = PetPanelService.buildLiveCombatStats(6, 78, "敌人-武装JK", 60, true);
            deferredUnit.__unitInitializedVersion = 0;
            var mismatchVerProj:Object = PetPanelService.buildLiveCombatStats(6, 78, "敌人-武装JK", 60, true);
            check(nullInitProj.status == "pending" && nullInitProj.reason == "initializing"
                    && mismatchVerProj.status == "unavailable" && mismatchVerProj.reason == "not_ready",
                "初始化中返回 pending/initializing，版本闩锁失配返回 unavailable/not_ready");

            // 9. 重建失败 refreshDeferred 时即使旧 ready MC 仍在场上也绝不返回旧数值
            _root.战宠UI函数._宠物刷新待处理[1] = { reason: "level_up", level: 100 };
            var refreshDefProj:Object = PetPanelService.buildLiveCombatStats(1, 78, "敌人-武装JK", 100, true);
            delete _root.战宠UI函数._宠物刷新待处理[1];
            check(refreshDefProj.status == "pending" && refreshDefProj.reason == "refresh_deferred"
                    && refreshDefProj.maxHp == undefined,
                "refreshDeferred 标记存在时拦截残留旧实例并返回 pending/refresh_deferred");

            // 10. 升级后等级与实例失配
            var lvMismatchProj:Object = PetPanelService.buildLiveCombatStats(1, 78, "敌人-武装JK", 101, true);
            check(lvMismatchProj.status == "unavailable" && lvMismatchProj.reason == "level_mismatch",
                "升级后实例等级失配返回 unavailable/level_mismatch");

            // 11. 槽位复用 / 换形态身份失配（兵种或 petId 不一致）
            var kindMismatchProj:Object = PetPanelService.buildLiveCombatStats(0, 0, "敌人-制式军警犬", 20, true);
            var idMismatchProj:Object = PetPanelService.buildLiveCombatStats(0, 78, "敌人-僵尸1-狗", 20, true);
            check(kindMismatchProj.status == "unavailable" && kindMismatchProj.reason == "identity_mismatch"
                    && idMismatchProj.status == "unavailable" && idMismatchProj.reason == "identity_mismatch",
                "兵种切换或槽位复用身份失配返回 unavailable/identity_mismatch");

            // 12. 脱离 gameworld / 残旧引用
            var detachedWorld:Object = {};
            var detachedUnit:Object = makeReadyUnit(detachedWorld, "宠物7敌人-武装JK", 7, 78, "敌人-武装JK", 60, 100, 100, 10, 10, 4, false);
            _root.宠物mc库.push(detachedUnit);
            var detachedProj:Object = PetPanelService.buildLiveCombatStats(7, 78, "敌人-武装JK", 60, true);
            var orphanUnit:Object = makeReadyUnit(world, "宠物8敌人-武装JK", 8, 78, "敌人-武装JK", 60, 100, 100, 10, 10, 4, false);
            delete world["宠物8敌人-武装JK"];
            _root.宠物mc库.push(orphanUnit);
            var orphanProj:Object = PetPanelService.buildLiveCombatStats(8, 78, "敌人-武装JK", 60, true);
            check(detachedProj.status == "unavailable" && detachedProj.reason == "instance_missing"
                    && orphanProj.status == "unavailable" && orphanProj.reason == "instance_missing",
                "非当前 gameworld 与已脱名孤儿引用 fail-closed 为 unavailable");

            // 13. 同 slot 双实例冲突
            var dupUnit:Object = makeReadyUnit(world, "宠物1敌人-武装JK__dup", 1, 78, "敌人-武装JK", 100, 100, 200, 10, 10, 4, false);
            _root.宠物mc库.push(dupUnit);
            var dupProj:Object = PetPanelService.buildLiveCombatStats(1, 78, "敌人-武装JK", 100, true);
            _root.宠物mc库.pop();
            delete world["宠物1敌人-武装JK__dup"];
            check(dupProj.status == "unavailable" && dupProj.reason == "ambiguous_instance",
                "同 slot 出现双实例时 fail-closed 返回 ambiguous_instance");

            // 14. 非有限/损坏/布尔伪装字段全部 fail-closed
            var badUnit:Object = makeReadyUnit(world, "宠物9敌人-武装JK", 9, 78, "敌人-武装JK", 60, 100, 200, 50, 80, 4, false);
            _root.宠物mc库.push(badUnit);
            badUnit.hp = NaN;
            var nanHp:Object = PetPanelService.buildLiveCombatStats(9, 78, "敌人-武装JK", 60, true);
            badUnit.hp = 100; badUnit.防御力 = Infinity;
            var infDef:Object = PetPanelService.buildLiveCombatStats(9, 78, "敌人-武装JK", 60, true);
            badUnit.防御力 = 80; badUnit.空手攻击力 = undefined;
            var undefAtk:Object = PetPanelService.buildLiveCombatStats(9, 78, "敌人-武装JK", 60, true);
            badUnit.空手攻击力 = 50; badUnit.行走X速度 = -1;
            var negSpd:Object = PetPanelService.buildLiveCombatStats(9, 78, "敌人-武装JK", 60, true);
            badUnit.行走X速度 = 4; badUnit.空手攻击力 = true;
            var boolAtk:Object = PetPanelService.buildLiveCombatStats(9, 78, "敌人-武装JK", 60, true);
            check(nanHp.status == "unavailable"
                    && infDef.status == "unavailable" && infDef.reason == "invalid_stats"
                    && undefAtk.status == "unavailable" && undefAtk.reason == "invalid_stats"
                    && negSpd.status == "unavailable" && negSpd.reason == "invalid_stats"
                    && boolAtk.status == "unavailable" && boolAtk.reason == "invalid_stats",
                "NaN/Infinity/undefined/负速度/布尔伪装数值全部 fail-closed");

            // 15. 无副作用检查
            check(spawnCalls == 0 && flushCalls == 0 && promoExecCalls == 0
                    && _root.金钱 == 88888 && _root.虚拟币 == 123
                    && _root.存档系统.dirtyMark === false,
                "只读投影零创建 MC、零 PlayerStatRefreshCoordinator.flush、零进阶执行、零资产与存档脏标写入");

            // 16. 10 战宠（2 出战 + 8 休息）snapshot 耗时与消息体可观测记录
            var benchPets:Array = [
                [0, 20, 180, 0, 1, { 基础训练: { 次数: 1 } }],
                [78, 100, 200, 0, 1, {}]
            ];
            for (var k:Number = 2; k < 10; k++) {
                benchPets.push([0, 10 + k, 200, 0, 0, {}]);
            }
            _root.宠物信息 = benchPets;
            _root.宠物mc库 = [dogUnit, jkUnit];
            _root.出战宠物id库 = [0, 1];
            var t0:Number = getTimer();
            PetPanelService.handleSnapshot({ callId: "bench_snap_10" });
            var elapsedMs:Number = getTimer() - t0;
            var benchParsed:Object = codec.parse(rawPayload);
            trace("[BENCH] 10 pets (2 deployed ready + 8 resting) handleSnapshot elapsedMs=" + elapsedMs + " payloadChars=" + rawPayload.length);
            check(benchParsed != null && benchParsed.success === true
                    && benchParsed.snapshot.pets.length == 10
                    && benchParsed.snapshot.pets[0].liveCombat.status == "ready"
                    && benchParsed.snapshot.pets[1].liveCombat.status == "ready"
                    && benchParsed.snapshot.pets[9].liveCombat.status == "not_deployed"
                    && rawPayload.indexOf('"combat":') < 0,
                "10 战宠快照可观测基线通过且零旧 combat 字段残留");
        } finally {
            _root.gameworld = oldWorld;
            _root.宠物mc库 = oldPetUnits;
            _root.出战宠物id库 = oldDeployedIds;
            _root.宠物信息 = oldPetInfo;
            _root.宠物库 = oldPetLib;
            _root.敌人属性表 = oldEnemyTable;
            _root.战宠进阶函数 = oldAdvFns;
            _root.等级限制 = oldLevelLimit;
            _root.等级 = oldLevel;
            _root.金钱 = oldMoney;
            _root.虚拟币 = oldKpoint;
            _root.存档系统 = oldSave;
            _root.server = oldServer;
            _root.加载游戏世界人物 = oldSpawn;
            if (_root.战宠UI函数 != undefined) {
                _root.战宠UI函数._宠物刷新待处理 = oldDeferred;
                _root.战宠UI函数.计算战宠升级所需经验 = oldCalcXp;
            }
            _root.当前为战斗地图 = oldCombatMap;
            _root.难度等级 = oldDifficulty;
            _root.宠物领养限制 = oldPetLimit;
            coordinator.flush = oldFlush;
        }

        trace("PetLiveCombatProjectionTest Tests Passed: " + passed);
        trace("PetLiveCombatProjectionTest Tests Failed: " + failed);
    }
}