import org.flashNight.arki.audio.IMusicPlayer;
import org.flashNight.gesh.path.PathManager;

class org.flashNight.arki.audio.MusicPlayer implements IMusicPlayer {
    // 用于预加载的 Sound 实例（非流式加载）
    private var _preloadedSound:Sound;
    // 用于即时播放的 Sound 实例（流式加载）
    private var _streamSound:Sound;
    // 当前正在播放的 Sound 实例（预加载或流式加载）
    private var _activeSound:Sound;
    // 记录预加载音频的 URL
    private var _preloadedUrl:String;
    // 标记是否已成功预加载
    private var _isPreloaded:Boolean = false;
    // 是否循环播放
    private var _loop:Boolean = false;
    // 当前音量（默认 100）
    private var _volume:Number = 100;

    public function MusicPlayer() {
        trace("MusicPlayer: 构造函数调用，创建 MusicPlayer 实例");
    }

    /**
     * 预加载音频（非流式加载，完整加载到内存中）
     */
    public function preLoad(clip:String):Void {
        trace("MusicPlayer.preLoad: 接收到 clip = " + clip);
        var fullPath:String = PathManager.resolvePath(clip);
        if (fullPath == null) {
            trace("MusicPlayer.preLoad: 无法解析路径: " + clip);
            return;
        }
        trace("MusicPlayer.preLoad: resolved path = " + fullPath);
        
        // 如果已预加载且 URL 一致，则无需重复加载
        if (_isPreloaded && _preloadedUrl == fullPath) {
            trace("MusicPlayer.preLoad: 音频已预加载: " + fullPath);
            return;
        }
        _preloadedUrl = fullPath;
        if (_preloadedSound == undefined) {
            _preloadedSound = new Sound();
            trace("MusicPlayer.preLoad: 创建新的 _preloadedSound 实例");
        }
        
        // 保存当前实例引用，用于闭包中访问
        var self:MusicPlayer = this;
        _preloadedSound.onLoad = function(success:Boolean):Void {
            trace("MusicPlayer.preLoad.onLoad: 回调触发，success = " + success + "，加载文件 = " + fullPath);
            if (success) {
                trace("MusicPlayer.preLoad.onLoad: 预加载成功: " + fullPath);
                self._isPreloaded = true;
            } else {
                trace("MusicPlayer.preLoad.onLoad: 预加载失败: " + fullPath);
                self._isPreloaded = false;
            }
        };
        _isPreloaded = false; // 重置标志，等待加载完成
        trace("MusicPlayer.preLoad: 开始加载音频 (非流式模式): " + fullPath);
        _preloadedSound.loadSound(fullPath, false); // 非流式加载
    }

    /**
     * 播放音频。如果该音频已预加载，则直接使用预加载数据播放；否则使用流式加载方式播放
     */
    public function play(clip:String):Void {
        trace("MusicPlayer.play: 接收到 clip = " + clip);
        var fullPath:String = PathManager.resolvePath(clip);
        if (fullPath == null) {
            trace("MusicPlayer.play: 无法解析路径: " + clip);
            return;
        }
        trace("MusicPlayer.play: resolved path = " + fullPath);
        
        // 如果预加载的音频存在且 URL 匹配，则直接播放预加载的 Sound 对象
        if (_isPreloaded && _preloadedUrl == fullPath && _preloadedSound != undefined) {
            trace("MusicPlayer.play: 直接播放已预加载音频: " + fullPath);
            _activeSound = _preloadedSound;
            _activeSound.start(0, _loop ? -1 : 1);
            trace("MusicPlayer.play: 调用 start()");
            _activeSound.setVolume(_volume);
            trace("MusicPlayer.play: 设置音量为 = " + _volume);
            return;
        }
        
        // 否则，使用流式加载方式播放
        if (_streamSound == undefined) {
            _streamSound = new Sound();
            trace("MusicPlayer.play: 创建新的 _streamSound 实例");
        }
        var self:MusicPlayer = this;
        _streamSound.onLoad = function(success:Boolean):Void {
            trace("MusicPlayer.play.onLoad: 回调触发，success = " + success + "，加载文件 = " + fullPath);
            if (success) {
                trace("MusicPlayer.play.onLoad: 流式加载成功: " + fullPath);
                self._activeSound = self._streamSound;
                self._activeSound.start(0, self._loop ? -1 : 1);
                trace("MusicPlayer.play.onLoad: 调用 start()");
                self._activeSound.setVolume(self._volume);
                trace("MusicPlayer.play.onLoad: 设置音量为 = " + self._volume);
            } else {
                trace("MusicPlayer.play.onLoad: 流式加载失败: " + fullPath);
            }
        };
        trace("MusicPlayer.play: 开始流式加载: " + fullPath);
        _streamSound.loadSound(fullPath, true); // 流式加载
    }

