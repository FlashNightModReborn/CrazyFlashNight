/* 
 * 文件：org/flashNight/arki/audio/MusicPlayer.as
 * 说明：音乐播放器类，实现 IMusicPlayer 接口，
 *       负责读取预处理数据，并与 AS2 的 Sound 对象交互。
 */
 
import org.flashNight.arki.audio.IMusicPlayer;

class org.flashNight.arki.audio.MusicPlayer implements IMusicPlayer {
    // 引用预处理后生成的 soundManager 对象（由 SoundPreprocessor 创建）
    private var soundManager:Object;
    // 当前播放音效的标识（clip ID）
    private var currentClip:String;
    // 当前使用的 Sound 对象
    private var currentSound:Sound;
    // 当前音量设置（0～100）
    private var volume:Number;
    // 循环标志
    private var loop:Boolean;
    // 静音标志
    private var isMuted:Boolean;
    
    /**
     * 构造函数
     * @param soundManager	预处理类创建的 soundManager 对象（例如 _root.soundManager）
     */
    public function MusicPlayer(soundManager:Object) {
        this.soundManager = soundManager;
        this.currentClip = "";
        this.currentSound = null;
        this.volume = 100;
        this.loop = false;
        this.isMuted = false;
    }
    
    // 播放指定音效（clip 为音效标识）
    public function play(clip:String):Void {
        // 根据 soundSourceDict 确定音效所属分类
        var category:String = this.soundManager.soundSourceDict[clip];
        if (category == undefined) {
            trace("[MusicPlayer] Error: No category found for clip: " + clip);
            return;
        }
        // 根据分类选择目标 MovieClip
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
                trace("[MusicPlayer] Error: Unknown category: " + category);
                return;
        }
        // 检查最小播放间隔
        var currentTime:Number = getTimer();
        if (!isNaN(this.soundManager.soundLastTime[clip]) && currentTime - this.soundManager.soundLastTime[clip] < this.soundManager.minInterval) {
            trace("[MusicPlayer] Play ignored due to min interval constraint for clip: " + clip);
            return;
        }
        this.soundManager.soundLastTime[clip] = currentTime;
        
        // 如果还没有对应 Sound 对象，则创建并 attachSound
        if (!this.soundManager.soundDict[clip]) {
            this.soundManager.soundDict[clip] = new Sound(target_mc);
            this.soundManager.soundDict[clip].attachSound(clip);
        }
        this.currentSound = this.soundManager.soundDict[clip];
        this.currentClip = clip;
        // 设置音量（若未静音，则按设置音量播放）
        if (!this.isMuted) {
            this.currentSound.setVolume(this.volume);
        } else {
            this.currentSound.setVolume(0);
        }
        // 播放：若循环则设较大循环次数，否则 1 次播放
        var loopCount:Number = (this.loop) ? 9999 : 1;
        this.currentSound.start(0, loopCount);
        trace("[MusicPlayer] Playing clip: " + clip + " in category: " + category);
    }
    
    // 停止当前播放的音效
    public function stop():Void {
        if (this.currentSound != null) {
            this.currentSound.stop();
            trace("[MusicPlayer] Stopped clip: " + this.currentClip);
            this.currentClip = "";
            this.currentSound = null;
        }
    }
    
    // 模拟淡入效果（实际可扩展为 onEnterFrame 逐帧调整音量）
    public function fadeIn(duration:Number):Void {
        trace("[MusicPlayer] FadeIn over " + duration + " frames");
        // 简单实现：直接设置音量至当前值
        this.setVolume(this.volume);
    }
    
    // 模拟淡出效果：直接设置音量为 0
    public function fadeOut(duration:Number):Void {
        trace("[MusicPlayer] FadeOut over " + duration + " frames");
        this.setVolume(0);
    }
    
    // 设置音量
    public function setVolume(volume:Number):Void {
        this.volume = volume;
        if (this.currentSound != null && !this.isMuted) {
            this.currentSound.setVolume(volume);
        }
        trace("[MusicPlayer] Volume set to: " + volume);
    }
    
    // 跳转到指定播放位置（单位由具体实现定义）
    public function jumpTo(position:Number):Void {
        if (this.currentSound != null) {
            // AS2 Sound 对象的 jump 方法用于跳转播放位置
            this.currentSound.jump(position);
            trace("[MusicPlayer] Jump to position: " + position);
        }
    }
    
    // 设置循环播放（注意：更改循环参数对当前播放可能无效）
    public function setLoop(loop:Boolean):Void {
        this.loop = loop;
        trace("[MusicPlayer] Loop set to: " + loop);
    }
    
    // 静音
    public function mute():Void {
        this.isMuted = true;
        if (this.currentSound != null) {
            this.currentSound.setVolume(0);
        }
        trace("[MusicPlayer] Muted");
    }
    
    // 取消静音
    public function unmute():Void {
        this.isMuted = false;
        if (this.currentSound != null) {
            this.currentSound.setVolume(this.volume);
        }
        trace("[MusicPlayer] Unmuted");
    }
}
