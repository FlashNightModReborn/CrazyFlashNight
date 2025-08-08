// 文件路径：org.flashNight.arki.bullet.BulletComponent.Type.BulletTypesetterTest.as

import org.flashNight.arki.bullet.BulletComponent.Type.*;
import org.flashNight.gesh.object.ObjectUtil;

/**
 * BulletTypesetter 和 BulletTypeUtil 完整测试套件 
 * 
 * 测试覆盖范围：
 * • 基础功能测试：所有类型检测和标志位计算
 * • 缓存机制测试：验证缓存一致性和性能
 * • 边界条件测试：异常输入和特殊情况
 * • 性能基准测试：对比优化前后的性能提升
 * • 重定向兼容性测试：验证方法搬迁后的兼容性
 * • 透明子弹管理测试：动态类型管理功能
 * 
 * 使用方法：
 * org.flashNight.arki.bullet.BulletComponent.Type.BulletTypesetterTest.main();
 */
class org.flashNight.arki.bullet.BulletComponent.Type.BulletTypesetterTest {
    
    // 测试统计
    private static var testsRun:Number = 0;
    private static var testsPassed:Number = 0;
    private static var testsFailed:Number = 0;
    
    // 简单的断言方法
    private static function assert(condition:Boolean, message:String):Void {
        testsRun++;
        if (!condition) {
            testsFailed++;
            trace("[FAIL] " + message);
            throw new Error("Assertion failed: " + message);
        } else {
            testsPassed++;
            trace("[PASS] " + message);
        }
    }
    
    private static function assertEquals(expected, actual, message:String):Void {
        var condition:Boolean = (expected == actual);
        if (!condition) {
            trace("Expected: " + expected + ", Actual: " + actual);
        }
        assert(condition, message);
    }
    
    private static function assertNotNull(value, message:String):Void {
        assert(value != null && value != undefined, message);
    }
    
    // 测试开始和结束的辅助方法
    private static function startTest(testName:String):Void {
        trace("\n=== 开始测试: " + testName + " ===");
    }
    
    private static function endTest(testName:String):Void {
        trace("=== 完成测试: " + testName + " ===\n");
    }
    
    // AS2/ES3 兼容性辅助方法
    private static function repeatString(str:String, count:Number):String {
        if (count < 0) return "";
        var result:String = "";
        for (var i:Number = 0; i < count; i++) {
            result += str;
        }
        return result;
    }
    
    // ------------------------
    // 基础功能测试方法
    // ------------------------
    
