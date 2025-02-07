import org.flashNight.arki.audio.IMusicPlayer;
import org.flashNight.gesh.path.PathManager;

class org.flashNight.arki.audio.MusicPlayer implements org.flashNight.arki.audio.IMusicPlayer {
    private var _sound:Sound; // Sound 对象
    private var _url:String; // 当前音频文件的 URL
    private var _loop:Boolean; // 是否循环播放
    private var _volume:Number = 100; // 音量（默认 100）

    /* IMusicPlayer 接口实现 */

    public function play(clip:String):Void {
        // 拼接完整路径
        var fullPath:String = PathManager.resolvePath(clip);
        if (fullPath == null) {
            trace("无法解析路径: " + clip);
            return;
        }

        // 如果 Sound 对象尚未创建，初始化
        if (_sound == undefined) {
            _sound = new Sound();
            _sound.onLoad = onLoadComplete;
            _sound.onID3 = function (id3:Object) {
                // 异步加载完成
                _sound.start(0, _loop ? -1 : 1);
            };
        }

        // 加载音频
        _url = fullPath;
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

        // 创建一个临时 Sound 对象预加载
        var preLoadSound:Sound = new Sound();
        preLoadSound.onLoad = function (success:Boolean) {
            if (success) {
                trace("预加载成功: " + fullPath);
                // 加载完成后卸载 Sound 对象以节省内存
                preLoadSound = null;
            } else {
                trace("预加载失败: " + fullPath);
            }
        };
        preLoadSound.loadSound(fullPath, false); // 先加载到内存中
    }

    /* 播放完成后的清理 */

    public function onLoadComplete(success:Boolean):Void {
        if (success && !_loop) {
            // 如果未设置循环，播放完毕后卸载 Sound 对象
            _sound = null;
        }
    }
}