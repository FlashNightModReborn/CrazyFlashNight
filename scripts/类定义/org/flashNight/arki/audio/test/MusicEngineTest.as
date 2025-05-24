/**
 * 文件：org/flashNight/arki/audio/test/MusicEngineTest.as
 * 说明：测试扩展后的音乐状态机，通过 trace 输出来观察各命令及状态转换情况。
 */

import org.flashNight.arki.audio.MusicEngine;
import org.flashNight.arki.audio.SimMusicPlayer;

class org.flashNight.arki.audio.test.MusicEngineTest {
    
    private var engine:MusicEngine;
    
    public function MusicEngineTest() {
        trace("===== MusicEngineTest Begin =====");
        
        // 1) 创建 MusicEngine，并注入 SimMusicPlayer
        engine = new MusicEngine(null, null, null);
        engine.setMusicPlayer(new SimMusicPlayer());
        
        // 初始状态查询
        engine.handleCommand("query", null);
        
        // 2) Issue 'play' 命令：播放主背景音乐，优先级为 5，循环开启
        trace(">>> Issue 'play' command");
        engine.handleCommand("play", {clip:"bgm_main", priority:5, fadeDuration:60, loop:true, volume:80});
        
        // 模拟 70 帧运行，完成淡入
        for (var i:Number = 0; i < 70; i++) {
            engine.onAction();
        }
        
        // 查询状态
        engine.handleCommand("query", null);
        
        // 3) 尝试发出低优先级 'switch' 命令（优先级 3），应被忽略
        trace(">>> Issue 'switch' command with low priority (3) - should be ignored");
        engine.handleCommand("switch", {clip:"bgm_low_priority", priority:3, fadeDuration:15});
        engine.handleCommand("query", null);
        
        // 4) 发出高优先级 'switch' 命令（优先级 7），切换曲目
        trace(">>> Issue 'switch' command with high priority (7)");
        engine.handleCommand("switch", {clip:"bgm_battle", priority:7, fadeDuration:15, loop:false, volume:90});
        // 模拟淡出与淡入过程：先执行淡out
        for (var j:Number = 0; j < 60; j++) {
            engine.onAction();
        }
        // 为简化测试，手动调用 'play' 命令以触发新曲淡入（实际可通过延时或转换自动触发）
        // engine.handleCommand("play", {clip:"bgm_battle", priority:7, fadeDuration:60, loop:false, volume:90});
        // for (var k:Number = 0; k < 30; k++) {
        //     engine.onAction();
        // }
        // engine.handleCommand("query", null);
        
        // 5) 测试 'adjust' 命令：调整当前播放音量与循环标志
        trace(">>> Issue 'adjust' command");
        engine.handleCommand("adjust", {volume:70, fadeDuration:30, loop:true, priority:7});
        engine.handleCommand("query", null);
        
        // 6) 测试 'jump' 命令：跳转播放位置
        trace(">>> Issue 'jump' command");
        engine.handleCommand("jump", {position:120});
        
        // 7) 测试 'mute' 命令（优先级 10）
        trace(">>> Issue 'mute' command");
        engine.handleCommand("mute", {priority:10, fadeDuration:30});
        for (var m:Number = 0; m < 40; m++) {
            engine.onAction();
        }
        engine.handleCommand("query", null);
        
        // 8) 测试 'unmute' 命令，恢复播放
        trace(">>> Issue 'unmute' command");
        engine.handleCommand("unmute", {priority:10, fadeDuration:30});
        for (var n:Number = 0; n < 40; n++) {
            engine.onAction();
        }
        engine.handleCommand("query", null);
        
        // 9) 模拟播放完成（complete）
        trace(">>> Issue 'complete' command (simulate playback complete)");
        engine.handleCommand("complete", null);
        engine.handleCommand("query", null);
        
        // 10) 测试 'stop' 命令
        trace(">>> Issue 'stop' command");
        engine.handleCommand("stop", null);
        for (var p:Number = 0; p < 30; p++) {
            engine.onAction();
        }
        engine.handleCommand("query", null);
        
        trace("===== MusicEngineTest End =====");
    }
    
    // 入口方法，可在 AS2 环境中指定为文档类或在舞台第一帧脚本中实例化
    public static function main():Void {
        new MusicEngineTest();
    }
}
