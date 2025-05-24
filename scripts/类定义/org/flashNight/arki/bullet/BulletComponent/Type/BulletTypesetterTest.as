// 文件路径：org.flashNight.arki.bullet.BulletComponent.Type.BulletTypesetterTest.as

import org.flashNight.arki.bullet.BulletComponent.Type.BulletTypesetter;
import org.flashNight.gesh.object.ObjectUtil;

class org.flashNight.arki.bullet.BulletComponent.Type.BulletTypesetterTest {
    
    // 简单的断言方法
    private static function assert(condition:Boolean, message:String):Void {
        if (!condition) {
            throw new Error("Assertion failed: " + message);
        }
    }
    
    // ------------------------
    // 基础功能测试方法
    // ------------------------

    // 测试近战子弹
    private static function testMeleeBullet():Void {
        var bullet:Object = { 子弹种类: "近战子弹" };
        BulletTypesetter.setTypeFlags(bullet);
        
        assert(bullet.近战检测 == true, bullet.子弹种类 + " 近战检测应为 true");
        assert(bullet.联弹检测 == false, bullet.子弹种类 + " 联弹检测应为 false");
        assert(bullet.穿刺检测 == false, bullet.子弹种类 + " 穿刺检测应为 false");
        assert(bullet.透明检测 == true, bullet.子弹种类 + " 透明检测应为 true");
        assert(bullet.手雷检测 == false, bullet.子弹种类 + " 手雷检测应为 false");
        assert(bullet.爆炸检测 == false, bullet.子弹种类 + " 爆炸检测应为 false");
        assert(bullet.普通检测 == true, bullet.子弹种类 + " 普通检测应为 true");
        
        // 测试 baseAsset
        assert(bullet.baseAsset == "近战子弹", "baseAsset 应为 '近战子弹'");
    }
    
    // 测试联弹子弹
    private static function testChainBullet():Void {
        var bullet:Object = { 子弹种类: "联弹子弹" };
        BulletTypesetter.setTypeFlags(bullet);
        
        assert(bullet.近战检测 == false, bullet.子弹种类 + " 近战检测应为 false");
        assert(bullet.联弹检测 == true, bullet.子弹种类 + " 联弹检测应为 true");
        assert(bullet.穿刺检测 == false, bullet.子弹种类 + " 穿刺检测应为 false");
        assert(bullet.透明检测 == false, bullet.子弹种类 + " 透明检测应为 false");
        assert(bullet.手雷检测 == false, bullet.子弹种类 + " 手雷检测应为 false");
        assert(bullet.爆炸检测 == false, bullet.子弹种类 + " 爆炸检测应为 false");
        assert(bullet.普通检测 == false, bullet.子弹种类 + " 普通检测应为 false");
        
        // 测试 baseAsset
        assert(bullet.baseAsset == "联弹子弹", "baseAsset 应为 '联弹子弹'");
    }
    
    // 测试穿刺子弹
    private static function testPierceBullet():Void {
        var bullet:Object = { 子弹种类: "穿刺子弹" };
        BulletTypesetter.setTypeFlags(bullet);
        
        assert(bullet.近战检测 == false, bullet.子弹种类 + " 近战检测应为 false");
        assert(bullet.联弹检测 == false, bullet.子弹种类 + " 联弹检测应为 false");
        assert(bullet.穿刺检测 == true, bullet.子弹种类 + " 穿刺检测应为 true");
        assert(bullet.透明检测 == false, bullet.子弹种类 + " 透明检测应为 false");
        assert(bullet.手雷检测 == false, bullet.子弹种类 + " 手雷检测应为 false");
        assert(bullet.爆炸检测 == false, bullet.子弹种类 + " 爆炸检测应为 false");
        assert(bullet.普通检测 == false, bullet.子弹种类 + " 普通检测应为 false");
        
        // 测试 baseAsset
        assert(bullet.baseAsset == "穿刺子弹", "baseAsset 应为 '穿刺子弹'");
    }
    
