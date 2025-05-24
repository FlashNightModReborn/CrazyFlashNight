import org.flashNight.arki.audio.IMusicPlayer;
import org.flashNight.gesh.path.PathManager;

/**
 * @class MusicPlayer
 * @description 音乐播放器类，支持预加载和流式加载音频播放，并提供渐入/渐出效果（采用 enterFrame 事件实现平滑过渡）。
 *              每个 MusicPlayer 实例均持有一个独立的影片剪辑，用于控制音频播放及动画效果。
 * @version 1.1
 */
class org.flashNight.arki.audio.MusicPlayer implements IMusicPlayer {
    // #region 字段定义

    /** 预加载音频的 Sound 实例（非流式加载） */
    private var _preloadedSound:Sound;
    
    /** 流式加载音频的 Sound 实例 */
    private var _streamSound:Sound;
    
    /** 当前正在播放的 Sound 实例（可能是预加载或流式加载） */
    private var _activeSound:Sound;
    
    /** 预加载音频的 URL */
    private var _preloadedUrl:String;
    
    /** 标记是否已成功预加载 */
    private var _isPreloaded:Boolean = false;
    
    /** 是否循环播放标记 */
    private var _loop:Boolean = false;
    
    /** 当前音量（默认 100，范围 0-100） */
    private var _volume:Number = 100;
    
    /** 用于音频及动画控制的影片剪辑 */
    private var _movieClip:MovieClip;
    
    // 以下属性用于渐入/渐出效果
    /** 渐变类型，"in" 表示渐入，"out" 表示渐出，null 表示无渐变 */
    private var _fadeType:String = null;
    /** 渐变持续的帧数 */
    private var _fadeDuration:Number = 0;
    /** 当前渐变已进行的帧数 */
    private var _fadeFrameCount:Number = 0;
    /** 渐变起始音量 */
    private var _fadeStartVolume:Number = 0;
    /** 渐变目标音量 */
    private var _fadeTargetVolume:Number = 0;
    
    /** 静态计数器，用于生成独立影片剪辑的名称 */
    private static var uid:Number = 0;
    
    // #endregion

    // #region 构造函数

    /**
     * 构造函数，创建 MusicPlayer 实例并初始化控制影片剪辑
     */
    public function MusicPlayer() {
        trace("MusicPlayer: 构造函数调用，创建 MusicPlayer 实例");
        // 创建一个独立的空影片剪辑，用于音频播放和动画控制。默认在_root.musicManager中创建，若未找到则在根影片剪辑中创建
        var parentclip = _root.musicManager != null ? _root.musicManager : _root;
        _movieClip = parentclip.createEmptyMovieClip("musicPlayer_" + MusicPlayer.uid++, parentclip.getNextHighestDepth());
        // trace("创建影片剪辑: " + _movieClip)
    }

    // #endregion

    // #region 公共方法

    /**
     * 预加载音频（非流式加载，完整加载到内存中）
     * @param clip 要加载的音频剪辑路径（相对或绝对路径）
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
     * @param clip 要播放的音频剪辑路径
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
            _activeSound.start(0, _loop ? null : 1);
            _activeSound.setVolume(_volume);
            // 若非循环播放，设置播放完成后的回调
            if (!_loop) {
                var self:MusicPlayer = this;
                _activeSound.onSoundComplete = function():Void {
                    self.resetSound(); // 自动重置音频
                };
            }
            return;
        }
        if(!_isPreloaded && _preloadedUrl == fullPath && _preloadedSound != undefined){
            _root.发布消息("背景音乐尚未完成预载！");
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
                self._activeSound = self._streamSound;
                self._activeSound.start(0, null);
                self._activeSound.setVolume(self._volume);
                // 根据是否循环播放设置播放完成后的回调
                self._activeSound.onSoundComplete = function():Void {
                    if (self._loop) {
                        trace("MusicPlayer._streamSound.onSoundComplete: 再次流式加载: " + fullPath);
                        self._activeSound.loadSound(fullPath, true); // 再次流式加载
                    }else{
                        self.resetSound(); // 自动重置音频
                    }
                };
            } else {
                trace("MusicPlayer.play.onLoad: 流式加载失败: " + fullPath);
            }
        };
        trace("MusicPlayer.play: 开始流式加载: " + fullPath);
        _streamSound.loadSound(fullPath, true); // 流式加载
    }
    
    /**
     * 停止当前播放的音频
     */
    public function stop():Void {
        trace("MusicPlayer.stop: 停止播放调用");
        if (_activeSound != undefined) {
            _activeSound.stop();
        } else {
            trace("MusicPlayer.stop: 当前没有活动声音，无需停止");
        }
    }
    
