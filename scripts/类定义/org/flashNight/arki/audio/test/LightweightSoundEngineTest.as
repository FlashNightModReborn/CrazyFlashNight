/**
 * 文件：org/flashNight/arki/audio/test/LightweightSoundEngineTest.as
 * 说明：测试轻量化音效引擎 LightweightSoundEngine 的核心功能，包括播放、间隔控制、分类、音量调整等。
 */

import org.flashNight.arki.audio.LightweightSoundEngine;
import org.flashNight.arki.audio.SoundPreprocessor;

class org.flashNight.arki.audio.test.LightweightSoundEngineTest {
    
    private var engine:LightweightSoundEngine;
    private var preprocessor:SoundPreprocessor;
    
    public function LightweightSoundEngineTest() {
        trace("===== LightweightSoundEngineTest Begin =====");
        
        // 1. 创建 SoundPreprocessor 并预填充测试数据（避免实际加载 SWF/XML）
        preprocessor = createMockPreprocessor();
        
        // 2. 创建 LightweightSoundEngine 实例
        engine = new LightweightSoundEngine(preprocessor);
        
        // 3. 执行测试用例
        testPlaySound();        // 测试正常播放
        testMinInterval();      // 测试播放间隔限制
        testInvalidSoundId();   // 测试无效音效 ID
        testCategoryHandling(); // 测试分类是否正确
        testVolumeControl();    // 测试音量调整
        testStopCommand();      // 测试停止功能
        
        trace("===== LightweightSoundEngineTest End =====");
    }
    
    /**
     * 创建一个模拟的 SoundPreprocessor，填充测试用 soundSourceDict
     */
    private function createMockPreprocessor():SoundPreprocessor {
        var mockPreprocessor:SoundPreprocessor = new SoundPreprocessor(_root); // 使用 _root 作为容器
        
        // 手动填充 soundSourceDict（模拟 XML 加载后的数据）
        mockPreprocessor.soundSourceDict = {
            sword_attack: "武器",
            fire_effect: "特效",
            hero_jump: "人物",
            for_set_volume: "特效",
            invalid_sound: "未知分类" // 测试错误分类
        };
        
        // 创建模拟分类 MovieClip
        mockPreprocessor.soundManager.createEmptyMovieClip("武器", 1);
        mockPreprocessor.soundManager.createEmptyMovieClip("特效", 2);
        mockPreprocessor.soundManager.createEmptyMovieClip("人物", 3);
        
        return mockPreprocessor;
    }
    
    // 测试用例 1: 正常播放音效
    private function testPlaySound():Void {
        trace(">>> Test Case 1: Normal Play");
        engine.handleCommand("play", {soundId: "sword_attack", volumeMultiplier: 1.0, source: "武器"});
        // 验证 soundLastTime 是否更新
        var lastTime:Number = preprocessor.soundLastTime["sword_attack"];
        if (!isNaN(lastTime)) {
            trace("  [PASS] soundLastTime updated for sword_attack");
        } else {
            trace("  [FAIL] soundLastTime not updated");
        }
    }
    
    // 测试用例 2: 播放间隔限制
    private function testMinInterval():Void {
        trace(">>> Test Case 2: Minimum Interval Check");
        // 第一次播放
        engine.handleCommand("play", {soundId: "fire_effect"});
        var firstPlayTime:Number = getTimer();
        preprocessor.soundLastTime["fire_effect"] = firstPlayTime - 50; // 设定 50ms 前播放过
        
        // 立即尝试再次播放（间隔 50ms < 90ms）
        engine.handleCommand("play", {soundId: "fire_effect"});
        // 预期：触发忽略，查看 trace 输出是否包含忽略信息
    }
    
    // 测试用例 3: 无效音效 ID
    private function testInvalidSoundId():Void {
        trace(">>> Test Case 3: Invalid Sound ID");
        engine.handleCommand("play", {soundId: "non_existing_sound"}); // 预期错误
    }
    
    // 测试用例 4: 分类是否正确处理
    private function testCategoryHandling():Void {
        trace(">>> Test Case 4: Category Handling");
        // 使用预定义的分类
        engine.handleCommand("play", {soundId: "hero_jump"}); // 应属于 "人物" 分类
        // 应检查是否在正确的 MovieClip 下创建了 Sound 对象
        var soundObj:Sound = preprocessor.soundDict["hero_jump"];
        if (soundObj != null) {
            trace("  [PASS] Sound object created for hero_jump in 人物 category");
        } else {
            trace("  [FAIL] Sound object not created");
        }
        
        // 测试无效分类
        engine.handleCommand("play", {soundId: "invalid_sound"}); // 分类为 "未知分类"
    }
    
    // 测试用例 5: 音量控制
    private function testVolumeControl():Void {
        trace(">>> Test Case 5: Volume Adjustment");
        // 设置全局音量为 50%
        engine.setVolume(50);
        // 播放音效并验证音量计算
        engine.handleCommand("play", {soundId: "for_set_volume", volumeMultiplier: 0.8});
        // 预期音量计算：假设 _root.音效音量 = 100 → 100 * 0.8 * 0.5 = 40
        var soundObj:Sound = preprocessor.soundDict["for_set_volume"];
        if (soundObj.getVolume() == 40) {
            trace("  [PASS] Volume correctly set to 40");
        } else {
            trace("  [FAIL] Volume is " + soundObj.getVolume() + ", expected 40");
        }
    }
    
    // 测试用例 6: 停止功能
    // 修改 testStopCommand 中的音效播放完成监听
    private function testStopCommand():Void {
        trace(">>> Test Case 6: Stop Command");
        engine.handleCommand("play", {soundId: "hero_jump"}); // 播放音效
        
        // 注入 onSoundComplete 事件，监听音效播放完成
        var soundObj:Sound = preprocessor.soundDict["hero_jump"];
        soundObj.onSoundComplete = function():Void {
            trace("[LightweightSoundEngineTest] Sound hero_jump completed.");
            // 在这里处理停止后的验证逻辑
            var currentVolume:Number = soundObj.getVolume(); // 音量应为 0 表示停止
            if (currentVolume == 0) {
                trace("  [PASS] Sound stopped successfully");
            } else {
                trace("  [FAIL] Sound still playing after stop");
            }
        };
        
        // 触发停止命令
        engine.stop();
    }

    
    public static function main():Void {
        new LightweightSoundEngineTest();
    }
}