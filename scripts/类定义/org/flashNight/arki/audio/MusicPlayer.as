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
        // 构造函数，可根据需要初始化
    }

    /**
     * 预加载音频（非流式加载，完整加载到内存中）
     */
    public function preLoad(clip:String):Void {
        var fullPath:String = PathManager.resolvePath(clip);
        if (fullPath == null) {
            trace("无法解析路径: " + clip);
            return;
        }
        // 如果已预加载且 URL 一致，则无需重复加载
        if (_isPreloaded && _preloadedUrl == fullPath) {
            trace("音频已预加载: " + fullPath);
            return;
        }
        _preloadedUrl = fullPath;
        if (_preloadedSound == undefined) {
            _preloadedSound = new Sound();
        }
        // 保存当前实例引用，用于闭包中访问
        var self:MusicPlayer = this;
        _preloadedSound.onLoad = function(success:Boolean):Void {
            if (success) {
                trace("预加载成功: " + fullPath);
                self._isPreloaded = true;
            } else {
                trace("预加载失败: " + fullPath);
                self._isPreloaded = false;
            }
        };
        _isPreloaded = false; // 重置标志，等待加载完成
        _preloadedSound.loadSound(fullPath, false); // 非流式加载
    }

    /**
     * 播放音频。如果该音频已预加载，则直接使用预加载数据播放；否则使用流式加载方式播放
     */
    public function play(clip:String):Void {
        var fullPath:String = PathManager.resolvePath(clip);
        if (fullPath == null) {
            trace("无法解析路径: " + clip);
            return;
        }
        // 如果预加载的音频存在且 URL 匹配，则直接播放预加载的 Sound 对象
        if (_isPreloaded && _preloadedUrl == fullPath && _preloadedSound != undefined) {
            trace("直接播放已预加载音频: " + fullPath);
            _activeSound = _preloadedSound;
            _activeSound.start(0, _loop ? -1 : 1);
            _activeSound.setVolume(_volume);
            return;
        }
        // 否则，使用流式加载方式播放
        if (_streamSound == undefined) {
            _streamSound = new Sound();
        }
        var self:MusicPlayer = this;
        _streamSound.onLoad = function(success:Boolean):Void {
            if (success) {
                trace("流式加载成功: " + fullPath);
                self._activeSound = self._streamSound;
                self._activeSound.start(0, self._loop ? -1 : 1);
                self._activeSound.setVolume(self._volume);
            } else {
                trace("流式加载失败: " + fullPath);
            }
        };
        trace("开始播放");
        _streamSound.loadSound(fullPath, true); // 流式加载
    }

    /**
     * 停止播放
     */
    public function stop():Void {
        if (_activeSound != undefined) {
            _activeSound.stop();
        }
    }

    /**
     * 模拟淡入效果：直接调整音量至当前音量值
     */
    public function fadeIn(duration:Number):Void {
        setVolume(_volume);
    }

    /**
     * 模拟淡出效果：直接将音量设置为 0
     */
    public function fadeOut(duration:Number):Void {
        setVolume(0);
    }

    /**
     * 设置音量（会作用于当前正在播放的音频）
     */
    public function setVolume(volume:Number):Void {
        _volume = volume;
        if (_activeSound != undefined) {
            _activeSound.setVolume(_volume);
        }
    }

    /**
     * 跳转到指定播放位置（单位：秒）
     */
    public function jumpTo(position:Number):Void {
        if (_activeSound != undefined) {
            _activeSound.start(position);
        }
    }

    /**
     * 设置是否循环播放
     */
    public function setLoop(loop:Boolean):Void {
        _loop = loop;
    }

    /**
     * 静音
     */
    public function mute():Void {
        setVolume(0);
    }

    /**
     * 取消静音（恢复到当前音量）
     */
    public function unmute():Void {
        setVolume(_volume);
    }
    
    /**
     * 清理加载回调，防止在 SWF 卸载后仍触发回调（可在卸载前调用）
     */
    public function dispose():Void {
        if(_preloadedSound != undefined) {
            _preloadedSound.onLoad = null;
        }
        if(_streamSound != undefined) {
            _streamSound.onLoad = null;
        }
    }
}
