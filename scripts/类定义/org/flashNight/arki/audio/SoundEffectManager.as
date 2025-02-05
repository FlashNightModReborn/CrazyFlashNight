/* 
 * 文件：org/flashNight/arki/audio/SoundEffectManager.as
 * 说明：音效管理器，负责管理多个音效轨道。
 *       音效轨道使用轻量化的音效引擎，背景音乐与点歌音乐使用全功能的 MusicEngine。
 */
 
import org.flashNight.arki.audio.MusicPlayer;
import org.flashNight.arki.audio.LightweightSoundEngine;
import org.flashNight.arki.audio.MusicEngine;
import org.flashNight.arki.audio.SoundPreprocessor;

class org.flashNight.arki.audio.SoundEffectManager {
    private var preprocessor:SoundPreprocessor;
    
    // 轨道播放器：背景音乐、点歌、音效
    public var backgroundPlayer:MusicEngine;
    public var playlistPlayer:MusicEngine;
    public var effectPlayers:Object;
    
    // 构造函数：初始化播放器，并为音效轨道分配轻量化引擎
    public function SoundEffectManager(preprocessor:SoundPreprocessor) {
        this.preprocessor = preprocessor;
        // 创建背景与点歌音乐引擎（使用全功能 MusicEngine）
        this.backgroundPlayer = new MusicEngine(null, null, null);
        this.playlistPlayer = new MusicEngine(null, null, null);
        // 创建音效轨道播放器（使用轻量化音效引擎）
        this.effectPlayers = new Object();
        this.effectPlayers["武器"] = new LightweightSoundEngine(preprocessor.soundManager);
        this.effectPlayers["特效"] = new LightweightSoundEngine(preprocessor.soundManager);
        this.effectPlayers["人物"] = new LightweightSoundEngine(preprocessor.soundManager);
    }
    
    // 播放音效
    public function playSound(soundId:String, volumeMultiplier:Number, source:String):Boolean {
        var category:String = (source != undefined && source != null) ? source : this.preprocessor.soundSourceDict[soundId];
        if (category == undefined) {
            trace("[SoundEffectManager] Error: No category found for soundId: " + soundId);
            return false;
        }
        var player:IMusicEngine = this.effectPlayers[category];
        if (player == undefined) {
            trace("[SoundEffectManager] Error: No MusicPlayer found for category: " + category);
            return false;
        }
        return player.play(soundId);
    }
    
    // 停止音效
    public function stop():Void {
        // 停止背景音乐与点歌音乐
        this.backgroundPlayer.stop();
        this.playlistPlayer.stop();
        
        // 停止所有音效轨道
        for (var key:String in this.effectPlayers) {
            this.effectPlayers[key].stop();
        }
    }
    
    // 调整音量（调整所有轨道）
    public function setVolume(volume:Number):Void {
        this.backgroundPlayer.setVolume(volume);
        this.playlistPlayer.setVolume(volume);
        for (var key:String in this.effectPlayers) {
            this.effectPlayers[key].setVolume(volume);
        }
    }
}