    // 测试透明子弹
    private static function testTransparencyBullet():Void {
        var bullet:Object = { 子弹种类: "透明子弹" };
        BulletTypesetter.setTypeFlags(bullet);
        
        assert(bullet.近战检测 == false, bullet.子弹种类 + " 近战检测应为 false");
        assert(bullet.联弹检测 == false, bullet.子弹种类 + " 联弹检测应为 false");
        assert(bullet.穿刺检测 == false, bullet.子弹种类 + " 穿刺检测应为 false");
        assert(bullet.透明检测 == true, bullet.子弹种类 + " 透明检测应为 true");
        assert(bullet.手雷检测 == false, bullet.子弹种类 + " 手雷检测应为 false");
        assert(bullet.爆炸检测 == false, bullet.子弹种类 + " 爆炸检测应为 false");
        assert(bullet.普通检测 == true, bullet.子弹种类 + " 普通检测应为 true");
        
        // 测试 baseAsset
        assert(bullet.baseAsset == "透明子弹", "baseAsset 应为 '透明子弹'");
    }
    
    // 测试手雷子弹
    private static function testGrenadeBullet():Void {
        var bullet:Object = { 子弹种类: "手雷子弹" };
        BulletTypesetter.setTypeFlags(bullet);
        
        assert(bullet.近战检测 == false, bullet.子弹种类 + " 近战检测应为 false");
        assert(bullet.联弹检测 == false, bullet.子弹种类 + " 联弹检测应为 false");
        assert(bullet.穿刺检测 == false, bullet.子弹种类 + " 穿刺检测应为 false");
        assert(bullet.透明检测 == false, bullet.子弹种类 + " 透明检测应为 false");
        assert(bullet.手雷检测 == true, bullet.子弹种类 + " 手雷检测应为 true");
        assert(bullet.爆炸检测 == false, bullet.子弹种类 + " 爆炸检测应为 false");
        assert(bullet.普通检测 == false, bullet.子弹种类 + " 普通检测应为 false");
        
        // 测试 baseAsset
        assert(bullet.baseAsset == "手雷子弹", "baseAsset 应为 '手雷子弹'");
    }
    
    // 测试爆炸子弹
    private static function testExplosiveBullet():Void {
        var bullet:Object = { 子弹种类: "爆炸子弹" };
        BulletTypesetter.setTypeFlags(bullet);
        
        assert(bullet.近战检测 == false, bullet.子弹种类 + " 近战检测应为 false");
        assert(bullet.联弹检测 == false, bullet.子弹种类 + " 联弹检测应为 false");
        assert(bullet.穿刺检测 == false, bullet.子弹种类 + " 穿刺检测应为 false");
        assert(bullet.透明检测 == false, bullet.子弹种类 + " 透明检测应为 false");
        assert(bullet.手雷检测 == false, bullet.子弹种类 + " 手雷检测应为 false");
        assert(bullet.爆炸检测 == true, bullet.子弹种类 + " 爆炸检测应为 true");
        assert(bullet.普通检测 == false, bullet.子弹种类 + " 普通检测应为 false");
        
        // 测试 baseAsset
        assert(bullet.baseAsset == "爆炸子弹", "baseAsset 应为 '爆炸子弹'");
    }
    
    // 测试普通子弹
    private static function testNormalBullet():Void {
        var bullet:Object = { 子弹种类: "普通子弹" };
        BulletTypesetter.setTypeFlags(bullet);
        
        assert(bullet.近战检测 == false, bullet.子弹种类 + " 近战检测应为 false");
        assert(bullet.联弹检测 == false, bullet.子弹种类 + " 联弹检测应为 false");
        assert(bullet.穿刺检测 == false, bullet.子弹种类 + " 穿刺检测应为 false");
        assert(bullet.透明检测 == false, bullet.子弹种类 + " 透明检测应为 false");
        assert(bullet.手雷检测 == false, bullet.子弹种类 + " 手雷检测应为 false");
        assert(bullet.爆炸检测 == false, bullet.子弹种类 + " 爆炸检测应为 false");
        assert(bullet.普通检测 == true, bullet.子弹种类 + " 普通检测应为 true");
        
        // 测试 baseAsset
        assert(bullet.baseAsset == "普通子弹", "baseAsset 应为 '普通子弹'");
    }
    
