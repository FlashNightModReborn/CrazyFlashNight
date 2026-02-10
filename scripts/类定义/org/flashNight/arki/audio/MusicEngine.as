/* 
 * 文件：org/flashNight/arki/audio/MusicEngine.as
 * 说明：原有的音乐系统 FSM 实现，扩展以实现 IMusicEngine 接口。
 */

import org.flashNight.neur.StateMachine.*;
import org.flashNight.arki.audio.IMusicEngine;
import org.flashNight.arki.audio.IMusicPlayer;
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
    private var currentClip:String = null;
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
        this.transitions.push("fadein", "playing", function():Boolean {
            var state = this.getActiveState();
            if (state.isComplete != undefined && state.isComplete()) {
                return true;
            }
            return false;
        });
        
        // 转换：淡出完成后尝试切换到下一首背景音乐
        var self:MusicEngine = this;
        this.transitions.push("fadeout", "fadein", function():Boolean {
            var state = this.getActiveState();
            if (self.currentClip != null && self.currentClip !== "" && state.isComplete()) {
                return true;
            }
            return false;
        });
        // 转换：淡出完成后切换到空闲状态
        this.transitions.push("fadeout", "idle", function():Boolean {
            var state = this.getActiveState();
            if (state.isComplete != undefined && state.isComplete()) {
                return true;
            }
            return false;
        });
        // 启动状态机：idle 为默认首状态，start 触发 idle.onEnter
        this.start();
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
     * 对外接口：处理命令
     *   - "play", "switch", "stop", "mute", "unmute", "adjust", "jump", "query", "complete" 等
     */
    public function handleCommand(command:String, params:Object):Boolean {
        var cmdPriority:Number = (params != null && params.priority != undefined) ? params.priority : 0;
        
        // 对于需要优先级的命令
        if (command == "play" || command == "switch" || command == "mute" || command == "unmute" || command == "adjust") {
            if (cmdPriority < currentPriority) {
                trace("[MusicEngine] Command '" + command + "' ignored due to low priority (" + cmdPriority + " < " + currentPriority + ")");
                return false;
            }
            currentPriority = cmdPriority;
        }
        
        switch (command) {
            case "play":
                //只有idle状态下可以使用play指令
                if(getActiveStateName() !== "idle"){
                    trace("[MusicEngine] Error: 'play' command not in idle state.");
                    return false;
                }
                if (params == null || params.clip == undefined) {
                    trace("[MusicEngine] Error: 'play' command missing 'clip' parameter.");
                    return false;
                }
                currentClip = params.clip;
                currentLoop = (params.loop != undefined) ? params.loop : false;
                fadeInState.fadeDuration = (params.fadeDuration != undefined) ? params.fadeDuration : fadeInState.fadeDuration;
                playingState.targetVolume = (params.volume != undefined) ? params.volume : playingState.targetVolume;
                playingState.clip = currentClip;
                playingState.priority = cmdPriority;
                playingState.loop = currentLoop;
                
                trace("[MusicEngine] Processing 'play' command: clip=" + currentClip + ", priority=" + cmdPriority);
                this.ChangeState("fadein");
                return true;
            
            case "switch":
                //只有playing状态下可以使用switch指令
                if(getActiveStateName() !== "playing"){
                    trace("[MusicEngine] Error: 'switch' command not in playing state.");
                    return false;
                }
                if (params == null || params.clip == undefined) {
                    trace("[MusicEngine] Error: 'switch' command missing 'clip' parameter.");
                    return false;
                }
                currentClip = params.clip;
                currentLoop = (params.loop != undefined) ? params.loop : currentLoop;
                fadeInState.fadeDuration = (params.fadeDuration != undefined) ? params.fadeDuration : fadeInState.fadeDuration;
                playingState.targetVolume = (params.volume != undefined) ? params.volume : playingState.targetVolume;
                playingState.clip = currentClip;
                playingState.priority = cmdPriority;
                playingState.loop = currentLoop;
                
                trace("[MusicEngine] Processing 'switch' command: switching to clip=" + currentClip + ", priority=" + cmdPriority);
                // 先淡出，再由外部/后续命令重新 play (x) 目前状态机逻辑改为淡出后自动回到淡入
                this.ChangeState("fadeout");
                return true;
            
            case "stop":
                var stateName = getActiveStateName();
                if(stateName !== "playing" && stateName !== "fadein"){
                    trace("[MusicEngine] Error: 'switch' command not in playing or fadein state.");
                    return false;
                }
                trace("[MusicEngine] Processing 'stop' command");
                currentClip = null;
                currentPriority = 0; // 重置
                this.ChangeState("fadeout");
                return true;
            
            case "mute":
                trace("[MusicEngine] Processing 'mute' command with priority " + cmdPriority);
                fadeInState.fadeDuration = (params.fadeDuration != undefined) ? params.fadeDuration : fadeInState.fadeDuration;
                this.ChangeState("mute");
                return true;
            
            case "unmute":
                trace("[MusicEngine] Processing 'unmute' command with priority " + cmdPriority);
                this.ChangeState("fadein");
                return true;
            
            case "adjust":
                if (params == null) {
                    trace("[MusicEngine] Error: 'adjust' command missing parameters.");
                    return false;
                }
                if (getActiveStateName() == "playing") {
                    var newVolume:Number = (params.volume != undefined) ? params.volume : playingState.targetVolume;
                    var newFadeDuration:Number = (params.fadeDuration != undefined) ? params.fadeDuration : playingState.fadeDuration;
                    var newLoop:Boolean = (params.loop != undefined) ? params.loop : playingState.loop;
                    playingState.adjustParameters(newVolume, newFadeDuration, newLoop);
                } else {
                    trace("[MusicEngine] 'adjust' command ignored: not in playing state.");
                    return false;
                }
                return true;
            
            case "jump":
                if (params == null || params.position == undefined) {
                    trace("[MusicEngine] Error: 'jump' command missing 'position'.");
                    return false;
                }
                trace("[MusicEngine] Processing 'jump' to position " + params.position);
                if (musicPlayer != null) {
                    musicPlayer.jumpTo(params.position);
                }
                return true;
            
            case "query":
                trace("[MusicEngine] Current State: " + getActiveStateName());
                if (getActiveStateName() == "playing") {
                    trace("   Playing clip: " + playingState.clip + 
                          ", volume: " + playingState.targetVolume + 
                          ", loop: " + playingState.loop + 
                          ", priority: " + playingState.priority);
                }
                return true;
            
            case "complete":
                if (getActiveStateName() == "playing") {
                    trace("[MusicEngine] Playback complete received");
                    if (playingState.loop) {
                        trace("[MusicEngine] Loop enabled, restarting");
                        this.ChangeState("fadein");
                    } else {
                        this.ChangeState("idle");
                        currentPriority = 0;
                    }
                } else {
                    trace("[MusicEngine] 'complete' ignored: not in playing state.");
                    return false;
                }
                return true;
            
            default:
                trace("[MusicEngine] Unknown command: " + command);
                return false;
        }
    }
    
    // IMusicEngine: stop()
    public function stop():Void {
        // 等同于发出 "stop" 命令
        this.handleCommand("stop", null);
    }
    
    // IMusicEngine: setVolume(...)
    public function setVolume(volume:Number):Void {
        // 如果正处于 playing 状态，可直接调用 playingState.adjustParameters
        if (getActiveStateName() == "playing") {
            playingState.adjustParameters(volume, playingState.fadeDuration, playingState.loop);
        }
        trace("[MusicEngine] setVolume called: " + volume);
    }

    public function getCurrentClip():String{
        if(getActiveStateName() != "idle") return currentClip;
        return null;
    }
}
