/* 
 * 文件：org/flashNight/arki/audio/states/BaseMusicState.as
 * 说明：音乐状态机各状态的基础类，封装了设置音乐播放器的公共接口。
 */
 
import org.flashNight.neur.StateMachine.*;
import org.flashNight.arki.audio.*;

class org.flashNight.arki.audio.states.BaseMusicState extends FSM_Status {
    // 供各状态调用的音乐播放接口
    protected var musicPlayer:IMusicPlayer;
    
    public function BaseMusicState(_onAction:Function, _onEnter:Function, _onExit:Function) {
        // 可传入 null，后续各状态可重写这三个方法
        super(_onAction, _onEnter, _onExit);
        this.active = true;
    }
    
    // 供外部设置音乐播放器（以便后续管理音频对象内存分配）
    public function setMusicPlayer(player:IMusicPlayer):Void {
        this.musicPlayer = player;
    }
}