    /**
     * 测试基础的子弹类型检测功能
     */
    private static function testBasicTypeDetection():Void {
        startTest("基础类型检测");
        
        // 测试近战子弹
        var meleeTypes:Array = ["近战子弹", "近战联弹", "激光近战"];
        for (var i:Number = 0; i < meleeTypes.length; i++) {
            assert(BulletTypeUtil.isMelee(meleeTypes[i]), "近战类型检测通过: " + meleeTypes[i]);
            assert(BulletTypesetter.isMelee(meleeTypes[i]), "BulletTypesetter近战类型检测通过: " + meleeTypes[i]);
        }
        
        // 测试联弹子弹
        var chainTypes:Array = ["联弹子弹", "近战联弹", "穿刺联弹"];
        for (var i:Number = 0; i < chainTypes.length; i++) {
            assert(BulletTypeUtil.isChain(chainTypes[i]), "联弹类型检测通过: " + chainTypes[i]);
            assert(BulletTypesetter.isChain(chainTypes[i]), "BulletTypesetter联弹类型检测通过: " + chainTypes[i]);
        }
        
        // 测试穿刺子弹
        var pierceTypes:Array = ["穿刺子弹", "穿刺联弹", "高速穿刺"];
        for (var i:Number = 0; i < pierceTypes.length; i++) {
            assert(BulletTypeUtil.isPierce(pierceTypes[i]), "穿刺类型检测通过: " + pierceTypes[i]);
            assert(BulletTypesetter.isPierce(pierceTypes[i]), "BulletTypesetter穿刺类型检测通过: " + pierceTypes[i]);
        }
        
        // 测试透明子弹
        var transparencyTypes:Array = ["近战子弹", "近战联弹", "透明子弹"];
        for (var i:Number = 0; i < transparencyTypes.length; i++) {
            assert(BulletTypeUtil.isTransparency(transparencyTypes[i]), "透明类型检测通过: " + transparencyTypes[i]);
            assert(BulletTypesetter.isTransparency(transparencyTypes[i]), "BulletTypesetter透明类型检测通过: " + transparencyTypes[i]);
        }
        
        // 测试纵向子弹
        var verticalTypes:Array = ["纵向子弹", "纵向爆炸", "纵向穿刺"];
        for (var i:Number = 0; i < verticalTypes.length; i++) {
            assert(BulletTypeUtil.isVertical(verticalTypes[i]), "纵向类型检测通过: " + verticalTypes[i]);
            assert(BulletTypesetter.isVertical(verticalTypes[i]), "BulletTypesetter纵向类型检测通过: " + verticalTypes[i]);
        }
        
        // 测试爆炸子弹 (移除"高爆弹"，因为"高爆"不等于"爆炸")
        var explosiveTypes:Array = ["爆炸子弹", "纵向爆炸"];
        for (var i:Number = 0; i < explosiveTypes.length; i++) {
            assert(BulletTypeUtil.isExplosive(explosiveTypes[i]), "爆炸类型检测通过: " + explosiveTypes[i]);
            assert(BulletTypesetter.isExplosive(explosiveTypes[i]), "BulletTypesetter爆炸类型检测通过: " + explosiveTypes[i]);
        }
        
        // 测试手雷子弹
        var grenadeTypes:Array = ["手雷子弹", "智能手雷", "定时手雷"];
        for (var i:Number = 0; i < grenadeTypes.length; i++) {
            assert(BulletTypeUtil.isGrenade(grenadeTypes[i]), "手雷类型检测通过: " + grenadeTypes[i]);
            assert(BulletTypesetter.isGrenade(grenadeTypes[i]), "BulletTypesetter手雷类型检测通过: " + grenadeTypes[i]);
        }
        
        // 测试普通子弹
        var normalTypes:Array = ["普通子弹", "近战子弹", "透明子弹"];
        for (var i:Number = 0; i < normalTypes.length; i++) {
            assert(BulletTypeUtil.isNormal(normalTypes[i]), "普通类型检测通过: " + normalTypes[i]);
            assert(BulletTypesetter.isNormal(normalTypes[i]), "BulletTypesetter普通类型检测通过: " + normalTypes[i]);
        }
        
        endTest("基础类型检测");
    }
    
    /**
     * 测试标志位计算的准确性
     */
    private static function testFlagsCalculation():Void {
        startTest("标志位计算");
        
        // 测试复合类型
        var bullet1:Object = { 子弹种类: "近战联弹" };
        var flags1:Number = BulletTypesetter.setTypeFlags(bullet1);
        
        // 近战联弹应该同时具有近战和联弹标志
        assert((flags1 & 1) != 0, "近战联弹正确包含近战标志"); // FLAG_MELEE = 1
        assert((flags1 & 2) != 0, "近战联弹正确包含联弹标志"); // FLAG_CHAIN = 2
        assert((flags1 & 8) != 0, "近战联弹正确包含透明标志"); // FLAG_TRANSPARENCY = 8
        assert((flags1 & 64) != 0, "近战联弹正确包含普通标志"); // FLAG_NORMAL = 64
        
        // 测试穿刺爆炸（不应该是普通子弹）
        var bullet2:Object = { 子弹种类: "穿刺爆炸" };
        var flags2:Number = BulletTypesetter.setTypeFlags(bullet2);
        
        assert((flags2 & 4) != 0, "穿刺爆炸正确包含穿刺标志"); // FLAG_PIERCE = 4
        assert((flags2 & 32) != 0, "穿刺爆炸正确包含爆炸标志"); // FLAG_EXPLOSIVE = 32
        assert((flags2 & 64) == 0, "穿刺爆炸正确不是普通子弹"); // FLAG_NORMAL = 64
        
        // 测试纵向手雷
        var bullet3:Object = { 子弹种类: "纵向手雷" };
        var flags3:Number = BulletTypesetter.setTypeFlags(bullet3);
        
        assert((flags3 & 128) != 0, "纵向手雷正确包含纵向标志"); // FLAG_VERTICAL = 128
        assert((flags3 & 16) != 0, "纵向手雷正确包含手雷标志"); // FLAG_GRENADE = 16
        
        endTest("标志位计算");
    }
    
