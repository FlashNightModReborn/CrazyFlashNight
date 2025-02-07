import org.flashNight.arki.audio.IMusicPlayer;
import org.flashNight.gesh.path.PathManager;

class org.flashNight.arki.audio.MusicPlayer implements IMusicPlayer {
    private var _sound:Sound; // Sound 对象
    private var _url:String; // 当前音频文件的 URL
    private var _loop:Boolean; // 是否循环播放
    private var _volume:Number = 100; // 音量（默认 100）
    private var _isPreloaded:Boolean = false; // 标记音频是否已预加载

    /* IMusicPlayer 接口实现 */

    public function play(clip:String):Void {
        // 拼接完整路径
        var fullPath:String = PathManager.resolvePath(clip);
        if (fullPath == null) {
            trace("无法解析路径: " + clip);
            return;
        }

        // 如果音频文件已预加载，直接播放
        if (_isPreloaded && _url == fullPath) {
            trace("直接播放已预加载音频: " + fullPath);
            if (_sound != undefined) {
                _sound.start(0, _loop ? -1 : 1);
            }
            return;
        }

        // 如果 Sound 对象尚未创建，初始化
        if (_sound == undefined) {
            _sound = new Sound();
            trace("创建新 Sound 对象");
            _sound.onLoad = onLoadComplete;
            _sound.onID3 = function (id3:Object) {
                // 异步加载完成
                _sound.start(0, _loop ? -1 : 1);
            };
        }

        // 加载音频
        _url = fullPath;
        _isPreloaded = false; // 重置预加载标志
        _sound.loadSound(_url, true); // 使用 streaming 模式
    }

    public function stop():Void {
        if (_sound != undefined) {
            _sound.stop();
        }
    }

    public function fadeIn(duration:Number):Void {
        // 模拟淡入效果（直接调整音量）
        setVolume(_volume);
    }

    public function fadeOut(duration:Number):Void {
        // 模拟淡出效果（直接调整音量）
        setVolume(0);
    }

    public function setVolume(volume:Number):Void {
        _volume = volume;
        if (_sound != undefined) {
            _sound.setVolume(_volume);
        }
    }

    public function jumpTo(position:Number):Void {
        if (_sound != undefined) {
            _sound.start(position);
        }
    }

    public function setLoop(loop:Boolean):Void {
        _loop = loop;
    }

    public function mute():Void {
        setVolume(0);
    }

    public function unmute():Void {
        setVolume(_volume);
    }

    /* 预加载功能 */

    public function preLoad(clip:String):Void {
        var fullPath:String = PathManager.resolvePath(clip);
        if (fullPath == null) {
            trace("无法解析路径: " + clip);
            return;
        }

        // 如果已经预加载且路径相同，直接返回
        if (_isPreloaded && _url === fullPath) {
            trace("音频已预加载: " + fullPath);
            return;
        }

        // 初始化主_sound对象（如果未创建）
        if (_sound == undefined) {
            _sound = new Sound();
            _sound.onID3 = function(id3:Object) {}; // 保留onID3避免错误
        }

        // 保存原来的onLoad回调
        var originalOnLoad:Function = _sound.onLoad;

        // 设置预加载的onLoad回调
        _sound.onLoad = function(success:Boolean):Void {
            if (success) {
                trace("预加载成功: " + fullPath);
                _isPreloaded = true;
            } else {
                trace("预加载失败: " + fullPath);
                _isPreloaded = false;
            }
            // 恢复原来的onLoad回调
            _sound.onLoad = originalOnLoad;
        };

        _url = fullPath;
        _isPreloaded = false; // 开始加载前重置标志

        // 使用非流式模式加载到主_sound对象
        _sound.loadSound(_url, false);
    }

    /* 播放完成后的清理 */

    public function onLoadComplete(success:Boolean):Void {
        if (success && !_loop) {
            // 如果未设置循环，播放完毕后卸载 Sound 对象
            _sound = null;
        }
    }
}
