/* 
 * 文件：org/flashNight/arki/audio/states/MusicMuteState.as
 * 说明：静音状态，进入时渐变静音并调用 mute，保持静音状态，等待 unmute 命令切换回播放状态。
 */
 
import org.flashNight.arki.audio.states.BaseMusicState;

class org.flashNight.arki.audio.states.MusicMuteState extends BaseMusicState {
    private var elapsed:Number;
    
    public function MusicMuteState() {
        super(null, null, null);
        elapsed = 0;
    }
    
    public function onEnter():Void {
        trace("MusicMuteState: Entering Mute State");
        elapsed = 0;
        if(musicPlayer != null){
            // 以 fadeDuration 渐变静音
            musicPlayer.fadeOut(fadeDuration);
        }
    }
    
    public function onAction():Void {
        elapsed++;
        trace("[MusicMuteState] Muting... " + elapsed + "/" + fadeDuration + " frames");
        if(elapsed >= fadeDuration && musicPlayer != null){
            musicPlayer.mute();
        }
    }
    
    public function onExit():Void {
        trace("MusicMuteState: Exiting Mute State");
    }
    
    public function isComplete():Boolean {
        return elapsed >= fadeDuration;
    }
}
