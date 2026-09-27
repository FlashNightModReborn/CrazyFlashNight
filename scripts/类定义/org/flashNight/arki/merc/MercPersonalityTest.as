import org.flashNight.arki.merc.MercLibrary;
import org.flashNight.arki.merc.MercPanelService;

/**
 * 佣兵数据侧性格配置回归：mercenaries.json 顶层 personality → MercLibrary.normalizePersonality
 * → merc[19].性格 → MercLibrary.mergePersonalityTraits。战斗侧 配置人形怪AI 与面板
 * buildPersonality 共用同一份合并语义，本套件钉住"配置即生效、未配置零影响、越界先夹取"。
 * 填表说明见 data/merc/mercenaries_README.md。
 */
class org.flashNight.arki.merc.MercPersonalityTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;
    private static var DIMS:Array = ["勇气", "技术", "经验", "反应", "智力", "谋略"];

    public static function runAllTests():Void {
        passed = 0;
        failed = 0;
        trace("=== MercPersonalityTest start ===");
        testNormalizePersonality();
        testMergePersonalityTraits();
        testBuildMercDataWritesPersonality();
        testPanelProjectsAuthoredPersonality();
        trace("MercPersonalityTest Tests Passed: " + passed);
        trace("MercPersonalityTest Tests Failed: " + failed);
        trace("=== MercPersonalityTest end ===");
    }

    private static function check(condition:Boolean, message:String):Void {
        if (condition) {
            passed++;
        } else {
            failed++;
            trace("[FAIL] " + message);
        }
    }

    private static function mercTupleWithMeta(meta:Object):Array {
        var merc:Array = [];
        merc[19] = meta;
        return merc;
    }

    private static function testNormalizePersonality():Void {
        // 形参注解为 :Object，故意传非对象时用无类型局部变量绕过编译期类型检查
        var unset = undefined;
        var notObject = 5;
        check(MercLibrary.normalizePersonality(unset) === undefined,
            "未配置 personality 不产生性格覆写");
        check(MercLibrary.normalizePersonality(notObject) === undefined,
            "非对象 personality 不产生性格覆写");

        var partial:Object = MercLibrary.normalizePersonality({勇气:0.9, 外域键:0.5});
        check(partial != undefined && partial.勇气 === 0.9,
            "已配置的维度按原值保留");
        check(partial.技术 == undefined,
            "未配置的维度保持缺省，交给 生成随机人格");
        check(partial.外域键 == undefined,
            "六维以外的键被丢弃，不进入性格覆写");

        var clamped:Object = MercLibrary.normalizePersonality({技术:3, 反应:-2});
        check(clamped != undefined && clamped.技术 === 1 && clamped.反应 === 0,
            "越界维度夹回 [0,1]，避免 计算AI参数 线性公式放大");

        check(MercLibrary.normalizePersonality({勇气:"勇气"}) === undefined,
            "全非数值维度整条不产出覆写");
        check(MercLibrary.normalizePersonality({勇气:null}) === undefined,
            "显式 null 维度按未配置处理，不被 Number(null) 夹成 0");
        var mixed:Object = MercLibrary.normalizePersonality({勇气:"勇气", 智力:0.4});
        check(mixed != undefined && mixed.勇气 == undefined && mixed.智力 === 0.4,
            "非法值只丢弃自身，同批合法维度仍生效");
    }

    private static function testMergePersonalityTraits():Void {
        var p:Object = {勇气:0.2, 技术:0.3, 经验:0.4, 反应:0.5, 智力:0.6, 谋略:0.7};
        var held:Object = p;
        check(MercLibrary.mergePersonalityTraits(p, {勇气:0.95}) === true,
            "存在覆写维度时返回 true，调用方据此重算派生参数");
        check(held === p && held.勇气 === 0.95,
            "合并 mutate 同一人格对象引用（AI 与面板持同一引用，不得替换向量）");
        check(p.技术 === 0.3 && p.谋略 === 0.7,
            "未覆写维度保持 生成随机人格 的结果");
        var noAuthored = undefined;
        check(MercLibrary.mergePersonalityTraits(p, noAuthored) === false,
            "无 merc[19].性格 时不报已合并");
        check(MercLibrary.mergePersonalityTraits(p, {}) === false,
            "空覆写对象不报已合并");
        check(p.外域键 == undefined,
            "合并不会写入六维以外的键");
    }

    private static function testBuildMercDataWritesPersonality():Void {
        var savedEasy:Function = _root.isEasyMode;
        var savedBaseValue = _root.基础身价值;
        try {
            _root.isEasyMode = function():Boolean { return false; };
            _root.基础身价值 = 1000;

            var plain:Array = MercLibrary.buildMercData({level:10, name:"测试佣兵", id:"m1"});
            check(plain[19].性格 == undefined,
                "缺省佣兵不写 merc[19].性格");
            check(plain[19].是否杂交 === false,
                "性格缺省时 merc[19] 既有元数据键保留");

            var configured:Array = MercLibrary.buildMercData({
                level:10, name:"测试佣兵", id:"m1", personality:{勇气:0.95, 谋略:1.4}
            });
            check(configured[19].性格 != undefined && configured[19].性格.勇气 === 0.95,
                "personality 经 buildMercData 落到 merc[19].性格");
            check(configured[19].性格.谋略 === 1,
                "入表即归一化：merc[19].性格 存的是夹取后的值");
            check(configured[19].性格.技术 == undefined,
                "部分配置只覆写列出的维度");

            var junk:Array = MercLibrary.buildMercData({
                level:10, name:"测试佣兵", id:"m1", personality:{勇气:"勇气"}
            });
            check(junk[19].性格 == undefined,
                "全非法的 personality 不写 merc[19].性格");
        } finally {
            _root.isEasyMode = savedEasy;
            _root.基础身价值 = savedBaseValue;
        }
    }

    private static function testPanelProjectsAuthoredPersonality():Void {
        var base:Object = MercPanelService.buildPersonality(
            mercTupleWithMeta({}), "测试佣兵", 10);
        var merged:Object = MercPanelService.buildPersonality(
            mercTupleWithMeta({性格:{勇气:0.95, 谋略:0.05}}), "测试佣兵", 10);

        check(merged.勇气 === 0.95 && merged.谋略 === 0.05,
            "面板六维读数据侧性格覆写，与战斗侧 配置人形怪AI 同源");
        check(merged.技术 === base.技术 && merged.经验 === base.经验 &&
                merged.反应 === base.反应 && merged.智力 === base.智力,
            "未覆写维度仍取同一种子的人格向量，配置不改变随机基准");

        var allNumeric:Boolean = true;
        for (var i:Number = 0; i < DIMS.length; i++) {
            if (isNaN(Number(merged[DIMS[i]])) || isNaN(Number(base[DIMS[i]]))) {
                allNumeric = false;
            }
        }
        check(allNumeric, "面板投影的六维在配置与未配置两条路径上都是数值");
    }
}
