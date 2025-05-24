/* 
 * 文件：org/flashNight/arki/audio/states/MusicFadeInState.as
 * 说明：淡入状态，通过计时检测淡入过程是否完成，然后由状态机自动切换到播放状态。
 */
 
import org.flashNight.arki.audio.states.BaseMusicState;

class org.flashNight.arki.audio.states.MusicFadeInState extends BaseMusicState {
    private var elapsed:Number;
    
    public function MusicFadeInState() {
        super(null, null, null);
        elapsed = 0;
    }
    
    public function onEnter():Void {
        trace("MusicFadeInState: Entering FadeIn State");
        elapsed = 0;
        if (musicPlayer != null) {
            musicPlayer.fadeIn(fadeDuration);
        }
    }
    
    public function onAction():Void {
        elapsed++;
        // 可选：逐帧输出淡入进度
        trace("[MusicFadeInState] Fading in... " + elapsed + "/" + fadeDuration + " frames");
    }
    
    public function onExit():Void {
        trace("MusicFadeInState: Exiting FadeIn State");
    }
    
    public function isComplete():Boolean {
        return elapsed >= fadeDuration;
    }
}
