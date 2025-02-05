/* 
 * 文件：org/flashNight/arki/audio/SoundEffectManager.as
 * 说明：音效管理器，封装多个 MusicPlayer 轨道，包括背景音乐、点歌、以及音效轨道，
 *       并提供 playSound 接口实现原有的音效播放功能。
 */
 
import org.flashNight.arki.audio.MusicPlayer;
import org.flashNight.arki.audio.SoundPreprocessor;

class org.flashNight.arki.audio.SoundEffectManager {
    // 预处理类实例（含 soundManager 与各数据结构）
    private var preprocessor:SoundPreprocessor;
    
    // 各个轨道的播放器
    public var backgroundPlayer:MusicPlayer;
    public var playlistPlayer:MusicPlayer;
    // 用于音效轨道：按分类存放播放器（"武器", "特效", "人物"）
    public var effectPlayers:Object;
    
    /**
     * 构造函数
     * @param preprocessor	预处理类实例，必须先完成初始化（并加载 XML 数据）
     */
    public function SoundEffectManager(preprocessor:SoundPreprocessor) {
        this.preprocessor = preprocessor;
        // 利用预处理后的 soundManager 创建播放器
        this.backgroundPlayer = new MusicPlayer(preprocessor.soundManager);
        this.playlistPlayer = new MusicPlayer(preprocessor.soundManager);
        this.effectPlayers = new Object();
        this.effectPlayers["武器"] = new MusicPlayer(preprocessor.soundManager);
        this.effectPlayers["特效"] = new MusicPlayer(preprocessor.soundManager);
        this.effectPlayers["人物"] = new MusicPlayer(preprocessor.soundManager);
    }
    
    /**
     * 播放音效接口，参数意义与原始代码相同：
     * @param soundId			音效标识（linkageIdentifier）
     * @param volumeMultiplier	音量乘数（建议 0～1）
     * @param source			可选：明确指定音效所属分类（如 "武器"），否则根据预处理数据查找
     * @return Boolean			播放成功返回 true，否则 false
     */
    public function playSound(soundId:String, volumeMultiplier:Number, source:String):Boolean {
        // 若 source 参数提供，则使用，否则查预处理数据
        var category:String = (source != undefined && source != null) ? source : this.preprocessor.soundSourceDict[soundId];
        if (category == undefined) {
            trace("[SoundEffectManager] Error: No category found for soundId: " + soundId);
            return false;
        }
        // 取得对应分类的播放器
        var player:MusicPlayer = this.effectPlayers[category];
        if (player == undefined) {
            trace("[SoundEffectManager] Error: No MusicPlayer found for category: " + category);
            return false;
        }
        // 检查播放间隔
        var currentTime:Number = getTimer();
        if (!isNaN(this.preprocessor.soundLastTime[soundId]) &&
            currentTime - this.preprocessor.soundLastTime[soundId] < this.preprocessor.minInterval) {
            trace("[SoundEffectManager] Play sound ignored due to min interval for soundId: " + soundId);
            return false;
        }
        this.preprocessor.soundLastTime[soundId] = currentTime;
        
        // 根据全局音效音量, 计算最终音量
        var baseVolume:Number = (_root.音效音量 != undefined) ? _root.音效音量 : 100;
        var vol:Number = Math.floor(volumeMultiplier * baseVolume);
        vol = Math.max(vol, 1);
        player.setVolume(vol);
        // 播放该音效
        player.play(soundId);
        trace("[SoundEffectManager] Played soundId: " + soundId + " on category: " + category + " with volume: " + vol);
        return true;
    }
    
    // 此外，可根据需要添加调整各轨道参数、停止某轨道音效等接口
}
