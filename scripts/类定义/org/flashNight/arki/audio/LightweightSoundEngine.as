/* 
 * 文件：org/flashNight/arki/audio/LightweightSoundEngine.as
 * 说明：轻量化音效引擎，实现 IMusicEngine，负责音效轨道的基本播放控制（播放、音量、静音等）。
 */
 
import org.flashNight.arki.audio.IMusicEngine;

class org.flashNight.arki.audio.LightweightSoundEngine implements IMusicEngine {
    private var soundManager:Object; // 预处理的音频管理器
    private var currentClip:String;  // 当前播放的音效标识
    private var currentSound:Sound;  // 当前播放的 Sound 对象
    private var volume:Number;      // 音量
    private var loop:Boolean;       // 循环播放标志
    private var isMuted:Boolean;    // 静音标志
    private var lastPlayTime:Number; // 最后一次播放音效的时间
    private var minInterval:Number; // 最小间隔
    
    public function LightweightSoundEngine(soundManager:Object) {
        this.soundManager = soundManager;
        this.currentClip = "";
        this.currentSound = null;
        this.volume = 100;
        this.loop = false;
        this.isMuted = false;
        this.lastPlayTime = 0;
        this.minInterval = 90; // 最小播放间隔
    }
    
    public function play(clip:String):Void {
        // 如果当前播放的音效与传入的相同，则不重复播放
        if (clip == this.currentClip) {
            trace("[LightweightSoundEngine] Already playing this clip: " + clip);
            return;
        }
        
        // 检查播放间隔，避免两次播放声音间隔过短
        var currentTime:Number = getTimer();
        if (currentTime - this.lastPlayTime < this.minInterval) {
            trace("[LightweightSoundEngine] Ignored play due to min interval constraint");
            return;
        }
        this.lastPlayTime = currentTime;
        
        // 获取音效的 MovieClip（武器、特效、人物）
        var category:String = this.soundManager.soundSourceDict[clip];
        if (category == undefined) {
            trace("[LightweightSoundEngine] Error: No category found for clip: " + clip);
            return;
        }
        var target_mc:MovieClip;
        switch(category) {
            case "武器":
                target_mc = this.soundManager.武器;
                break;
            case "特效":
                target_mc = this.soundManager.特效;
                break;
            case "人物":
                target_mc = this.soundManager.人物;
                break;
            default:
                trace("[LightweightSoundEngine] Error: Unknown category: " + category);
                return;
        }
        
        // 如果没有 Sound 对象，则创建并附加
        if (!this.soundManager.soundDict[clip]) {
            this.soundManager.soundDict[clip] = new Sound(target_mc);
            this.soundManager.soundDict[clip].attachSound(clip);
        }
        
        this.currentSound = this.soundManager.soundDict[clip];
        this.currentClip = clip;
        
        // 设置音量
        if (!this.isMuted) {
            this.currentSound.setVolume(this.volume);
        } else {
            this.currentSound.setVolume(0);
        }
        
        // 设置循环
        var loopCount:Number = (this.loop) ? 9999 : 1;
        this.currentSound.start(0, loopCount);
        
        trace("[LightweightSoundEngine] Playing clip: " + clip + " in category: " + category);
    }
    
    public function stop():Void {
        if (this.currentSound != null) {
            this.currentSound.stop();
            this.currentClip = "";
            this.currentSound = null;
            trace("[LightweightSoundEngine] Stopped clip: " + this.currentClip);
        }
    }
    
    public function setVolume(volume:Number):Void {
        this.volume = volume;
        if (this.currentSound != null && !this.isMuted) {
            this.currentSound.setVolume(volume);
        }
        trace("[LightweightSoundEngine] Volume set to: " + volume);
    }
    
    public function jumpTo(position:Number):Void {
        if (this.currentSound != null) {
            this.currentSound.jump(position);
            trace("[LightweightSoundEngine] Jump to position: " + position);
        }
    }
    
    public function setLoop(loop:Boolean):Void {
        this.loop = loop;
        trace("[LightweightSoundEngine] Loop set to: " + loop);
    }
    
    public function mute():Void {
        this.isMuted = true;
        if (this.currentSound != null) {
            this.currentSound.setVolume(0);
        }
        trace("[LightweightSoundEngine] Muted");
    }
    
    public function unmute():Void {
        this.isMuted = false;
        if (this.currentSound != null) {
            this.currentSound.setVolume(this.volume);
        }
        trace("[LightweightSoundEngine] Unmuted");
    }
}
