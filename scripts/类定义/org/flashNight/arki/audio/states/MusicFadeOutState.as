/* 
 * 文件：org/flashNight/arki/audio/states/MusicFadeOutState.as
 * 说明：淡出状态，通过计时检测淡出过程是否完成，然后自动切换到 Idle 状态。
 */
 
import org.flashNight.arki.audio.states.BaseMusicState;

class org.flashNight.arki.audio.states.MusicFadeOutState extends BaseMusicState {
    private var elapsed:Number;
    
    public function MusicFadeOutState() {
        super(null, null, null);
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
        trace("[MusicFadeOutState] Fading out... " + elapsed + "/" + fadeDuration + " frames");
    }
    
    public function onExit():Void {
        trace("MusicFadeOutState: Exiting FadeOut State");
    }
    
    public function isComplete():Boolean {
        return elapsed >= fadeDuration;
    }
}