    /**
     * 测试缓存机制
     */
    private static function testCacheMechanism():Void {
        startTest("缓存机制");
        
        // 清空缓存
        BulletTypesetter.clearCache();
        
        // 第一次调用应该计算并缓存
        var bullet1:Object = { 子弹种类: "测试子弹" };
        var flags1:Number = BulletTypesetter.setTypeFlags(bullet1);
        
        // 第二次调用应该从缓存读取
        var bullet2:Object = { 子弹种类: "测试子弹" };
        var flags2:Number = BulletTypesetter.setTypeFlags(bullet2);
        
        assertEquals(flags1, flags2, "缓存前后标志位应该相同");
        
        // 测试getFlags不污染缓存
        BulletTypesetter.clearCache();
        var debugFlags:Number = BulletTypesetter.getFlags({ 子弹种类: "调试子弹" });
        
        // 再次调用setTypeFlags应该重新计算
        var bullet3:Object = { 子弹种类: "调试子弹" };
        var flags3:Number = BulletTypesetter.setTypeFlags(bullet3);
        assertEquals(debugFlags, flags3, "getFlags和setTypeFlags结果应该相同");
        
        endTest("缓存机制");
    }
    
    /**
     * 测试基础素材名提取
     */
    private static function testBaseAssetExtraction():Void {
        startTest("基础素材名提取");
        
        // 测试联弹的基础素材名提取
        var bullet1:Object = { 子弹种类: "AK47-联弹" };
        BulletTypesetter.setTypeFlags(bullet1);
        assertEquals("AK47", bullet1.baseAsset, "联弹基础素材名应为AK47");
        
        // 测试非联弹的基础素材名
        var bullet2:Object = { 子弹种类: "M16普通子弹" };
        BulletTypesetter.setTypeFlags(bullet2);
        assertEquals("M16普通子弹", bullet2.baseAsset, "非联弹基础素材名应为完整名称");
        
        // 测试getBaseAsset方法
        var baseAsset1:String = BulletTypesetter.getBaseAsset("RPG-联弹");
        assertEquals("RPG", baseAsset1, "getBaseAsset应正确提取联弹基础素材名");
        
        var baseAsset2:String = BulletTypesetter.getBaseAsset("手枪子弹");
        assertEquals("手枪子弹", baseAsset2, "getBaseAsset对非联弹应返回完整名称");
        
        endTest("基础素材名提取");
    }
    
    /**
     * 测试外部FLAG_GRENADE标志处理
     */
    private static function testExternalGrenadeFlag():Void {
        startTest("外部手雷标志处理");
        
        // 首先测试普通子弹本身不是手雷（避免缓存污染）
        BulletTypesetter.clearCache();
        assert(BulletTypeUtil.isGrenade("普通子弹") == false, "普通子弹本身正确不是手雷");
        
        // 测试外部传入的FLAG_GRENADE
        var bullet:Object = { 
            子弹种类: "普通子弹", 
            FLAG_GRENADE: true 
        };
        
        var flags:Number = BulletTypesetter.setTypeFlags(bullet);
        
        // 应该检测到手雷标志
        assert((flags & 16) != 0, "外部FLAG_GRENADE正确被识别"); // FLAG_GRENADE = 16
        
        // FLAG_GRENADE应该被清除
        assert(bullet.FLAG_GRENADE == undefined, "处理后FLAG_GRENADE正确被清除");
        
        endTest("外部手雷标志处理");
    }
    
    /**
     * 测试调试工具方法
     */
    private static function testDebugUtilities():Void {
        startTest("调试工具");
        
        // 测试flagsToString - 英文输出
        var flags:Number = 1 | 2 | 4; // MELEE | CHAIN | PIERCE
        var englishOutput:String = BulletTypeUtil.flagsToString(flags, false);
        assert(englishOutput.indexOf("MELEE") != -1, "英文输出正确包含MELEE");
        assert(englishOutput.indexOf("CHAIN") != -1, "英文输出正确包含CHAIN");
        assert(englishOutput.indexOf("PIERCE") != -1, "英文输出正确包含PIERCE");
        
        // 测试flagsToString - 中文输出
        var chineseOutput:String = BulletTypeUtil.flagsToString(flags, true);
        assert(chineseOutput.indexOf("近战") != -1, "中文输出正确包含近战");
        assert(chineseOutput.indexOf("联弹") != -1, "中文输出正确包含联弹");
        assert(chineseOutput.indexOf("穿刺") != -1, "中文输出正确包含穿刺");
        
        // 测试空标志位
        var emptyFlags:Number = 0;
        assertEquals("NONE", BulletTypeUtil.flagsToString(emptyFlags, false), "空标志位英文输出正确为NONE");
        assertEquals("无", BulletTypeUtil.flagsToString(emptyFlags, true), "空标志位中文输出正确为无");
        
        // 测试重定向兼容性
        assertEquals(englishOutput, BulletTypesetter.flagsToString(flags, false), "BulletTypesetter重定向结果与BulletTypeUtil一致");
        
        endTest("调试工具");
    }
    
