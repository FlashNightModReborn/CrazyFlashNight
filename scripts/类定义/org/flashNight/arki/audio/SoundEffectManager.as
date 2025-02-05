/* 
 * 文件：org/flashNight/arki/audio/SoundEffectManager.as
 * 说明：音效管理器，将音效分配到不同的轨道，每个轨道可以使用不同的音效引擎。
 */

import org.flashNight.arki.audio.IMusicEngine;
import org.flashNight.arki.audio.MusicEngine;
import org.flashNight.arki.audio.LightweightSoundEngine;

class org.flashNight.arki.audio.SoundEffectManager {
    private var lightweightEngine:IMusicEngine;
    private var musicEngineBackground:IMusicEngine;
    private var musicEnginePlaylist:IMusicEngine;
    
    public function SoundEffectManager() {
        // 初始化轻量化音效引擎和全功能音乐引擎
        this.lightweightEngine = new LightweightSoundEngine();
        this.musicEngineBackground = new MusicEngine(_root.soundManager);
        this.musicEnginePlaylist = new MusicEngine(_root.soundManager);
    }

    // 播放音效
    public function playSound(soundId:String, volumeMultiplier:Number, soundSource:String):Void {
        // 对于音效轨道，使用轻量化音效引擎
        this.lightweightEngine.handleCommand("play", {soundId: soundId, volumeMultiplier: volumeMultiplier, soundSource: soundSource});
    }

    // 播放背景音乐
    public function playBackgroundMusic(params:Object):Void {
        this.musicEngineBackground.handleCommand("play", params);
    }

    // 播放点歌音乐
    public function playPlaylistMusic(params:Object):Void {
        this.musicEnginePlaylist.handleCommand("play", params);
    }

    // 停止所有音效
    public function stopAll():Void {
        this.lightweightEngine.handleCommand("stop", null);
        this.musicEngineBackground.handleCommand("stop", null);
        this.musicEnginePlaylist.handleCommand("stop", null);
    }

    // 设置音量
    public function setVolume(volume:Number):Void {
        this.lightweightEngine.handleCommand("setVolume", {volume: volume});
        this.musicEngineBackground.handleCommand("setVolume", {volume: volume});
        this.musicEnginePlaylist.handleCommand("setVolume", {volume: volume});
    }
}
