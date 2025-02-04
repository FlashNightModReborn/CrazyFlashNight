/* 
 * 文件：org/flashNight/arki/audio/states/MusicPlayingState.as
 * 说明：播放状态，进入后确保音乐处于正常播放状态。
 */
 
import org.flashNight.arki.audio.states.*;

class org.flashNight.arki.audio.states.MusicPlayingState extends BaseMusicState {
    
    public function MusicPlayingState() {
        super(null, null, null);
    }
    
    public function onEnter():Void {
        trace("MusicPlayingState: Entering Playing State");
        if (musicPlayer != null) {
            // 例如，确保音量已调至正常水平
            musicPlayer.setVolume(100);
        }
    }
    
    public function onAction():Void {
        // 播放状态下可以添加一些监控逻辑，如检测播放进度等
    }
    
    public function onExit():Void {
        trace("MusicPlayingState: Exiting Playing State");
    }
}
