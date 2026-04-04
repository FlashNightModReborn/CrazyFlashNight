/**
 * 文件：org/flashNight/arki/audio/SoundEffectManager.as
 * 说明：音效管理器，通过 AudioBridge 将播放指令发送到 launcher 的 native 音频引擎。
 *
 * 归一化规则：所有 Flash 侧原始音量值（0-100+）在此处 /100 转为 0.0-∞ float，
 * AudioBridge 透传，native 层直接设。SoundEffectManager 是唯一归一化点。
 *
 * BGM 优先级状态机（3 级）：
 *   默认:     stage > jukebox > scene
 *   override: jukebox > stage > scene
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

    // ── 优先级状态 ──
    private var _bgmSource:String;          // "scene" | "stage" | "jukebox" | null
    private var _currentAlbum:String;       // 当前播放曲目所属专辑
    private var _currentLoop:Boolean;       // 当前播放的 loop 状态（用于快照 suppressed）
    private var _sceneIsAlbumMode:Boolean;  // 当前场景 BGM 是否通过 album 模式进入（区分单曲 vs 专辑）
    private var _jukeboxOverride:Boolean;   // 是否覆盖关卡BGM
    private var _jukeboxActive:Boolean;     // 点歌器是否有选中的曲目
    private var _jukeboxTitle:String;       // 点歌器选中的曲目 title
    private var _jukeboxLoop:Boolean;       // 点歌器是否循环
    private var _trueRandom:Boolean;        // true=真随机, false=伪随机(默认,不重复)
    private var _lastRandomTitle:String;    // 上一次随机选取的曲目
    private var _playMode:String;           // "singleLoop" | "albumLoop" | "playOnce"
    private var _jukeboxAlbum:String;       // 点歌器当前曲目所属专辑（用于 albumLoop）

    // ── 专辑索引 ──
    private var _albumIndex:Object;         // album → [{title, weight}, ...]

    // ── 被压制意图 ──
    private var _suppressedScene:Object;    // {type:"single"|"album", title, album, loop, defaultTitle}
    private var _suppressedStage:Object;    // {title, loop}

    public function SoundEffectManager() {
        globalVolume = 50;
        bgmVolume = 80;
        currentBGMBaseVolume = 100;
        currentFadeDuration = 20;
        currentBGMUrl = null;
        bgmList = new Object();

        _bgmSource = null;
        _currentAlbum = null;
        _jukeboxOverride = false;
        _jukeboxActive = false;
        _jukeboxTitle = null;
        _jukeboxLoop = true;
        _trueRandom = false;
        _lastRandomTitle = null;
        _playMode = "singleLoop";
        _jukeboxAlbum = null;
        _albumIndex = {};
        _suppressedScene = null;
        _suppressedStage = null;

        loadBGMList();
        // 默认音量由 Launcher 侧 Program.cs 在 AudioEngine.Init 后直接设（不依赖 socket）
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
                // 不清空 bgmList — catalog 可能已先到达并 merge 了 auto-discovered 曲目
                // XML 是权威源，逐条覆盖（IsRegistered 标记为 true）
                if (self.bgmList == undefined) self.bgmList = new Object();
                var musics:Object = data.music;
                for (var i in musics) {
                    var bgm = musics[i];
                    if (isNaN(bgm.fadeDuration)) bgm.fadeDuration = BGMDefault.fadeDuration;
                    if (isNaN(bgm.baseVolume)) bgm.baseVolume = BGMDefault.baseVolume;
                    if (isNaN(bgm.weight)) bgm.weight = 100;
                    // album 推导：显式声明 > 从 url 路径提取
                    if (bgm.album == undefined || bgm.album == "") {
                        bgm.album = self.deriveAlbumFromUrl(bgm.url);
                    }
                    self.bgmList[bgm.title] = bgm;
                }
                self.rebuildAlbumIndex();
            },
            function():Void {
                trace("[SoundEffectManager] Error loading bgmList XML");
            }
        );
    }

    // ── album 索引 ──

    private function deriveAlbumFromUrl(url:String):String {
        if (url == undefined || url == null) return "unknown";
        // "sounds/TFR/file.mp3" → "TFR"
        var parts:Array = url.split("/");
        if (parts.length >= 3) return parts[1];
        if (parts.length >= 2) return parts[0];
        return "unknown";
    }

    private function rebuildAlbumIndex():Void {
        _albumIndex = {};
        for (var title:String in bgmList) {
            var bgm:Object = bgmList[title];
            if (bgm.album == undefined || bgm.album == "") continue;
            if (_albumIndex[bgm.album] == undefined) {
                _albumIndex[bgm.album] = [];
            }
            _albumIndex[bgm.album].push({title: title, weight: bgm.weight || 100});
        }
    }

    // ── Catalog 合并（Launcher 推送）──

    public function mergeCatalog(catalog:Object):Void {
        var tracks:Array = catalog.tracks;
        if (tracks == undefined) return;
        var addedCount:Number = 0;
        for (var i:Number = 0; i < tracks.length; i++) {
            var t:Object = tracks[i];
            if (t.title == undefined) continue;
            // 不覆盖已注册的（bgm_list.xml 优先）
            if (bgmList[t.title] != undefined) {
                // 仅补充 album（如果现有的没有）
                if ((bgmList[t.title].album == undefined || bgmList[t.title].album == "") && t.album != undefined) {
                    bgmList[t.title].album = t.album;
                }
                continue;
            }
            bgmList[t.title] = {
                title: t.title,
                url: t.url,
                album: t.album || "unknown",
                fadeDuration: t.fade || 20,
                baseVolume: t.vol || 100,
                weight: t.weight || 100
            };
            addedCount++;
        }
        rebuildAlbumIndex();
        trace("[SoundEffectManager] mergeCatalog: +" + addedCount + " tracks merged, total=" + countObj(bgmList));
    }

    public function updateCatalog(update:Object):Void {
        var added:Array = update.added;
        var removed:Array = update.removed;
        var addedCount:Number = 0;
        var removedCount:Number = 0;

        if (removed != undefined) {
            for (var r:Number = 0; r < removed.length; r++) {
                var rTitle:String = removed[r];
                if (bgmList[rTitle] != undefined) {
                    delete bgmList[rTitle];
                    removedCount++;
                }
            }
        }
        if (added != undefined) {
            for (var a:Number = 0; a < added.length; a++) {
                var t:Object = added[a];
                if (t.title == undefined) continue;
                if (bgmList[t.title] != undefined) continue;
                bgmList[t.title] = {
                    title: t.title,
                    url: t.url,
                    album: t.album || "unknown",
                    fadeDuration: t.fade || 20,
                    baseVolume: t.vol || 100,
                    weight: t.weight || 100
                };
                addedCount++;
            }
        }
        if (addedCount > 0 || removedCount > 0) {
            rebuildAlbumIndex();
            trace("[SoundEffectManager] updateCatalog: +" + addedCount + " -" + removedCount);
        }
    }

    private function countObj(obj:Object):Number {
        var n:Number = 0;
        for (var k:String in obj) n++;
        return n;
    }

    // ══════════════════════════════════════════════════════════
    // ██  核心播放方法：优先级状态机
    // ══════════════════════════════════════════════════════════

    /**
     * 带优先级的 BGM 播放入口。所有外部调用应通过此方法。
     * @param title   bgmList 中的曲目标题
     * @param source  "scene" | "stage" | "jukebox"
     * @param loop    是否循环
     * @param volume  基础音量（可选，null 用 bgm 默认值）
     */
    public function playBGMWithSource(title:String, source:String, loop:Boolean, volume:Number):Void {
        var bgm:Object = bgmList[title];
        if (bgm == null) {
            trace("[BGM] source=" + source + " title=" + title + " result=not_found");
            return;
        }

        // ── 优先级检查 ──
        if (source == "stage") {
            if (_jukeboxOverride && _jukeboxActive) {
                // jukebox 覆盖模式下拒绝 stage
                _suppressedStage = {title: title, loop: loop};
                trace("[BGM] source=stage title=" + title + " result=reject_by_jukebox_override");
                // jukebox 可能被 transition stopBGM 中断, 需要恢复播放
                if (currentBGMUrl == null) {
                    playBGMWithSource(_jukeboxTitle, "jukebox", _jukeboxLoop, null);
                }
                return;
            }
            // stage 可以打断 jukebox（非 override 模式）和 scene
            // 快照 jukebox 意图（如果 jukebox 正在播放）
            // jukeboxPlay 时已经快照了 scene，这里无需重复
        } else if (source == "scene") {
            // scene 请求到达意味着已离开战斗，无条件清除过期的 stage 快照
            _suppressedStage = null;
            if (_jukeboxActive) {
                // 更新 suppressed scene（记录最新的场景意图）
                _suppressedScene = {type: "single", title: title, loop: loop};
                trace("[BGM] source=scene title=" + title + " result=reject_by_jukebox");
                // ★ 自动恢复：刚被 stop 后 jukebox 需要重新开始播放
                if (currentBGMUrl == null) {
                    playBGMWithSource(_jukeboxTitle, "jukebox", _jukeboxLoop, null);
                }
                return;
            }
            if (_bgmSource == "stage") {
                trace("[BGM] source=scene title=" + title + " result=reject_in_battle");
                return;
            }
        } else if (source == "jukebox") {
            if (_bgmSource == "stage" && !_jukeboxOverride) {
                trace("[BGM] source=jukebox title=" + title + " result=reject_in_battle");
                return;
            }
        }

        // ── 执行播放 ──
        var result:Boolean = doPlayBGM(title, loop, volume);
        if (result) {
            _bgmSource = source;
            _currentAlbum = bgm.album;
            _currentLoop = loop;
            // 单曲调用不改变 _sceneIsAlbumMode（由 playAlbumBGM 设置）
            if (source == "scene") _sceneIsAlbumMode = false;
            trace("[BGM] source=" + source + " title=" + title + " result=play");
            org.flashNight.arki.render.FrameBroadcaster.pushUiState("jbs:" + source);
        } else if (bgm.url == currentBGMUrl && source != _bgmSource) {
            // 同一首曲目继续播放, 但 source 上下文变更(如跨关卡同 BGM)
            _bgmSource = source;
            _currentAlbum = bgm.album;
            _currentLoop = loop;
            if (source == "scene") _sceneIsAlbumMode = false;
            trace("[BGM] source=" + source + " title=" + title + " result=source_updated");
        }
    }

    /**
     * 专辑模式播放：从 album 中加权随机选取一首。
     * @param album        专辑名
     * @param source       "scene" | "stage" | "jukebox"
     * @param loop         是否循环
     * @param defaultTitle 当专辑为空时的回退曲目（可选）
     */
    public function playAlbumBGM(album:String, source:String, loop:Boolean, defaultTitle:String):Void {
        // 同区域检查：不换歌
        if (_currentAlbum == album && currentBGMUrl != null && _bgmSource == source) {
            return;
        }

        // 在调用 playBGMWithSource 之前，先检查是否会被 jukebox 拒绝
        // 如果会被拒绝，直接在这里记录 album 级别的 suppressed 意图
        if (source == "scene" && _jukeboxActive) {
            _suppressedStage = null; // scene 到达 = 已离开战斗
            _suppressedScene = {type: "album", album: album, loop: loop, defaultTitle: defaultTitle};
            trace("[BGM] source=scene album=" + album + " result=reject_by_jukebox (album preserved)");
            // 自动恢复 jukebox（如果刚被 stop）
            if (currentBGMUrl == null) {
                playBGMWithSource(_jukeboxTitle, "jukebox", _jukeboxLoop, null);
            }
            return;
        }

        var tracks:Array = _albumIndex[album];
        if (tracks == undefined || tracks.length == 0) {
            // 专辑无曲目，回退到默认单曲
            if (defaultTitle != undefined && defaultTitle != null && defaultTitle != "") {
                playBGMWithSource(defaultTitle, source, loop, null);
            }
            return;
        }

        var selectedTitle:String = weightedRandom(tracks);
        playBGMWithSource(selectedTitle, source, loop, null);
        // playBGMWithSource 会设 _sceneIsAlbumMode=false，这里覆盖回 true
        if (source == "scene") _sceneIsAlbumMode = true;
    }

    /**
     * 加权随机选取。默认伪随机（保证前后两首不重复）。
     */
    private function weightedRandom(tracks:Array):String {
        if (tracks.length == 0) return null;
        if (tracks.length == 1) return tracks[0].title;

        var maxRetries:Number = _trueRandom ? 1 : 3;
        var result:String = null;

        for (var attempt:Number = 0; attempt < maxRetries; attempt++) {
            var totalWeight:Number = 0;
            for (var i:Number = 0; i < tracks.length; i++) {
                totalWeight += tracks[i].weight;
            }
            var rand:Number = Math.random() * totalWeight;
            var cumulative:Number = 0;
            for (var j:Number = 0; j < tracks.length; j++) {
                cumulative += tracks[j].weight;
                if (rand < cumulative) {
                    result = tracks[j].title;
                    break;
                }
            }
            // 伪随机：检查不重复
            if (_trueRandom || result != _lastRandomTitle) break;
        }

        _lastRandomTitle = result;
        return result;
    }

    // ══════════════════════════════════════════════════════════
    // ██  点歌器入口
    // ══════════════════════════════════════════════════════════

    public function jukeboxPlay(title:String):Void {
        // 快照当前被压制的意图（使用 _currentLoop 保留原始 loop 语义）
        if (_bgmSource == "scene") {
            if (_sceneIsAlbumMode) {
                _suppressedScene = {type: "album", album: _currentAlbum, loop: _currentLoop, defaultTitle: null};
            } else {
                var currentTitle:String = findTitleByUrl(currentBGMUrl);
                _suppressedScene = {type: "single", title: currentTitle, loop: _currentLoop};
            }
        } else if (_bgmSource == "stage") {
            var stageTitle:String = findTitleByUrl(currentBGMUrl);
            _suppressedStage = {title: stageTitle, loop: _currentLoop};
        }

        _jukeboxActive = true;
        _jukeboxTitle = title;
        // 播放模式决定 loop：singleLoop 循环，其余不循环（由 trackEnd 处理续播/恢复）
        _jukeboxLoop = (_playMode == "singleLoop");
        // 记录曲目所属专辑（albumLoop 模式需要）
        var bgmInfo:Object = bgmList[title];
        _jukeboxAlbum = (bgmInfo != null) ? bgmInfo.album : null;
        playBGMWithSource(title, "jukebox", _jukeboxLoop, null);
    }

    public function jukeboxStop():Void {
        _jukeboxActive = false;
        _jukeboxTitle = null;
        restoreSuppressed();
    }

    public function jukeboxTrackEnd():Void {
        if (!_jukeboxActive) return;
        if (_jukeboxLoop) return; // 单曲循环不会自然结束

        if (_playMode == "albumLoop" && _jukeboxAlbum != null) {
            // 专辑循环：从同专辑随机选下一首
            var tracks:Array = _albumIndex[_jukeboxAlbum];
            if (tracks != undefined && tracks.length > 0) {
                var nextTitle:String = weightedRandom(tracks);
                _jukeboxTitle = nextTitle;
                // 清空 currentBGMUrl 以允许播放（doPlayBGM 有去重检查）
                currentBGMUrl = null;
                playBGMWithSource(nextTitle, "jukebox", false, null);
                trace("[BGM] albumLoop: next=" + nextTitle);
                return;
            }
        }

        // playOnce 或 albumLoop 无曲目：恢复默认
        _jukeboxActive = false;
        _jukeboxTitle = null;
        _jukeboxAlbum = null;
        restoreSuppressed();
    }

    /**
     * 兜底恢复：场景切换后调用，确保 jukebox 不因"目标场景无 BGM 配置"而丢失。
     */
    public function resumeJukeboxIfNeeded():Void {
        // 此方法在场景加载末尾调用，意味着已离开战斗
        _suppressedStage = null;
        if (_jukeboxActive && currentBGMUrl == null) {
            playBGMWithSource(_jukeboxTitle, "jukebox", _jukeboxLoop, null);
        }
    }

    /**
     * 进入无 BGM 配置的 UI 帧(如选关界面)时调用。
     * jukebox 活跃时保持/恢复播放, 否则停止残留 BGM。
     */
    public function enterNoBgmFrame():Void {
        _suppressedStage = null;
        if (_jukeboxActive) {
            if (currentBGMUrl == null) {
                playBGMWithSource(_jukeboxTitle, "jukebox", _jukeboxLoop, null);
            }
            return;
        }
        doStopBGM();
    }

    public function setJukeboxOverride(value:Boolean):Void {
        var wasOverride:Boolean = _jukeboxOverride;
        _jukeboxOverride = (value == true);
        // 从 false → true 且 jukebox 激活且当前在 stage：立即切换
        if (!wasOverride && _jukeboxOverride && _jukeboxActive && _bgmSource == "stage") {
            var stageTitle:String = findTitleByUrl(currentBGMUrl);
            _suppressedStage = {title: stageTitle, loop: _currentLoop};
            playBGMWithSource(_jukeboxTitle, "jukebox", _jukeboxLoop, null);
        }
        org.flashNight.arki.render.FrameBroadcaster.pushUiState("jbo:" + (_jukeboxOverride ? "1" : "0"));
    }

    public function setTrueRandom(value:Boolean):Void {
        _trueRandom = (value == true);
        trace("[BGM] trueRandom=" + _trueRandom);
        org.flashNight.arki.render.FrameBroadcaster.pushUiState("jbr:" + (_trueRandom ? "1" : "0"));
    }

    public function setPlayMode(mode:String):Void {
        if (mode != "singleLoop" && mode != "albumLoop" && mode != "playOnce") mode = "singleLoop";
        _playMode = mode;
        trace("[BGM] playMode=" + _playMode);
        org.flashNight.arki.render.FrameBroadcaster.pushUiState("jbm:" + _playMode);
        // 无条件更新 _jukeboxLoop（即使被 stage 压制，恢复时也用新值）
        if (_jukeboxActive) {
            _jukeboxLoop = (_playMode == "singleLoop");
            // 仅在当前实际播放 jukebox 时才通知 native 层
            if (_bgmSource == "jukebox") {
                AudioBridge.setBGMLooping(_jukeboxLoop);
            }
        }
    }

    public function getPlayMode():String {
        return _playMode;
    }

    public function getJukeboxOverride():Boolean {
        return _jukeboxOverride;
    }

    public function getTrueRandom():Boolean {
        return _trueRandom;
    }

    // ── suppressed 恢复 ──

    private function restoreSuppressed():Void {
        if (_suppressedStage != null) {
            var st:Object = _suppressedStage;
            _suppressedStage = null;
            playBGMWithSource(st.title, "stage", st.loop, null);
            return;
        }
        if (_suppressedScene != null) {
            var sc:Object = _suppressedScene;
            _suppressedScene = null;
            if (sc.type == "album") {
                playAlbumBGM(sc.album, "scene", sc.loop, sc.defaultTitle);
            } else {
                playBGMWithSource(sc.title, "scene", sc.loop, null);
            }
            return;
        }
        stopBGM();
    }

    private function findTitleByUrl(url:String):String {
        if (url == null || url == undefined) return null;
        for (var title:String in bgmList) {
            if (bgmList[title].url == url) return title;
        }
        return null;
    }

    // ══════════════════════════════════════════════════════════
    // ██  原有 API（保持兼容）
    // ══════════════════════════════════════════════════════════

    /**
     * 播放音效 — SFX 快车道（S 前缀）
     */
    public function playSound(soundId:String, source:String):Void {
        if (globalVolume == 0) return;
        AudioBridge.playSound(soundId);
    }

    /**
     * 原始 playBGM — 无优先级检查，保留向后兼容。
     * 新代码应使用 playBGMWithSource。
     */
    public function playBGM(title:String, loop:Boolean, volume:Number):Void {
        doPlayBGM(title, loop, volume);
    }

    /**
     * 内部播放实现（不含优先级逻辑）。
     * @return true 如果实际发起了播放
     */
    private function doPlayBGM(title:String, loop:Boolean, volume:Number):Boolean {
        var bgm:Object = bgmList[title];
        if (bgm == null) return false;
        var url:String = bgm.url;
        if (url == null) return false;

        if (url == "stop") {
            stopBGM();
            return false;
        }

        if (currentBGMUrl == url) return false;

        if (loop !== true) loop = false;
        if (isNaN(volume) || volume < 0) volume = bgm.baseVolume;

        var finalVolume:Number = volume * bgmVolume / 100;
        var fadeSec:Number = bgm.fadeDuration / 30;
        // 不跳过音量=0 的情况：native 层自然静音，恢复音量时通过 bgm_vol/master_vol 生效
        if (!AudioBridge.playBGM(url, loop, finalVolume / 100, fadeSec)) return false;

        currentBGMBaseVolume = volume;
        currentFadeDuration = bgm.fadeDuration;
        currentBGMUrl = url;

        org.flashNight.arki.render.FrameBroadcaster.pushUiState("bgm:" + title);
        return true;
    }

    /** 停止 BGM，淡出时间不低于 1 秒。无优先级检查。 */
    public function stopBGM():Void {
        doStopBGM();
    }

    /**
     * 场景过渡时调用。jukebox override 激活时保持 jukebox 连续播放, 不中断。
     */
    public function stopBGMForTransition():Void {
        if (_jukeboxOverride && _jukeboxActive) {
            trace("[BGM] stopBGMForTransition: skip (jukebox override active)");
            return;
        }
        doStopBGM();
    }

    /**
     * 带来源的停止：stage 发出的 stop 在 override 模式下不能停掉 jukebox。
     */
    public function stopBGMWithSource(source:String):Void {
        if (source == "stage" && _jukeboxOverride && _jukeboxActive) {
            trace("[BGM] stopBGM source=stage result=reject_by_jukebox_override");
            return;
        }
        doStopBGM();
    }

    private function doStopBGM():Void {
        var fadeSec:Number = currentFadeDuration / 30;
        if (fadeSec < 1) fadeSec = 1;
        if (AudioBridge.stopBGM(fadeSec)) {
            currentBGMUrl = null;
            _bgmSource = null;
            _currentAlbum = null;
            org.flashNight.arki.render.FrameBroadcaster.pushUiState("bgm:");
        }
    }

    /**
     * 场景跳转时调用, 清除残留的 stage 上下文. 不停止当前播放.
     * _suppressedStage 无条件清除(覆盖 jukebox override 下 _bgmSource="jukebox" 但
     * _suppressedStage 残留的情况); _bgmSource 仅在 "stage" 时重置.
     */
    public function notifyLeaveBattle():Void {
        var hadStage:Boolean = (_suppressedStage != null || _bgmSource == "stage");
        _suppressedStage = null;
        if (_bgmSource == "stage") {
            _bgmSource = null;
        }
        if (hadStage) {
            trace("[BGM] notifyLeaveBattle: stage context cleared");
        }
    }

    public function stopAll():Void {
        stopBGM();
    }

    public function setGlobalVolume(value:Number):Void {
        if (isNaN(value) || value > 100 || value < 0) return;
        globalVolume = value;
        AudioBridge.setMasterVolume(value / 100);
        org.flashNight.arki.render.FrameBroadcaster.pushUiState("vg:" + Math.round(value));
    }

    public function getGlobalVolume():Number {
        return globalVolume;
    }

    public function setBGMVolume(value:Number):Void {
        if (isNaN(value) || value > 100 || value < 0) return;
        bgmVolume = value;
        var finalVolume:Number = currentBGMBaseVolume * bgmVolume / 100;
        AudioBridge.setBGMVolume(finalVolume / 100);
        org.flashNight.arki.render.FrameBroadcaster.pushUiState("vb:" + Math.round(value));
    }

    public function getBGMVolume():Number {
        return bgmVolume;
    }
}
