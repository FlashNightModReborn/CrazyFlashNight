import org.flashNight.arki.audio.MusicPlayer;
import org.flashNight.gesh.path.PathManager;

class org.flashNight.arki.audio.test.MusicPlayerTest {
    
    private var player:MusicPlayer;
    // 测试使用的音频文件路径（请确保该文件存在）
    private var testMusicUrl:String = "sounds/Kevin Macleod/Decisions.mp3";
    // 测试步骤队列，每个对象包含名称、执行函数及延时（单位：毫秒）
    private var tests:Array;
    private var currentTestIndex:Number = 0;
    
    public function MusicPlayerTest() {
        // 创建 MusicPlayer 实例
        player = new MusicPlayer();
        
        // 定义测试步骤及各自延时
        tests = [
            { name: "预加载测试",         func: testPreload,       delay: 2000 },
            { name: "播放预加载音频测试",   func: testPlayPreloaded, delay: 4000 },
            { name: "停止播放测试",         func: testStop,          delay: 2000 },
            { name: "音量设置测试",         func: testSetVolume,     delay: 4000 },
            { name: "淡入效果测试",         func: testFadeIn,        delay: 4000 },
            { name: "淡出效果测试",         func: testFadeOut,       delay: 4000 },
            { name: "静音/取消静音测试",    func: testMuteUnmute,    delay: 4000 },
            { name: "跳转播放位置测试",      func: testJumpTo,        delay: 4000 },
            { name: "循环播放测试",         func: testLoop,          delay: 6000 }
        ];
        
        trace("==== 开始 MusicPlayer 测试 ====");
        runNextTest();
    }
    
    /**
     * 依次执行测试步骤，每个步骤结束后延时继续下一个测试。
     */
    private function runNextTest():Void {
        if (currentTestIndex < tests.length) {
            var testObj:Object = tests[currentTestIndex];
            trace("\n==== " + testObj.name + " ====");
            // 执行当前测试步骤
            testObj.func.apply(this);
            currentTestIndex++;
            // 注意：由于 AS2 中匿名函数 this 丢失，因此用 self 保存当前实例引用
            var self:MusicPlayerTest = this;
            setTimeout(function():Void {
                self.runNextTest();
            }, testObj.delay);
        } else {
            trace("\n==== 所有测试结束 ====");
        }
    }
    
    /**
     * 测试预加载功能
     */
    private function testPreload():Void {
        trace("调用 preLoad(" + testMusicUrl + ")");
        player.preLoad(testMusicUrl);
    }
    
    /**
     * 测试预加载成功后直接播放音频
     */
    private function testPlayPreloaded():Void {
        trace("调用 play(" + testMusicUrl + ") - 应直接播放预加载音频");
        player.play(testMusicUrl);
    }
    
    /**
     * 测试停止播放功能
     */
    private function testStop():Void {
        trace("调用 stop() 停止播放");
        player.stop();
    }
    
    /**
     * 测试音量调整功能：
     * 播放音频后依次将音量调整为 50、100、0，便于观察效果
     */
    private function testSetVolume():Void {
        trace("开始音量设置测试");
        // 播放音频，便于观察音量变化
        player.play(testMusicUrl);
        setTimeout(function():Void {
            trace("设置音量为 50");
            player.setVolume(50);
        }, 1000);
        setTimeout(function():Void {
            trace("设置音量为 100");
            player.setVolume(100);
        }, 2000);
        setTimeout(function():Void {
            trace("设置音量为 0");
            player.setVolume(0);
        }, 3000);
    }
    
    /**
     * 测试淡入效果：先停止播放，再调用淡入方法后播放
     */
    private function testFadeIn():Void {
        trace("开始淡入效果测试");
        player.stop();
        var self:MusicPlayerTest = this;
        var fade_player:MusicPlayer = player;
        var selfUrl:String = testMusicUrl;
        setTimeout(function():Void {
            trace("调用 fadeIn(5) 并播放音频");
            fade_player.play(selfUrl);
            fade_player.setVolume(100); // 恢复目标音量
            fade_player.fadeIn(5);
        }, 500);
    }
    
    /**
     * 测试淡出效果：播放音频后延时调用淡出方法
     */
    private function testFadeOut():Void {
        trace("开始淡出效果测试");
        var fade_player:MusicPlayer = player;
        fade_player.play(testMusicUrl);
        fade_player.setVolume(100); // 恢复目标音量
        setTimeout(function():Void {
            trace("调用 fadeOut(5)");
            fade_player.fadeOut(5);
        }, 1000);
    }
    
    /**
     * 测试静音和取消静音：播放音频后依次静音，再取消静音
     */
    private function testMuteUnmute():Void {
        trace("开始静音与取消静音测试");
        player.play(testMusicUrl);
        setTimeout(function():Void {
            trace("调用 mute()");
            player.mute();
        }, 1000);
        setTimeout(function():Void {
            trace("调用 unmute()");
            player.unmute();
        }, 2000);
    }
    
    /**
     * 测试跳转播放位置：播放音频后延时调用 jumpTo 跳转到指定位置
     */
    private function testJumpTo():Void {
        trace("开始跳转播放位置测试");
        player.play(testMusicUrl);
        setTimeout(function():Void {
            trace("调用 jumpTo(10)");
            player.jumpTo(10);
        }, 1000);
    }
    
    /**
     * 测试循环播放：设置循环播放后播放音频，延时关闭循环并停止播放
     */
    private function testLoop():Void {
        trace("开始循环播放测试");
        player.setLoop(true);
        player.play(testMusicUrl);
        setTimeout(function():Void {
            trace("关闭循环播放并调用 stop()");
            player.setLoop(false);
            player.stop();
        }, 5000);
    }
}
