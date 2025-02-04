/* 
 * 文件：org/flashNight/arki/audio/MusicEngine.as
 * 说明：音乐系统的状态机实现。内部组合了各个音乐状态，并对外提供 handleCommand 接口，
 *       以便后续接入事件系统（不直接耦合事件系统，仅暴露接口）。
 */

import org.flashNight.neur.StateMachine.*;
import org.flashNight.arki.audio.*;
import org.flashNight.arki.audio.states.*;

class org.flashNight.arki.audio.MusicEngine extends FSM_StateMachine {
    private var musicPlayer:IMusicPlayer;
    
    // 保留各个状态的引用，方便后续扩展和参数设置
    private var idleState:MusicIdleState;
    private var fadeInState:MusicFadeInState;
    private var playingState:MusicPlayingState;
    private var fadeOutState:MusicFadeOutState;
    
    public function MusicEngine(_onAction:Function, _onEnter:Function, _onExit:Function) {
        // 调用 FSM_StateMachine 构造函数
        super(_onAction, _onEnter, _onExit);
        
        // 创建状态实例（构造时传 null 参数，内部可自行重写 onEnter/onAction/onExit）
        idleState    = new MusicIdleState();
        fadeInState  = new MusicFadeInState();
        playingState = new MusicPlayingState();
        fadeOutState = new MusicFadeOutState();
        
        // 添加状态到状态机（状态名为后续转换的关键字）
        this.AddStatus("idle", idleState);
        this.AddStatus("fadein", fadeInState);
        this.AddStatus("playing", playingState);
        this.AddStatus("fadeout", fadeOutState);
        
        // 添加默认转换：淡入状态完成后切换到播放状态
        this.transitions.AddTransition("fadein", "playing", function():Boolean {
            // this 指向 MusicEngine（状态机），当前状态应为 fadeInState
            var state = this.getActiveState();
            // 要求状态提供 isComplete 方法来判断渐变是否结束
            if (state.isComplete != undefined && state.isComplete()) {
                return true;
            }
            return false;
        });
        
        // 添加默认转换：淡出状态完成后切换到空闲状态
        this.transitions.AddTransition("fadeout", "idle", function():Boolean {
            var state = this.getActiveState();
            if (state.isComplete != undefined && state.isComplete()) {
                return true;
            }
            return false;
        });
        
        // 默认进入空闲状态
        this.ChangeState("idle");
    }
    
    // 允许外部注入具体的音乐播放实现（例如由 AudioEngine 提供）
    public function setMusicPlayer(player:IMusicPlayer):Void {
        this.musicPlayer = player;
        idleState.setMusicPlayer(player);
        fadeInState.setMusicPlayer(player);
        playingState.setMusicPlayer(player);
        fadeOutState.setMusicPlayer(player);
    }
    
    /**
     * 对外接口：处理外部指令。注意，这里不直接绑定事件系统，仅提供一个可被外部调用的接口。
     * 可接受的 command 如 "play"（播放）、"stop"（停止）等，params 可用于传递更多参数。
     */
    public function handleCommand(command:String, params:Object):Void {
        switch(command) {
            case "play":
                // 播放时先进入淡入状态
                this.ChangeState("fadein");
                break;
            case "stop":
                // 停止时进入淡出状态
                this.ChangeState("fadeout");
                break;
            // 后续可以扩展 pause/resume 等命令
            default:
                // 未知命令，可记录日志或忽略
                break;
        }
    }
    
    // 如有需要，可以在 onAction 中加入音乐引擎级别的逻辑
    public function onAction():Void {
        super.onAction();
        // 例如，可在此处监控当前播放状态、处理资源回收等
    }
}