    // 测试能量子弹
    private static function testEnergyBullet():Void {
        var bullet:Object = { 子弹种类: "能量子弹" };
        BulletTypesetter.setTypeFlags(bullet);
        
        assert(bullet.近战检测 == false, bullet.子弹种类 + " 近战检测应为 false");
        assert(bullet.联弹检测 == false, bullet.子弹种类 + " 联弹检测应为 false");
        assert(bullet.穿刺检测 == false, bullet.子弹种类 + " 穿刺检测应为 false");
        assert(bullet.透明检测 == false, bullet.子弹种类 + " 透明检测应为 false");
        assert(bullet.手雷检测 == false, bullet.子弹种类 + " 手雷检测应为 false");
        assert(bullet.爆炸检测 == false, bullet.子弹种类 + " 爆炸检测应为 false");
        assert(bullet.普通检测 == false, bullet.子弹种类 + " 普通检测应为 false");
        
        // 测试 baseAsset
        assert(bullet.baseAsset == "能量子弹", "baseAsset 应为 '能量子弹'");
    }
    
    // 测试精制子弹
    private static function testRefinedBullet():Void {
        var bullet:Object = { 子弹种类: "精制子弹" };
        BulletTypesetter.setTypeFlags(bullet);
        
        assert(bullet.近战检测 == false, bullet.子弹种类 + " 近战检测应为 false");
        assert(bullet.联弹检测 == false, bullet.子弹种类 + " 联弹检测应为 false");
        assert(bullet.穿刺检测 == false, bullet.子弹种类 + " 穿刺检测应为 false");
        assert(bullet.透明检测 == false, bullet.子弹种类 + " 透明检测应为 false");
        assert(bullet.手雷检测 == false, bullet.子弹种类 + " 手雷检测应为 false");
        assert(bullet.爆炸检测 == false, bullet.子弹种类 + " 爆炸检测应为 false");
        assert(bullet.普通检测 == false, bullet.子弹种类 + " 普通检测应为 false");
        
        // 测试 baseAsset
        assert(bullet.baseAsset == "精制子弹", "baseAsset 应为 '精制子弹'");
    }
    
    // 测试新能量子弹
    private static function testNewEnergyBullet():Void {
        var bullet:Object = { 子弹种类: "新能量子弹" };
        BulletTypesetter.setTypeFlags(bullet);
        
        assert(bullet.近战检测 == false, bullet.子弹种类 + " 近战检测应为 false");
        assert(bullet.联弹检测 == false, bullet.子弹种类 + " 联弹检测应为 false");
        assert(bullet.穿刺检测 == false, bullet.子弹种类 + " 穿刺检测应为 false");
        assert(bullet.透明检测 == false, bullet.子弹种类 + " 透明检测应为 false");
        assert(bullet.手雷检测 == false, bullet.子弹种类 + " 手雷检测应为 false");
        assert(bullet.爆炸检测 == false, bullet.子弹种类 + " 爆炸检测应为 false");
        assert(bullet.普通检测 == false, bullet.子弹种类 + " 普通检测应为 false");
        
        // 测试 baseAsset
        assert(bullet.baseAsset == "新能量子弹", "baseAsset 应为 '新能量子弹'");
    }
    
    // 测试巨型穿刺能量子弹
    private static function testBigEnergyBullet():Void {
        var bullet:Object = { 子弹种类: "巨型穿刺能量子弹" };
        BulletTypesetter.setTypeFlags(bullet);
        
        assert(bullet.近战检测 == false, bullet.子弹种类 + " 近战检测应为 false");
        assert(bullet.联弹检测 == false, bullet.子弹种类 + " 联弹检测应为 false");
        assert(bullet.穿刺检测 == true, bullet.子弹种类 + " 穿刺检测应为 true");
        assert(bullet.透明检测 == false, bullet.子弹种类 + " 透明检测应为 false");
        assert(bullet.手雷检测 == false, bullet.子弹种类 + " 手雷检测应为 false");
        assert(bullet.爆炸检测 == false, bullet.子弹种类 + " 爆炸检测应为 false");
        assert(bullet.普通检测 == false, bullet.子弹种类 + " 普通检测应为 false");
        
        // 测试 baseAsset
        assert(bullet.baseAsset == "巨型穿刺能量子弹", "baseAsset 应为 '巨型穿刺能量子弹'");
    }
    
