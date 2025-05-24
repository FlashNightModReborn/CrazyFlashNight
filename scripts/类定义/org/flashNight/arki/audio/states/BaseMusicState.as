/* 
 * 文件：org/flashNight/arki/audio/states/BaseMusicState.as
 * 说明：音乐状态机各状态的基础类，封装了设置音乐播放器的公共接口。
 */
 
import org.flashNight.neur.StateMachine.FSM_Status;
import org.flashNight.arki.audio.IMusicPlayer;

class org.flashNight.arki.audio.states.BaseMusicState extends FSM_Status {
    // 供各状态调用的音乐播放接口
    public var musicPlayer:IMusicPlayer;
    
    // 动态参数（各状态可按需使用）
    public var fadeDuration:Number = 20; // 默认淡入淡出时长
    public var targetVolume:Number = 100;  // 正常音量
    public var loop:Boolean = false;       // 循环播放标志
    
    public function BaseMusicState(_onAction:Function, _onEnter:Function, _onExit:Function) {
        super(_onAction, _onEnter, _onExit);
        this.active = true;
    }
    
    // 供外部设置音乐播放器
    public function setMusicPlayer(player:IMusicPlayer):Void {
        this.musicPlayer = player;
    }
}