    /**
     * 测试透明子弹类型管理
     */
    private static function testTransparencyTypeManagement():Void {
        startTest("透明子弹类型管理");
        
        // 获取初始透明类型列表
        var initialTypes:Array = BulletTypeUtil.getTransparencyTypes();
        var initialCount:Number = initialTypes.length;
        
        // 测试默认透明类型
        assert(BulletTypeUtil.isTransparency("近战子弹"), "近战子弹正确识别为透明");
        assert(BulletTypeUtil.isTransparency("近战联弹"), "近战联弹正确识别为透明");
        assert(BulletTypeUtil.isTransparency("透明子弹"), "透明子弹正确识别为透明");
        assert(!BulletTypeUtil.isTransparency("普通子弹"), "普通子弹正确识别为非透明");
        
        // 测试动态添加透明类型
        var added:Boolean = BulletTypeUtil.addTransparencyType("新透明类型");
        assert(added, "成功添加新的透明类型");
        assert(BulletTypeUtil.isTransparency("新透明类型"), "新添加的类型正确识别为透明");
        
        // 测试重复添加
        var addedAgain:Boolean = BulletTypeUtil.addTransparencyType("新透明类型");
        assert(!addedAgain, "重复添加正确返回false");
        
        // 验证类型列表更新
        var newTypes:Array = BulletTypeUtil.getTransparencyTypes();
        assertEquals(initialCount + 1, newTypes.length, "透明类型数量正确增加1");
        
        // 测试重定向兼容性
        assertEquals(added, BulletTypesetter.addTransparencyType("另一个新类型"), "BulletTypesetter重定向功能正常");
        
        endTest("透明子弹类型管理");
    }
    
    /**
     * 测试边界条件和异常输入
     */
    private static function testBoundaryConditions():Void {
        startTest("边界条件测试");
        
        // 测试undefined和null输入
        assertEquals(0, BulletTypesetter.calculateFlags(undefined), "undefined输入应返回0");
        assertEquals(0, BulletTypesetter.calculateFlags(null), "null输入应返回0");
        assertEquals(0, BulletTypesetter.calculateFlags({}), "空对象应返回0");
        assertEquals(0, BulletTypesetter.calculateFlags({ 子弹种类: undefined }), "undefined子弹种类应返回0");
        
        // 测试空字符串（性能优化：异常输入返回undefined，避免额外检查开销）
        var emptyBullet:Object = { 子弹种类: "" };
        var emptyFlags:Number = BulletTypesetter.setTypeFlags(emptyBullet);
        assertEquals(undefined, emptyFlags, "空字符串子弹种类应返回undefined（性能优化设计）");
        
        // 测试极长字符串
        var longType:String = "";
        for (var i:Number = 0; i < 1000; i++) {
            longType += "很长的子弹类型名称";
        }
        var longBullet:Object = { 子弹种类: longType };
        var longFlags:Number = BulletTypesetter.setTypeFlags(longBullet);
        assertNotNull(longFlags, "极长字符串应该能正常处理");
        
        // 测试特殊字符
        var specialBullet:Object = { 子弹种类: "!@#$%^&*()近战联弹_+{}|:<>?[]\\;'\",./" };
        var specialFlags:Number = BulletTypesetter.setTypeFlags(specialBullet);
        assert((specialFlags & 1) != 0, "包含特殊字符的近战子弹应该被正确识别");
        assert((specialFlags & 2) != 0, "包含特殊字符的联弹应该被正确识别");
        
        endTest("边界条件测试");
    }
    
