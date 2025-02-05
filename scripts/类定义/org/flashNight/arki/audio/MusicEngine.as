/* 
 * 文件：org/flashNight/arki/audio/MusicEngine.as
 * 说明：音乐系统的状态机实现，扩展支持优先级、曲目切换、静音、参数调整、跳转、播放完成等功能。
 *       对外仅提供 handleCommand(command, params) 接口，内部根据 command 及参数控制状态转换。
 */

import org.flashNight.neur.StateMachine.*;
import org.flashNight.arki.audio.*;
import org.flashNight.arki.audio.states.*;

class org.flashNight.arki.audio.MusicEngine extends FSM_StateMachine implements IMusicEngine {
    private var musicPlayer:IMusicPlayer;
    
    // 各状态引用
    private var idleState:MusicIdleState;
    private var fadeInState:MusicFadeInState;
    private var playingState:MusicPlayingState;
    private var fadeOutState:MusicFadeOutState;
    private var muteState:MusicMuteState;
    
    // 当前全局参数（默认优先级 0）
    private var currentPriority:Number = 0;
    // 当前曲目名称（用于 play/switch 命令）
    private var currentClip:String = "";
    // 循环标志
    private var currentLoop:Boolean = false;
    
    public function MusicEngine(_onAction:Function, _onEnter:Function, _onExit:Function) {
        super(_onAction, _onEnter, _onExit);
        
        // 初始化各状态
        idleState    = new MusicIdleState();
        fadeInState  = new MusicFadeInState();
        playingState = new MusicPlayingState();
        fadeOutState = new MusicFadeOutState();
        muteState    = new MusicMuteState();
        
        // 添加状态到状态机
        this.AddStatus("idle", idleState);
        this.AddStatus("fadein", fadeInState);
        this.AddStatus("playing", playingState);
        this.AddStatus("fadeout", fadeOutState);
        this.AddStatus("mute", muteState);
        
        // 添加转换：淡入完成后切换到播放状态
        this.transitions.AddTransition("fadein", "playing", function():Boolean {
            var state = this.getActiveState();
            if(state.isComplete != undefined && state.isComplete()){
                return true;
            }
            return false;
        });
        
        // 转换：淡出完成后切换到空闲状态
        this.transitions.AddTransition("fadeout", "idle", function():Boolean {
            var state = this.getActiveState();
            if(state.isComplete != undefined && state.isComplete()){
                return true;
            }
            return false;
        });
        
        // 默认进入空闲状态
        this.ChangeState("idle");
    }
    
    // 注入具体音乐播放器实现
    public function setMusicPlayer(player:IMusicPlayer):Void {
        this.musicPlayer = player;
        idleState.setMusicPlayer(player);
        fadeInState.setMusicPlayer(player);
        playingState.setMusicPlayer(player);
        fadeOutState.setMusicPlayer(player);
        muteState.setMusicPlayer(player);
    }
    
