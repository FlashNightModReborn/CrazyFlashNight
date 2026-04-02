/**
 * 文件：org/flashNight/arki/audio/SoundEffectManager.as
 * 说明：音效管理器，通过 AudioBridge 将播放指令发送到 launcher 的 native 音频引擎。
 *
 * 归一化规则：所有 Flash 侧原始音量值（0-100+）在此处 /100 转为 0.0-∞ float，
 * AudioBridge 透传，native 层直接设。SoundEffectManager 是唯一归一化点。
 */

import org.flashNight.arki.audio.AudioBridge;
import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;

class org.flashNight.arki.audio.SoundEffectManager {

    private var globalVolume:Number;
    private var bgmVolume:Number;
    private var currentBGMBaseVolume:Number;
    private var currentFadeDuration:Number;
    private var currentBGMUrl:String;

    public var bgmList:Object;
    private var bgmListPath:String = "sounds/bgm_list.xml";

    public function SoundEffectManager() {
        globalVolume = 50;
        bgmVolume = 80;
        currentBGMBaseVolume = 100;
        currentFadeDuration = 20;
        currentBGMUrl = null;

        loadBGMList();
    }

    public function loadBGMList():Void {
        var loader:BaseXMLLoader = new BaseXMLLoader(bgmListPath);
        var self:SoundEffectManager = this;
        loader.load(
            function(data:Object):Void {
                var BGMDefault = {
                    baseVolume: 100,
                    fadeDuration: 20
                };
                self.bgmList = new Object();
                var musics:Object = data.music;
                var count:Number = 0;
                for (var i in musics) {
                    var bgm = musics[i];
                    if (isNaN(bgm.fadeDuration)) bgm.fadeDuration = BGMDefault.fadeDuration;
                    if (isNaN(bgm.baseVolume)) bgm.baseVolume = BGMDefault.baseVolume;
                    self.bgmList[bgm.title] = bgm;
                    count++;
                }
                _root.server.sendSocketMessage("N[BGM] bgmList loaded: " + count + " entries");
            },
            function():Void {
                trace("[SoundEffectManager] Error loading bgmList XML");
                _root.server.sendSocketMessage("N[BGM] ERROR: failed to load bgm_list.xml");
            }
        );
    }

    /**
     * 播放音效 — SFX 快车道（S 前缀）
     * @param soundId   音效 linkageIdentifier
     * @param source    分类（不再需要，保留参数签名兼容）
     */
    public function playSound(soundId:String, source:String):Void {
        if (globalVolume == 0) return;
        AudioBridge.playSound(soundId);
    }

    /**
     * 播放背景音乐 — JSON 路由
     * @param title     bgm_list.xml 中的曲目标题
     * @param loop      是否循环
     * @param volume    基础音量（可选，默认从 bgm.baseVolume 取）
     */
    public function playBGM(title:String, loop:Boolean, volume:Number):Void {
        var bgm = bgmList[title];
        if (bgm == null) {
            _root.server.sendSocketMessage("N[BGM] title not in bgmList: " + title);
            return;
        }
        var url:String = bgm.url;
        if (url == null) {
            _root.server.sendSocketMessage("N[BGM] url is null for title: " + title);
            return;
        }

        if (url == "stop") {
            _root.server.sendSocketMessage("N[BGM] stop command for: " + title);
            stopBGM();
            return;
        }

        if (globalVolume == 0 || bgmVolume == 0) {
            _root.server.sendSocketMessage("N[BGM] muted globalVol=" + globalVolume + " bgmVol=" + bgmVolume + " title=" + title);
            return;
        }
        if (currentBGMUrl == url) {
            // 同一曲目已在播放，跳过（不打日志避免刷屏）
            return;
        }

        if (loop !== true) loop = false;
        if (isNaN(volume) || volume < 0) volume = bgm.baseVolume;

        var finalVolume:Number = volume * bgmVolume / 100;
        var fadeSec:Number = bgm.fadeDuration / 30;

        _root.server.sendSocketMessage("N[BGM] PLAY title=" + title + " url=" + url + " loop=" + loop + " vol=" + (finalVolume / 100) + " fade=" + fadeSec);

        if (!AudioBridge.playBGM(url, loop, finalVolume / 100, fadeSec)) {
            _root.server.sendSocketMessage("N[BGM] AudioBridge.playBGM returned false (socket down?)");
            return;
        }

        currentBGMBaseVolume = volume;
        currentFadeDuration = bgm.fadeDuration;
        currentBGMUrl = url;

        // 推送曲目标题到 WebView overlay
        org.flashNight.arki.render.FrameBroadcaster.pushUiState("bgm:" + title);
    }

    /** 停止 BGM，淡出时间不低于 1 秒 */
    public function stopBGM():Void {
        var fadeSec:Number = currentFadeDuration / 30;
        if (fadeSec < 1) fadeSec = 1;
        _root.server.sendSocketMessage("N[BGM] STOP fade=" + fadeSec + " was=" + currentBGMUrl);
        if (AudioBridge.stopBGM(fadeSec)) {
            currentBGMUrl = null;
            org.flashNight.arki.render.FrameBroadcaster.pushUiState("bgm:");
        }
    }

    public function stopAll():Void {
        stopBGM();
    }

    /**
     * 调整全局音量
     */
    public function setGlobalVolume(value:Number):Void {
        if (isNaN(value) || value > 100 || value < 0) return;
        globalVolume = value;
        // 归一化点：/100
        AudioBridge.setMasterVolume(value / 100);
    }

    public function getGlobalVolume():Number {
        return globalVolume;
    }

    /**
     * 调整BGM音量
     */
    public function setBGMVolume(value:Number):Void {
        if (isNaN(value) || value > 100 || value < 0) return;
        bgmVolume = value;
        var finalVolume:Number = currentBGMBaseVolume * bgmVolume / 100;
        // 归一化点：/100
        AudioBridge.setBGMVolume(finalVolume / 100);
    }

    public function getBGMVolume():Number {
        return bgmVolume;
    }
}