    /**
     * 设置音量，并立即作用于当前播放的音频
     * @param volume 目标音量值（范围 0-100）
     */
    public function setVolume(volume:Number):Void {
        _volume = volume;
        if (_activeSound != undefined) {
            _activeSound.setVolume(_volume);
        }
    }
    
    /**
     * 跳转到指定的播放位置（单位：秒）
     * @param position 播放位置（秒）
     */
    public function jumpTo(position:Number):Void {
        if (_activeSound != undefined) {
            _activeSound.start(position);
        }
    }
    
    /**
     * 设置是否循环播放
     * @param loop true 表示循环播放，false 表示不循环
     */
    public function setLoop(loop:Boolean):Void {
        _loop = loop;
    }
    
    /**
     * 静音处理，将音量设置为 0
     */
    public function mute():Void {
        setVolume(0);
    }
    
    /**
     * 取消静音，恢复音量到之前设置的值
     */
    public function unmute():Void {
        setVolume(_volume);
    }
    
    /**
     * 渐入效果，通过 enterFrame 事件逐帧增加音量
     * @param duration 渐入过渡所需的帧数
     */
    public function fadeIn(duration:Number):Void {
        trace("MusicPlayer.fadeIn: 开始渐入效果, duration = " + duration + " 帧");
        if (_activeSound == undefined) {
            trace("MusicPlayer.fadeIn: 没有活动声音，不执行渐入效果");
            return;
        }
        // 如果已有渐变效果正在进行，则先取消
        delete _movieClip.onEnterFrame;
        
        _fadeType = "in";
        _fadeDuration = duration;
        _fadeFrameCount = 0;
        _fadeStartVolume = 0;
        _fadeTargetVolume = _volume; // 目标音量为当前设置的音量
        
        // 将当前音量设为起始音量（0）
        _activeSound.setVolume(_fadeStartVolume);
        
        // 使用 enterFrame 事件处理渐入效果
        var self:MusicPlayer = this;
        _movieClip.onEnterFrame = function():Void {
            trace("MusicPlayer.fadeIn.onEnterFrame: 处理渐入效果，当前帧数 = " + self._fadeFrameCount);
            self.handleFade();
        };
    }
    
    /**
     * 渐出效果，通过 enterFrame 事件逐帧降低音量
     * @param duration 渐出过渡所需的帧数
     */
    public function fadeOut(duration:Number):Void {
        trace("MusicPlayer.fadeOut: 开始渐出效果, duration = " + duration + " 帧");
        if (_activeSound == undefined) {
            trace("MusicPlayer.fadeOut: 没有活动声音，不执行渐出效果");
            return;
        }
        // 如果已有渐变效果正在进行，则先取消
        delete _movieClip.onEnterFrame;
        
        _fadeType = "out";
        _fadeDuration = duration;
        _fadeFrameCount = 0;
        // 起始音量设为当前音量（此处取 _volume，即为之前设置的音量值）
        _fadeStartVolume = _volume;
        _fadeTargetVolume = 0; // 渐出目标为 0
        
        // 使用 enterFrame 事件处理渐出效果
        var self:MusicPlayer = this;
        _movieClip.onEnterFrame = function():Void {
            trace("MusicPlayer.fadeOut.onEnterFrame: 处理渐出效果，当前帧数 = " + self._fadeFrameCount);
            self.handleFade();
        };
    }
    
    // #endregion

    // #region 私有方法

    /**
     * 处理渐入/渐出效果，每帧根据当前进度更新音量，完成后移除 enterFrame 事件
     */
    private function handleFade():Void {
        _fadeFrameCount++;
        var newVolume:Number = _fadeStartVolume + ((_fadeTargetVolume - _fadeStartVolume) * _fadeFrameCount / _fadeDuration);
        // 如果达到或超过指定帧数，则确保音量精确到目标值，并取消 enterFrame 事件
        if (_fadeFrameCount >= _fadeDuration) {
            newVolume = _fadeTargetVolume;
            delete _movieClip.onEnterFrame;
            _fadeType = null;
        }
        if (_activeSound != undefined) {
            trace("setVolume: " + newVolume);
            _activeSound.setVolume(newVolume);
        }
    }
    
    /**
     * 重置当前播放的音频状态，不销毁 MusicPlayer 对象
     */
    private function resetSound():Void {
        trace("MusicPlayer.resetSound: 重置音频状态");
        if(_activeSound != undefined) {
            _activeSound.stop();
        }
        _activeSound = null;
    }
    
    // #endregion
}
