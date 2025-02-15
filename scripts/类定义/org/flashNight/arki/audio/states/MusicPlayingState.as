/* 
 * 文件：org/flashNight/arki/audio/states/MusicPlayingState.as
 * 说明：播放状态，进入后开始播放曲目，并支持播放完成检测、循环控制及参数调整。
 */
 
import org.flashNight.arki.audio.states.BaseMusicState;

class org.flashNight.arki.audio.states.MusicPlayingState extends BaseMusicState {
    // 模拟播放进度计数（在真实实现中应由播放器反馈）
    private var playFrames:Number;
    // 模拟的曲目总帧数（用作播放完成的判断）
    public var trackLength:Number = 300; // 例如300帧
    
    // 当前播放曲目
    public var clip:String = "";
    // 当前优先级（由 MusicEngine 传入）
    public var priority:Number = 0;
    
    public function MusicPlayingState() {
        super(null, null, null);
        playFrames = 0;
    }
    
    public function onEnter():Void {
        trace("MusicPlayingState: Entering Playing State with clip: " + clip + " (priority:" + priority + ")");
        playFrames = 0;
        if (musicPlayer != null) {
            musicPlayer.setVolume(targetVolume);
            musicPlayer.setLoop(loop);
            musicPlayer.play(clip);
        }
    }
    
    public function onAction():Void {
        playFrames++;
        // 模拟播放完成检测
        if (playFrames >= trackLength) {
            trace("MusicPlayingState: Playback complete detected");
            // 交由 MusicEngine 根据循环标志处理完成事件（例如发送 complete 命令）
        }
        // 可添加其它动态调整逻辑
    }
    
    public function onExit():Void {
        trace("MusicPlayingState: Exiting Playing State");
    }
    
    // 用于外部调整参数（例如调整音量、loop等）
    public function adjustParameters(newVolume:Number, newFadeDuration:Number, newLoop:Boolean):Void {
        targetVolume = newVolume;
        fadeDuration = newFadeDuration;
        loop = newLoop;
        if(musicPlayer != null){
            musicPlayer.setVolume(newVolume);
            musicPlayer.setLoop(newLoop);
        }
        trace("MusicPlayingState: Parameters adjusted: volume=" + newVolume + ", fadeDuration=" + newFadeDuration + ", loop=" + newLoop);
    }
}