    /**
     * 测试方法搬迁后的兼容性
     */
    private static function testCompatibilityRedirection():Void {
        startTest("兼容性重定向测试");
        
        // 测试所有重定向方法与原始方法结果一致
        var testTypes:Array = ["近战子弹", "联弹子弹", "穿刺爆炸", "纵向手雷", "普通子弹"];
        
        for (var i:Number = 0; i < testTypes.length; i++) {
            var bulletType:String = testTypes[i];
            
            // 比较BulletTypesetter和BulletTypeUtil的结果
            assertEquals(BulletTypesetter.isVertical(bulletType), BulletTypeUtil.isVertical(bulletType), "isVertical重定向测试: " + bulletType);
            assertEquals(BulletTypesetter.isMelee(bulletType), BulletTypeUtil.isMelee(bulletType), "isMelee重定向测试: " + bulletType);
            assertEquals(BulletTypesetter.isChain(bulletType), BulletTypeUtil.isChain(bulletType), "isChain重定向测试: " + bulletType);
            assertEquals(BulletTypesetter.isPierce(bulletType), BulletTypeUtil.isPierce(bulletType), "isPierce重定向测试: " + bulletType);
            assertEquals(BulletTypesetter.isTransparency(bulletType), BulletTypeUtil.isTransparency(bulletType), "isTransparency重定向测试: " + bulletType);
            assertEquals(BulletTypesetter.isGrenade(bulletType), BulletTypeUtil.isGrenade(bulletType), "isGrenade重定向测试: " + bulletType);
            assertEquals(BulletTypesetter.isExplosive(bulletType), BulletTypeUtil.isExplosive(bulletType), "isExplosive重定向测试: " + bulletType);
            assertEquals(BulletTypesetter.isNormal(bulletType), BulletTypeUtil.isNormal(bulletType), "isNormal重定向测试: " + bulletType);
        }
        
        endTest("兼容性重定向测试");
    }
    
    // ------------------------
    // 性能基准测试
    // ------------------------
    
    /**
     * 性能基准测试
     */
    private static function testPerformanceBenchmark():Void {
        startTest("性能基准测试");
        
        var iterations:Number = 10000;
        var testTypes:Array = [
            "近战子弹", "联弹子弹", "穿刺爆炸", "纵向手雷", "普通子弹",
            "AK47-联弹", "M16穿刺", "RPG爆炸", "激光近战", "智能手雷"
        ];
        
        // AS2兼容的计时器函数
        function getTime():Number {
            var timer:Number;
            if (_root && _root.getTimer && typeof(_root.getTimer()) == "number") {
                timer = _root.getTimer();
                if (!isNaN(timer)) return timer;
            }
            if (getTimer && typeof(getTimer()) == "number") {
                timer = getTimer();
                if (!isNaN(timer)) return timer;
            }
            // 回退到Date对象（精度较低但可用）
            return new Date().getTime();
        }
        
        // 测试setTypeFlags性能
        var startTime:Number = getTime();
        for (var i:Number = 0; i < iterations; i++) {
            var bullet:Object = { 子弹种类: testTypes[i % testTypes.length] };
            BulletTypesetter.setTypeFlags(bullet);
        }
        var setTypeFlagsTime:Number = getTime() - startTime;
        
        // 测试类型检测性能 (BulletTypeUtil)
        startTime = getTime();
        for (var i:Number = 0; i < iterations; i++) {
            var bulletType:String = testTypes[i % testTypes.length];
            BulletTypeUtil.isMelee(bulletType);
            BulletTypeUtil.isChain(bulletType);
            BulletTypeUtil.isPierce(bulletType);
            BulletTypeUtil.isTransparency(bulletType);
        }
        var typeCheckTime:Number = getTime() - startTime;
        
        // 测试缓存性能
        BulletTypesetter.clearCache();
        startTime = getTime();
        for (var i:Number = 0; i < iterations; i++) {
            // 重复调用相同类型，测试缓存效果
            var bullet:Object = { 子弹种类: "测试缓存子弹" };
            BulletTypesetter.setTypeFlags(bullet);
        }
        var cacheTime:Number = getTime() - startTime;
        
        trace("性能基准测试结果 (" + iterations + " 次迭代):");
        trace("setTypeFlags: " + setTypeFlagsTime + "ms");
        trace("类型检测: " + typeCheckTime + "ms");
        trace("缓存性能: " + cacheTime + "ms");
        
        // 性能阈值检查（可根据实际情况调整）
        assert(setTypeFlagsTime < 5000, "setTypeFlags性能达标，" + iterations + "次调用耗时" + setTypeFlagsTime + "ms");
        assert(typeCheckTime < 3000, "类型检测性能达标，" + (iterations * 4) + "次调用耗时" + typeCheckTime + "ms");
        assert(cacheTime < 1000, "缓存性能达标，" + iterations + "次调用耗时" + cacheTime + "ms");
        
        endTest("性能基准测试");
    }
    
