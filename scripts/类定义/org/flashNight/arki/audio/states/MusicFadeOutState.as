/* 
 * 文件：org/flashNight/arki/audio/states/MusicFadeOutState.as
 * 说明：淡出状态，进入时启动淡出效果，计时结束后可切换到空闲状态。
 */
 
import org.flashNight.arki.audio.states.*;

class org.flashNight.arki.audio.states.MusicFadeOutState extends BaseMusicState {
    private var fadeDuration:Number;
    private var elapsed:Number;
    
    public function MusicFadeOutState() {
        super(null, null, null);
        fadeDuration = 60; // 默认 60 帧内完成淡出
        elapsed = 0;
    }
    
    public function onEnter():Void {
        trace("MusicFadeOutState: Entering FadeOut State");
        elapsed = 0;
        if (musicPlayer != null) {
            musicPlayer.fadeOut(fadeDuration);
        }
    }
    
    public function onAction():Void {
        elapsed++;
    }
    
    public function onExit():Void {
        trace("MusicFadeOutState: Exiting FadeOut State");
    }
    
    public function isComplete():Boolean {
        return elapsed >= fadeDuration;
    }
}