    /**
     * 对外接口：处理命令（不直接依赖事件系统）
     * 支持命令：
     *  - "play": 播放新曲（参数：clip, priority, fadeDuration, loop, volume）
     *  - "switch": 切换曲目（同 play，但适用于已在播放状态时）
     *  - "stop": 停止播放（无须优先级检测，直接执行淡出）
     *  - "mute": 静音（参数：priority, fadeDuration）
     *  - "unmute": 取消静音（参数：priority, fadeDuration）
     *  - "adjust": 动态调整参数（参数：volume, fadeDuration, loop）
     *  - "jump": 跳转播放位置（参数：position）
     *  - "query": 输出当前状态及参数（无参数）
     *  - "complete": 模拟播放完成（由外部或播放器事件触发）
     */
    public function handleCommand(command:String, params:Object):Void {
        // 检查优先级（对于 play/switch/mute/unmute/adjust 命令）
        var cmdPriority:Number = (params != null && params.priority != undefined) ? params.priority : 0;
        
        // 对于部分命令，不需要进行优先级检查（如 stop, jump, query, complete）
        if(command == "play" || command == "switch" || command == "mute" || command == "unmute" || command == "adjust"){
            if(cmdPriority < currentPriority) {
                trace("[MusicEngine] Command '" + command + "' ignored due to low priority (" + cmdPriority + " < " + currentPriority + ")");
                return;
            }
            // 更新当前优先级
            currentPriority = cmdPriority;
        }
        
        switch(command) {
            case "play":
                if(params == null || params.clip == undefined) {
                    trace("[MusicEngine] Error: 'play' command missing 'clip' parameter.");
                    return;
                }
                currentClip = params.clip;
                currentLoop = (params.loop != undefined) ? params.loop : false;
                // 可调整淡入时长与目标音量
                fadeInState.fadeDuration = (params.fadeDuration != undefined) ? params.fadeDuration : fadeInState.fadeDuration;
                playingState.targetVolume = (params.volume != undefined) ? params.volume : playingState.targetVolume;
                playingState.clip = currentClip;
                playingState.priority = cmdPriority;
                playingState.loop = currentLoop;
                
                trace("[MusicEngine] Processing 'play' command: clip=" + currentClip + ", priority=" + cmdPriority);
                this.ChangeState("fadein");
                break;
                
            case "switch":
                if(params == null || params.clip == undefined) {
                    trace("[MusicEngine] Error: 'switch' command missing 'clip' parameter.");
                    return;
                }
                currentClip = params.clip;
                currentLoop = (params.loop != undefined) ? params.loop : currentLoop;
                fadeInState.fadeDuration = (params.fadeDuration != undefined) ? params.fadeDuration : fadeInState.fadeDuration;
                playingState.targetVolume = (params.volume != undefined) ? params.volume : playingState.targetVolume;
                playingState.clip = currentClip;
                playingState.priority = cmdPriority;
                playingState.loop = currentLoop;
                
                trace("[MusicEngine] Processing 'switch' command: switching to clip=" + currentClip + ", priority=" + cmdPriority);
                // 先淡出当前曲目，再淡入新曲
                this.ChangeState("fadeout");
                // 延后进入 fadein 可由外部控制或通过转换函数扩展（此处简单处理，假设在淡出后调用 play命令）
                break;
                
            case "stop":
                trace("[MusicEngine] Processing 'stop' command");
                currentPriority = 0; // 重置优先级
                this.ChangeState("fadeout");
                break;
                
            case "mute":
                trace("[MusicEngine] Processing 'mute' command with priority " + cmdPriority);
                fadeInState.fadeDuration = (params.fadeDuration != undefined) ? params.fadeDuration : fadeInState.fadeDuration;
                this.ChangeState("mute");
                break;
                
            case "unmute":
                trace("[MusicEngine] Processing 'unmute' command with priority " + cmdPriority);
                // 从 mute 状态恢复时进入淡入以渐变恢复音量
                this.ChangeState("fadein");
                break;
                
            case "adjust":
                if(params == null) {
                    trace("[MusicEngine] Error: 'adjust' command missing parameters.");
                    return;
                }
                // 仅对播放状态有效
                if(getActiveStateName() == "playing") {
                    var newVolume:Number = (params.volume != undefined) ? params.volume : playingState.targetVolume;
                    var newFadeDuration:Number = (params.fadeDuration != undefined) ? params.fadeDuration : playingState.fadeDuration;
                    var newLoop:Boolean = (params.loop != undefined) ? params.loop : playingState.loop;
                    playingState.adjustParameters(newVolume, newFadeDuration, newLoop);
                } else {
                    trace("[MusicEngine] 'adjust' command ignored: not in playing state.");
                }
                break;
                
            case "jump":
                if(params == null || params.position == undefined) {
                    trace("[MusicEngine] Error: 'jump' command missing 'position' parameter.");
                    return;
                }
                trace("[MusicEngine] Processing 'jump' command to position " + params.position);
                if(musicPlayer != null) {
                    musicPlayer.jumpTo(params.position);
                }
                break;
                
            case "query":
                trace("[MusicEngine] Current State: " + this.getActiveStateName());
                if(getActiveStateName() == "playing") {
                    trace("   Playing clip: " + playingState.clip + ", volume: " + playingState.targetVolume + ", loop: " + playingState.loop + ", priority: " + playingState.priority);
                }
                break;
                
            case "complete":
                // 模拟播放完成事件，在播放状态下根据循环标志处理
                if(getActiveStateName() == "playing") {
                    trace("[MusicEngine] Playback complete received");
                    if(playingState.loop) {
                        // 重播当前曲目
                        trace("[MusicEngine] Loop enabled, restarting playback");
                        this.ChangeState("fadein");
                    } else {
                        this.ChangeState("idle");
                        currentPriority = 0;
                    }
                } else {
                    trace("[MusicEngine] 'complete' command ignored: not in playing state.");
                }
                break;
                
            default:
                trace("[MusicEngine] Unknown command: " + command);
                break;
        }
    }
    
    public function onAction():Void {
        super.onAction();
        // 在 onAction 中可加入全局监控逻辑
    }

    // 播放背景音乐或点歌
    private function playMusic(params:Object):Void {
        trace("[MusicEngine] Playing music with parameters: " + params);
        // 此处执行背景音乐或点歌的播放逻辑
    }

    public function stop():Void {
        trace("[MusicEngine] Stopping music.");
        // 停止播放
    }

    public function setVolume(volume:Number):Void {
        trace("[MusicEngine] Setting volume to: " + volume);
        // 设置音量
    }
}