    // 测试精制联弹透明子弹
    private static function testRefinedChainTransparencyBullet():Void {
        var bullet:Object = { 子弹种类: "精制联弹透明子弹" };
        BulletTypesetter.setTypeFlags(bullet);
        
        assert(bullet.近战检测 == false, bullet.子弹种类 + " 近战检测应为 false");
        assert(bullet.联弹检测 == true, bullet.子弹种类 + " 联弹检测应为 true");
        assert(bullet.穿刺检测 == false, bullet.子弹种类 + " 穿刺检测应为 false");
        assert(bullet.透明检测 == false, bullet.子弹种类 + " 透明检测应为 false");
        assert(bullet.手雷检测 == false, bullet.子弹种类 + " 手雷检测应为 false");
        assert(bullet.爆炸检测 == false, bullet.子弹种类 + " 爆炸检测应为 false");
        assert(bullet.普通检测 == false, bullet.子弹种类 + " 普通检测应为 false");
        
        // 测试 baseAsset
        assert(bullet.baseAsset == "精制联弹透明子弹", "baseAsset 应为 '精制联弹透明子弹'");
    }
    
    // 测试组合子弹（近战联弹穿刺）
    private static function testCombinedBullet():Void {
        var bullet:Object = { 子弹种类: "近战联弹穿刺" };
        BulletTypesetter.setTypeFlags(bullet);
        
        assert(bullet.近战检测 == true, bullet.子弹种类 + " 近战检测应为 true");
        assert(bullet.联弹检测 == true, bullet.子弹种类 + " 联弹检测应为 true");
        assert(bullet.穿刺检测 == true, bullet.子弹种类 + " 穿刺检测应为 true");
        assert(bullet.透明检测 == false, bullet.子弹种类 + " 透明检测应为 false");
        assert(bullet.手雷检测 == false, bullet.子弹种类 + " 手雷检测应为 false");
        assert(bullet.爆炸检测 == false, bullet.子弹种类 + " 爆炸检测应为 false");
        assert(bullet.普通检测 == false, bullet.子弹种类 + " 普通检测应为 false");
        
        // 测试 baseAsset
        assert(bullet.baseAsset == "近战联弹穿刺", "baseAsset 应为 '近战联弹穿刺'");
    }
    
    // 测试子弹种类包含多个关键词但不在透明列表中
    private static function testMultipleKeywordsNonTransparent():Void {
        var bullet:Object = { 子弹种类: "近战爆炸子弹" };
        BulletTypesetter.setTypeFlags(bullet);
        
        assert(bullet.近战检测 == true, bullet.子弹种类 + " 近战检测应为 true");
        assert(bullet.联弹检测 == false, bullet.子弹种类 + " 联弹检测应为 false");
        assert(bullet.穿刺检测 == false, bullet.子弹种类 + " 穿刺检测应为 false");
        assert(bullet.透明检测 == false, bullet.子弹种类 + " 透明检测应为 false");
        assert(bullet.手雷检测 == false, bullet.子弹种类 + " 手雷检测应为 false");
        assert(bullet.爆炸检测 == true, bullet.子弹种类 + " 爆炸检测应为 true");
        assert(bullet.普通检测 == false, bullet.子弹种类 + " 普通检测应为 false");
        
        // 测试 baseAsset
        assert(bullet.baseAsset == "近战爆炸子弹", "baseAsset 应为 '近战爆炸子弹'");
    }
    
