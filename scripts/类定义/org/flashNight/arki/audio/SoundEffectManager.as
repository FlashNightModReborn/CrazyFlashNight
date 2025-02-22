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
import org.flashNight.neur.Event.EventBus;
import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;

class org.flashNight.arki.audio.SoundEffectManager {

    private var preprocessor:SoundPreprocessor;
    public var bgmEngine:MusicEngine;       // 全功能音乐引擎（背景）
    public var karaokeEngine:MusicEngine;   // 全功能音乐引擎（点歌）
    public var sfxEngine:IMusicEngine;       // 轻量音效引擎

    private var globalSoundObj:Sound; // 全局音量控制器
    private var globalVolume:Number; // 全局音量
    private var bgmVolume:Number; // BGM音量
    private var currentBGMBaseVolume:Number; // 记录当前音乐的基础音量

    public var bgmList:Object;
    private var bgmListPath:String = "sounds/bgm_list.xml";
    
    public function SoundEffectManager(preproc:SoundPreprocessor) {
        this.preprocessor = preproc;
        globalSoundObj = new Sound();
        globalVolume = 100;
        bgmVolume = 70; // 默认bgm音量为70
        
        // 初始化三轨道
        bgmEngine = new MusicEngine(null, null, null); 
        karaokeEngine = new MusicEngine(null, null, null);

        bgmEngine.setMusicPlayer(new MusicPlayer());
        karaokeEngine.setMusicPlayer(new SimMusicPlayer());
        
        sfxEngine = new LightweightSoundEngine(this.preprocessor);

        //
        EventBus.getInstance().subscribe("frameUpdate", function() {
            this.bgmEngine.onAction();
        }, this);
        
        // 如有需要，可设置 MusicPlayer 给两个全功能引擎
        //   bgmEngine.setMusicPlayer( ... );
        //   karaokeEngine.setMusicPlayer( ... );

        // 导入bgm列表
        loadBGMList();
    }

    public function loadBGMList(){
        var loader:BaseXMLLoader = new BaseXMLLoader(bgmListPath);
        // 为回调捕获 this
        var self:SoundEffectManager = this;
        loader.load(
            function(data:Object):Void {
                var BGMDefault = {
                    baseVolume: 100,
                    fadeDuration: 20
                };
                self.bgmList = new Object();
                var musics:Object = data.music;
                for (var i in musics) {
                    var bgm = musics[i];
                    if(isNaN(bgm.fadeDuration)) bgm.fadeDuration = BGMDefault.fadeDuration;
                    if(isNaN(bgm.baseVolume)) bgm.baseVolume = BGMDefault.baseVolume;
                    self.bgmList[bgm.title] = bgm;
                }
            },
            function():Void {
                trace("[SoundEffectManager] Error loading bgmList XML");
            }
        );
    }
    
    /**
     * 播放音效接口，对应原 _root.播放音效(...) 功能
     * @param soundId          音效标识
     * @param source           分类（可选），否则从 soundSourceDict 查找
     */
    public function playSound(soundId:String, source:String):Void {
        if(globalVolume == 0) return; //音量为0时不调用声音
        // 直接调用 sfxEngine.handleCommand("play", {...}) 
        sfxEngine.handleCommand("play", {
            soundId: soundId,
            source: source
        });
    }

    /**
     * 播放背景音乐接口
     * @param title          背景音乐名称
     * @param loop           是否循环
     * @param volume         音量
     */
    public function playBGM(title:String, loop:Boolean, volume:Number):Void {
        var bgm = bgmList[title];
        var url = bgm.url;
        if(url == null) return;
        //若为预留关键字stop则停止当前音乐
        if(url == "stop") {
            stopBGM();
            return;
        }
        if(globalVolume == 0 || bgmVolume == 0) return; //全局音量和音乐音量任一为0时不加载音乐

        var stateName = bgmEngine.getActiveStateName();
        var command = null;
        if(stateName == "idle"){
            command = "play";
        }else if(bgmEngine.getCurrentClip() == url){
            return; //若调用的声音和当前播放的声音路径相同则阻止指令
        }else if(stateName == "playing"){
            command = "switch";
        }
        if(command != null){
            if(loop !== true) loop = false;
            if(isNaN(volume) || volume < 0 || volume > 100) volume = bgm.baseVolume;
            var finalVolume = volume * bgmVolume / 100; // 应用设置的音乐音量
            var result = bgmEngine.handleCommand(command, {clip:url, priority:0, loop:loop, volume:finalVolume, fadeDuration:bgm.fadeDuration});
            if(result) currentBGMBaseVolume = volume; // 成功播放音乐后记录基础音量
        }
    }
    public function stopBGM():Void {
        bgmEngine.handleCommand("stop", null);
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
    
    /**
     * 调整全局音量
     */
    public function setGlobalVolume(value:Number):Void{
        if(isNaN(value) || value > 100 || value < 0) return;
        globalVolume = value;
        globalSoundObj.setVolume(globalVolume);
    }
    public function getGlobalVolume():Number{
        return globalVolume;
    }
    /**
     * 调整BGM音量
     */
    public function setBGMVolume(value:Number):Void{
        if(isNaN(value) || value > 100 || value < 0) return;
        bgmVolume = value;
        var finalVolume = currentBGMBaseVolume * bgmVolume / 100; // 应用设置的音乐音量
        bgmEngine.handleCommand("adjust",{volume: finalVolume});
    }
    public function getBGMVolume():Number{
        return bgmVolume;
    }
}
