/* 
 * 文件：org/flashNight/arki/audio/states/MusicIdleState.as
 * 说明：空闲状态，进入该状态时停止音乐播放。
 */
 
import org.flashNight.arki.audio.states.BaseMusicState;

class org.flashNight.arki.audio.states.MusicIdleState extends BaseMusicState {
    
    public function MusicIdleState() {
        super(null, null, null);
    }
    
    public function onEnter():Void {
        trace("MusicIdleState: Entering Idle State");
        if (musicPlayer != null) {
            musicPlayer.stop();
        }
    }
    
    public function onAction():Void {
        // 空闲状态下等待外部命令
    }
    
    public function onExit():Void {
        trace("MusicIdleState: Exiting Idle State");
    }
}