    // 测试子弹种类包含多个关键词且在透明列表中
    private static function testMultipleKeywordsTransparent():Void {
        var bullet:Object = { 子弹种类: "近战联弹透明子弹" };
        BulletTypesetter.setTypeFlags(bullet);
        
        assert(bullet.近战检测 == true, bullet.子弹种类 + " 近战检测应为 true");
        assert(bullet.联弹检测 == true, bullet.子弹种类 + " 联弹检测应为 true");
        assert(bullet.穿刺检测 == false, bullet.子弹种类 + " 穿刺检测应为 false");
        assert(bullet.透明检测 == false, bullet.子弹种类 + " 透明检测应为 false");
        assert(bullet.手雷检测 == false, bullet.子弹种类 + " 手雷检测应为 false");
        assert(bullet.爆炸检测 == false, bullet.子弹种类 + " 爆炸检测应为 false");
        assert(bullet.普通检测 == true, bullet.子弹种类 + " 普通检测应为 true");
        
        // 测试 baseAsset
        assert(bullet.baseAsset == "近战联弹透明子弹", "baseAsset 应为 '近战联弹透明子弹'");
    }
    
    // ------------------------
    // 边界条件测试
    // ------------------------
    
    // 测试未知子弹种类
    private static function testUnknownBullet():Void {
        var bullet:Object = { 子弹种类: "未知子弹" };
        BulletTypesetter.setTypeFlags(bullet);
        
        assert(bullet.近战检测 == false, bullet.子弹种类 + " 近战检测应为 false");
        assert(bullet.联弹检测 == false, bullet.子弹种类 + " 联弹检测应为 false");
        assert(bullet.穿刺检测 == false, bullet.子弹种类 + " 穿刺检测应为 false");
        assert(bullet.透明检测 == false, bullet.子弹种类 + " 透明检测应为 false");
        assert(bullet.手雷检测 == false, bullet.子弹种类 + " 手雷检测应为 false");
        assert(bullet.爆炸检测 == false, bullet.子弹种类 + " 爆炸检测应为 false");
        assert(bullet.普通检测 == false, bullet.子弹种类 + " 普通检测应为 false");
        
        // 测试 baseAsset
        assert(bullet.baseAsset == "未知子弹", "baseAsset 应为 '未知子弹'");
    }
    
    // 测试空子弹种类
    private static function testEmptyBullet():Void {
        var bullet:Object = { 子弹种类: "" };
        BulletTypesetter.setTypeFlags(bullet);
        
        assert(bullet.近战检测 == false, "空子弹种类 近战检测应为 false");
        assert(bullet.联弹检测 == false, "空子弹种类 联弹检测应为 false");
        assert(bullet.穿刺检测 == false, "空子弹种类 穿刺检测应为 false");
        assert(bullet.透明检测 == false, "空子弹种类 透明检测应为 false");
        assert(bullet.手雷检测 == false, "空子弹种类 手雷检测应为 false");
        assert(bullet.爆炸检测 == false, "空子弹种类 爆炸检测应为 false");
        assert(bullet.普通检测 == false, "空子弹种类 普通检测应为 false");
        
        // 测试 baseAsset
        assert(bullet.baseAsset == undefined, "baseAsset 应为空字符串");
    }
    
    // 测试精制普通子弹
    private static function testRefinedNormalBullet():Void {
        var bullet:Object = { 子弹种类: "精制普通子弹" };
        BulletTypesetter.setTypeFlags(bullet);
        
        assert(bullet.近战检测 == false, bullet.子弹种类 + " 近战检测应为 false");
        assert(bullet.联弹检测 == false, bullet.子弹种类 + " 联弹检测应为 false");
        assert(bullet.穿刺检测 == false, bullet.子弹种类 + " 穿刺检测应为 false");
        assert(bullet.透明检测 == false, bullet.子弹种类 + " 透明检测应为 false");
        assert(bullet.手雷检测 == false, bullet.子弹种类 + " 手雷检测应为 false");
        assert(bullet.爆炸检测 == false, bullet.子弹种类 + " 爆炸检测应为 false");
        assert(bullet.普通检测 == true, bullet.子弹种类 + " 普通检测应为 true");
        
        // 测试 baseAsset
        assert(bullet.baseAsset == "精制普通子弹", "baseAsset 应为 '精制普通子弹'");
    }
    