    /**
     * 停止播放
     */
    public function stop():Void {
        trace("MusicPlayer.stop: 停止播放调用");
        if (_activeSound != undefined) {
            _activeSound.stop();
            trace("MusicPlayer.stop: 调用 _activeSound.stop() 完成");
        } else {
            trace("MusicPlayer.stop: 当前没有活动声音，无需停止");
        }
    }

    /**
     * 模拟淡入效果：直接调整音量至当前音量值
     */
    public function fadeIn(duration:Number):Void {
        trace("MusicPlayer.fadeIn: 调用淡入效果，持续时间 (帧数) = " + duration);
        // 模拟淡入效果：直接设置音量为 _volume
        setVolume(_volume);
    }

    /**
     * 模拟淡出效果：直接将音量设置为 0
     */
    public function fadeOut(duration:Number):Void {
        trace("MusicPlayer.fadeOut: 调用淡出效果，持续时间 (帧数) = " + duration);
        // 模拟淡出效果：直接将音量设置为 0
        setVolume(0);
    }

    /**
     * 设置音量（会作用于当前正在播放的音频）
     */
    public function setVolume(volume:Number):Void {
        trace("MusicPlayer.setVolume: 请求设置音量为 = " + volume);
        _volume = volume;
        if (_activeSound != undefined) {
            _activeSound.setVolume(_volume);
            trace("MusicPlayer.setVolume: 已更新 _activeSound 的音量为 = " + _volume);
        } else {
            trace("MusicPlayer.setVolume: 当前没有活动声音，无法设置音量");
        }
    }

    /**
     * 跳转到指定播放位置（单位：秒）
     */
    public function jumpTo(position:Number):Void {
        trace("MusicPlayer.jumpTo: 请求跳转播放位置到 = " + position + " 秒");
        if (_activeSound != undefined) {
            _activeSound.start(position);
            trace("MusicPlayer.jumpTo: 调用 start(" + position + ")");
        } else {
            trace("MusicPlayer.jumpTo: 当前没有活动声音，无法跳转播放位置");
        }
    }

    /**
     * 设置是否循环播放
     */
    public function setLoop(loop:Boolean):Void {
        trace("MusicPlayer.setLoop: 设置循环播放为 = " + loop);
        _loop = loop;
    }

    /**
     * 静音
     */
    public function mute():Void {
        trace("MusicPlayer.mute: 静音调用");
        setVolume(0);
    }

    /**
     * 取消静音（恢复到当前音量）
     */
    public function unmute():Void {
        trace("MusicPlayer.unmute: 取消静音调用");
        setVolume(_volume);
    }
    
    /**
     * 清理加载回调，防止在 SWF 卸载后仍触发回调（可在卸载前调用）
     */
    public function dispose():Void {
        trace("MusicPlayer.dispose: 释放加载回调，准备卸载 MusicPlayer");
        if(_preloadedSound != undefined) {
            _preloadedSound.onLoad = null;
            trace("MusicPlayer.dispose: _preloadedSound.onLoad 已清空");
        }
        if(_streamSound != undefined) {
            _streamSound.onLoad = null;
            trace("MusicPlayer.dispose: _streamSound.onLoad 已清空");
        }
    }
}
