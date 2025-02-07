import org.flashNight.arki.audio.MusicPlayer;
import org.flashNight.gesh.path.PathManager;

class org.flashNight.arki.audio.test.MusicPlayerTest {

    private var player:MusicPlayer;
    private static var testMusicUrl:String = "sounds/Kevin Macleod/Decisions.mp3";

    public function MusicPlayerTest() {
        player = new MusicPlayer();  // 创建 MusicPlayer 实例
        startTests();  // 启动测试
    }

    // 启动所有测试
    private function startTests():Void {
        trace("开始 MusicPlayer 测试");

        // 播放测试
        testPlay();
        
        // 停止播放测试
        testStop();
        
        // 音量设置测试
        testSetVolume();
        
        // 淡入效果测试
        testFadeIn();
        
        // 淡出效果测试
        testFadeOut();
        
        // 静音测试
        testMuteUnmute();
        
        // 跳转播放位置测试
        testJumpTo();
        
        // 预加载测试
        testPreload();
        
        // 循环播放测试
        testLoop();
    }

    // 播放测试
    private function testPlay():Void {
        trace("测试播放");
        player.play(testMusicUrl);  // 假设文件存在
    }

    // 停止播放测试
    private function testStop():Void {
        trace("测试停止播放");
        player.stop();
    }

    // 音量设置测试
    private function testSetVolume():Void {
        trace("测试音量设置");
        player.setVolume(50);  // 设置音量为 50
        player.setVolume(100); // 设置音量为 100
        player.setVolume(0);   // 设置音量为 0
    }

    // 淡入效果测试
    private function testFadeIn():Void {
        trace("测试淡入效果");
        player.fadeIn(30);  // 在 30 帧内淡入
    }

    // 淡出效果测试
    private function testFadeOut():Void {
        trace("测试淡出效果");
        player.fadeOut(30);  // 在 30 帧内淡出
    }

    // 静音和取消静音测试
    private function testMuteUnmute():Void {
        trace("测试静音与取消静音");
        player.mute();  // 静音
        player.unmute();  // 取消静音
    }

    // 跳转播放位置测试
    private function testJumpTo():Void {
        trace("测试跳转播放位置");
        player.jumpTo(10);  // 跳转到播放位置 10
    }

    // 预加载测试
    private function testPreload():Void {
        trace("测试预加载音频");
        player.preLoad(testMusicUrl);  // 预加载音频文件
    }

    // 循环播放测试
    private function testLoop():Void {
        trace("测试循环播放");
        player.setLoop(true);  // 启用循环播放
        player.play(testMusicUrl);  // 播放音频
    }
}