    // 测试冰冷普通子弹
    private static function testIceNormalBullet():Void {
        var bullet:Object = { 子弹种类: "冰冷普通子弹" };
        BulletTypesetter.setTypeFlags(bullet);
        
        assert(bullet.近战检测 == false, bullet.子弹种类 + " 近战检测应为 false");
        assert(bullet.联弹检测 == false, bullet.子弹种类 + " 联弹检测应为 false");
        assert(bullet.穿刺检测 == false, bullet.子弹种类 + " 穿刺检测应为 false");
        assert(bullet.透明检测 == false, bullet.子弹种类 + " 透明检测应为 false");
        assert(bullet.手雷检测 == false, bullet.子弹种类 + " 手雷检测应为 false");
        assert(bullet.爆炸检测 == false, bullet.子弹种类 + " 爆炸检测应为 false");
        assert(bullet.普通检测 == true, bullet.子弹种类 + " 普通检测应为 true");
        
        // 测试 baseAsset
        assert(bullet.baseAsset == "冰冷普通子弹", "baseAsset 应为 '冰冷普通子弹'");
    }
    
    // 测试加强普通子弹
    private static function testEnhancedBullet():Void {
        var bullet:Object = { 子弹种类: "加强普通子弹" };
        BulletTypesetter.setTypeFlags(bullet);
        
        assert(bullet.近战检测 == false, bullet.子弹种类 + " 近战检测应为 false");
        assert(bullet.联弹检测 == false, bullet.子弹种类 + " 联弹检测应为 false");
        assert(bullet.穿刺检测 == false, bullet.子弹种类 + " 穿刺检测应为 false");
        assert(bullet.透明检测 == false, bullet.子弹种类 + " 透明检测应为 false");
        assert(bullet.手雷检测 == false, bullet.子弹种类 + " 手雷检测应为 false");
        assert(bullet.爆炸检测 == false, bullet.子弹种类 + " 爆炸检测应为 false");
        assert(bullet.普通检测 == true, bullet.子弹种类 + " 普通检测应为 true");
        
        // 测试 baseAsset
        assert(bullet.baseAsset == "加强普通子弹", "baseAsset 应为 '加强普通子弹'");
    }
    
    // 测试新电球
    private static function testBallBullet():Void {
        var bullet:Object = { 子弹种类: "新电球" };
        BulletTypesetter.setTypeFlags(bullet);
        
        assert(bullet.近战检测 == false, bullet.子弹种类 + " 近战检测应为 false");
        assert(bullet.联弹检测 == false, bullet.子弹种类 + " 联弹检测应为 false");
        assert(bullet.穿刺检测 == false, bullet.子弹种类 + " 穿刺检测应为 false");
        assert(bullet.透明检测 == false, bullet.子弹种类 + " 透明检测应为 false");
        assert(bullet.手雷检测 == false, bullet.子弹种类 + " 手雷检测应为 false");
        assert(bullet.爆炸检测 == false, bullet.子弹种类 + " 爆炸检测应为 false");
        assert(bullet.普通检测 == false, bullet.子弹种类 + " 普通检测应为 false");
        
        // 测试 baseAsset
        assert(bullet.baseAsset == "新电球", "baseAsset 应为 '新电球'");
    }
    
    // ------------------------
    // baseAsset 缓存测试
    // ------------------------
    
    // 测试 getBaseAsset 方法
    private static function testGetBaseAsset():Void {
        var 子弹种类List:Array = [
            "近战子弹",
            "联弹子弹",
            "穿刺子弹",
            "透明子弹",
            "手雷子弹",
            "爆炸子弹",
            "普通子弹",
            "能量子弹",
            "精制子弹",
            "近战联弹穿刺",
            "精制联弹透明子弹",
            "未知子弹",
            "近战爆炸子弹",
            "精制普通子弹",
            "冰冷普通子弹",
            "加强普通子弹",
            "新电球"
        ];
        
        for (var i:Number = 0; i < 子弹种类List.length; i++) {
            var 子弹种类:String = 子弹种类List[i];
            var expectedBaseAsset:String = 子弹种类.split("-")[0];
            var actualBaseAsset:String = BulletTypesetter.getBaseAsset(子弹种类);
            
            assert(actualBaseAsset == expectedBaseAsset, 
                   "getBaseAsset('" + 子弹种类 + "') 应为 '" + expectedBaseAsset + 
                   "', 实际为 '" + actualBaseAsset + "'");
        }
    }
    
    // ------------------------
    // 运行所有功能测试
    // ------------------------
    