    /**
     * 内存使用测试
     */
    private static function testMemoryUsage():Void {
        startTest("内存使用测试");
        
        // 创建大量不同类型的子弹，测试缓存内存使用
        var bulletTypes:Array = [];
        for (var i:Number = 0; i < 1000; i++) {
            bulletTypes.push("测试子弹类型_" + i + (Math.random() > 0.5 ? "_近战" : "_联弹"));
        }
        
        // 清空缓存开始测试
        BulletTypesetter.clearCache();
        
        for (var i:Number = 0; i < bulletTypes.length; i++) {
            var bullet:Object = { 子弹种类: bulletTypes[i] };
            BulletTypesetter.setTypeFlags(bullet);
        }
        
        // 验证缓存正常工作
        for (var i:Number = 0; i < 10; i++) {
            var testBullet:Object = { 子弹种类: bulletTypes[i] };
            var flags1:Number = BulletTypesetter.setTypeFlags(testBullet);
            var flags2:Number = BulletTypesetter.getFlags(testBullet);
            assertEquals(flags1, flags2, "缓存一致性测试 " + i);
        }
        
        // 清空缓存测试内存释放
        BulletTypesetter.clearCache();
        
        // 验证缓存已清空
        var newBullet:Object = { 子弹种类: bulletTypes[0] };
        var newFlags:Number = BulletTypesetter.setTypeFlags(newBullet);
        assertNotNull(newFlags, "清空缓存后应该能重新计算");
        
        endTest("内存使用测试");
    }
    
    // ------------------------
    // 完整的测试套件执行方法
    // ------------------------
    
    /**
     * 运行所有功能测试
     */
    private static function runAllTests():Void {
        trace("\n" + repeatString("=", 60));
        trace("开始执行 BulletTypesetter 和 BulletTypeUtil 完整测试套件");
        trace(repeatString("=", 60));
        
        testsRun = 0;
        testsPassed = 0;
        testsFailed = 0;
        
        try {
            // 基础功能测试
            testBasicTypeDetection();
            testFlagsCalculation();
            testBaseAssetExtraction();
            testExternalGrenadeFlag();
            
            // 缓存和性能测试
            testCacheMechanism();
            testMemoryUsage();
            
            // 工具方法测试
            testDebugUtilities();
            testTransparencyTypeManagement();
            
            // 边界条件和兼容性测试
            testBoundaryConditions();
            testCompatibilityRedirection();
            
        } catch (error:Error) {
            trace("测试执行出错: " + error.message);
        }
        
        // 输出测试结果统计
        trace("\n" + repeatString("=", 60));
        trace("测试结果统计:");
        trace("总计运行: " + testsRun + " 个测试");
        trace("通过: " + testsPassed + " 个");
        trace("失败: " + testsFailed + " 个");
        trace("成功率: " + Math.round((testsPassed / testsRun) * 100) + "%");
        
        if (testsFailed == 0) {
            trace("🎉 所有测试通过！");
        } else {
            trace("❌ 有 " + testsFailed + " 个测试失败，请检查实现");
        }
        trace(repeatString("=", 60));
    }
    
    /**
     * 运行性能测试
     */
    private static function runPerformanceTest():Void {
        trace("\n" + repeatString("=", 60));
        trace("开始执行性能基准测试");
        trace(repeatString("=", 60));
        
        try {
            testPerformanceBenchmark();
        } catch (error:Error) {
            trace("性能测试出错: " + error.message);
        }
        
        trace("性能测试完成");
        trace(repeatString("=", 60));
    }
    
    // ------------------------
    // 入口方法
    // ------------------------
    
    /**
     * 测试套件主入口
     * 使用方法：org.flashNight.arki.bullet.BulletComponent.Type.BulletTypesetterTest.main();
     */
    public static function main():Void {
        // ========== AS2/ES3 兼容性 Polyfill ==========
        // 在运行测试前添加现代JavaScript方法的兼容实现
        
        // String.prototype.repeat polyfill for AS2
        if (String.prototype.repeat == undefined) {
            String.prototype.repeat = function(count:Number):String {
                if (count < 0 || count == Infinity) {
                    throw new Error("Invalid count value");
                }
                count = Math.floor(count);
                var result:String = "";
                var str:String = this.toString();
                while (count > 0) {
                    if (count & 1) {
                        result += str;
                    }
                    str += str;
                    count >>>= 1;
                }
                return result;
            };
        }
        
        // Math.round polyfill check (通常AS2已支持，但确保可用)
        if (Math.round == undefined) {
            Math.round = function(x:Number):Number {
                return Math.floor(x + 0.5);
            };
        }
        
        trace("AS2兼容性Polyfill已加载");
        
        // 运行测试套件
        runAllTests();
        runPerformanceTest();
        
        trace("\n完整测试套件执行完毕！");
    }
}