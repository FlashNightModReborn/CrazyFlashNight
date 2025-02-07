/* 
 * 文件：org/flashNight/arki/audio/SoundEffectManager.as
 * 说明：音效管理器，内部区分 3 个轨道：
 *   1) bgmEngine: 全功能 MusicEngine（背景音乐）
 *   2) karaokeEngine: 全功能 MusicEngine（点歌）
 *   3) sfxEngine: 轻量 LightweightSoundEngine（普通音效）
 * 
 * 对外提供常用的 playSound，用于播放一般音效。
 * 对于背景音乐/点歌，则可直接调用 bgmEngine.handleCommand(...) 或 karaokeEngine.handleCommand(...)
 */
 
import org.flashNight.arki.audio.*;

class org.flashNight.arki.audio.SoundEffectManager {
    
    private var preprocessor:SoundPreprocessor;
    public var bgmEngine:IMusicEngine;       // 全功能音乐引擎（背景）
    public var karaokeEngine:IMusicEngine;   // 全功能音乐引擎（点歌）
    public var sfxEngine:IMusicEngine;       // 轻量音效引擎
    
    public function SoundEffectManager(preproc:SoundPreprocessor) {
        this.preprocessor = preproc;
        
        // 初始化三轨道
        bgmEngine = new MusicEngine(null, null, null); 
        karaokeEngine = new MusicEngine(null, null, null);

        bgmEngine.setMusicPlayer(new SimMusicPlayer());
        karaokeEngine.setMusicPlayer(new SimMusicPlayer());
        
        sfxEngine = new LightweightSoundEngine(this.preprocessor);
        
        // 如有需要，可设置 MusicPlayer 给两个全功能引擎
        //   bgmEngine.setMusicPlayer( ... );
        //   karaokeEngine.setMusicPlayer( ... );
    }
    
    /**
     * 播放音效接口，对应原 _root.播放音效(...) 功能
     * @param soundId          音效标识
     * @param volumeMultiplier 音量乘数（0~1之间）
     * @param source           分类（可选），否则从 soundSourceDict 查找
     */
    public function playSound(soundId:String, volumeMultiplier:Number, source:String):Void {
        // 直接调用 sfxEngine.handleCommand("play", {...}) 
        sfxEngine.handleCommand("play", {
            soundId: soundId,
            volumeMultiplier: volumeMultiplier,
            source: source
        });
    }
    
    /**
     * 若需要模拟之前的 stopAllSound()，可遍历三轨道 stop()
     */
    public function stopAll():Void {
        bgmEngine.stop();
        karaokeEngine.stop();
        sfxEngine.stop();
    }
    
    /**
     * 其它针对背景音乐/点歌的操作，可直接调用 bgmEngine / karaokeEngine
     * 如：bgmEngine.handleCommand("play", {clip:"bgm_main", priority:5});
     */
}