    public static function runAllTests():Void {
        trace("Running BulletTypesetter Tests...");
        
        try {
            // 基础功能测试
            testMeleeBullet();
            trace("testMeleeBullet passed.");
            
            testChainBullet();
            trace("testChainBullet passed.");
            
            testPierceBullet();
            trace("testPierceBullet passed.");
            
            testTransparencyBullet();
            trace("testTransparencyBullet passed.");
            
            testGrenadeBullet();
            trace("testGrenadeBullet passed.");
            
            testExplosiveBullet();
            trace("testExplosiveBullet passed.");
            
            testNormalBullet();
            trace("testNormalBullet passed.");
            
            testEnergyBullet();
            trace("testEnergyBullet passed.");
            
            testRefinedBullet();
            trace("testRefinedBullet passed.");
            
            testNewEnergyBullet();
            trace("testNewEnergyBullet passed.");
            
            testBigEnergyBullet();
            trace("testBigEnergyBullet passed.");
            
            testRefinedChainTransparencyBullet();
            trace("testRefinedChainTransparencyBullet passed.");
            
            testCombinedBullet();
            trace("testCombinedBullet passed.");
            
            testMultipleKeywordsNonTransparent();
            trace("testMultipleKeywordsNonTransparent passed.");
            
            testMultipleKeywordsTransparent();
            trace("testMultipleKeywordsTransparent passed.");
            
            // 边界条件测试
            testUnknownBullet();
            trace("testUnknownBullet passed.");
            
            testEmptyBullet();
            trace("testEmptyBullet passed.");
            
            testRefinedNormalBullet();
            trace("testRefinedNormalBullet passed.");
            
            testIceNormalBullet();
            trace("testIceNormalBullet passed.");
            
            testEnhancedBullet();
            trace("testEnhancedBullet passed.");
            
            testBallBullet();
            trace("testBallBullet passed.");
            
            // baseAsset 缓存测试
            testGetBaseAsset();
            trace("testGetBaseAsset passed.");
            
            trace("All BulletTypesetter Tests Passed Successfully.");
        } catch (e:Error) {
            trace("Test Failed: " + e.message);
        }
    }
    
    // ------------------------
    // 性能测试
    // ------------------------
    
    public static function runPerformanceTest():Void {
        var iterations:Number = 10000;
        var bullet:Object;
        var 子弹种类List:Array = [
            "近战子弹",
            "联弹子弹",
            "穿刺子弹",
            "透明子弹",
            "手雷子弹",
            "爆炸子弹",
            "普通子弹",
            "能量子弹",
            "精制子弹",
            "近战联弹穿刺",
            "精制联弹透明子弹",
            "未知子弹",
            "近战爆炸子弹",
            "精制普通子弹",
            "冰冷普通子弹",
            "加强普通子弹",
            "新电球"
        ];
        
        // 测试对象缓存实现
        BulletTypesetter.clearCache(); // 确保缓存为空
        var startTime1:Number = getTimer();
        for (var i:Number = 0; i < iterations; i++) {
            bullet = { 子弹种类: 子弹种类List[i % 子弹种类List.length] };
            BulletTypesetter.setTypeFlags(bullet);
        }
        var endTime1:Number = getTimer();
        trace("Object Cache Implementation Time: " + (endTime1 - startTime1) + " ms");
        
        // 测试位标志缓存实现
        // 由于已经使用位标志优化，我们无需区分两种实现
        // 这里只是再次运行测试以观察性能
        BulletTypesetter.clearCache(); // 确保缓存为空
        var startTime2:Number = getTimer();
        for (var j:Number = 0; j < iterations; j++) {
            bullet = { 子弹种类: 子弹种类List[j % 子弹种类List.length] };
            BulletTypesetter.setTypeFlags(bullet);
        }
        var endTime2:Number = getTimer();
        trace("Bit Flags Implementation Time: " + (endTime2 - startTime2) + " ms");
        
        // 注意：在实际比较中，应将原始和优化后的实现分开测试
    }
    
    // ------------------------
    // 入口方法
    // ------------------------
    
    public static function main():Void {
        runAllTests();
        runPerformanceTest();
    }
}
