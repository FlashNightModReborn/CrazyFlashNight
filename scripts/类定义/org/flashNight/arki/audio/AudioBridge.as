/**
 * 文件：org/flashNight/arki/audio/AudioBridge.as
 * 说明：音频桥接层，将 Flash 侧的播放指令通过 XMLSocket 发送到 launcher 的 native 音频引擎。
 *
 * SFX 采用帧末合批模式：帧内 playSound() 累积 id 到缓冲区，
 * 帧末由 FrameBroadcaster.send() 调用 flush() 一次性发送。
 * 协议：S{id1}|{id2}|{id3}\0（管道符分隔，单条消息）
 *
 * BGM/音量控制立即发送（低频操作，无需合批）。
 * AudioBridge 是透明传输层，不做任何归一化运算。
 */

import org.flashNight.neur.Server.ServerManager;

class org.flashNight.arki.audio.AudioBridge {
    private static var _sm:ServerManager;

    /** SFX 合批缓冲区：帧内累积，帧末 flush */
    private static var _sfxBuf:String = null;

    /**
     * 初始化桥接层，获取 ServerManager 单例引用。
     * 必须在 ServerManager 连接建立后调用。
     */
    public static function init():Void {
        _sm = ServerManager.getInstance();
    }

    /**
     * SFX 合批写入：帧内调用，累积到缓冲区。
     * 不立即发送，由帧末 flush() 统一发送。
     * @param id     音效 linkageIdentifier
     */
    public static function playSound(id:String):Void {
        if (id == null || id.length == 0) return;
        if (_sfxBuf == null) {
            _sfxBuf = id;
        } else {
            _sfxBuf += "|" + id;
        }
    }

    /**
     * 帧末刷新：由 FrameBroadcaster.send() 调用。
     * 将本帧累积的 SFX 请求合并为一条消息发送。
     * 协议：S{id1}|{id2}|{id3}
     */
    public static function flush():Void {
        if (_sfxBuf == null) return;
        if (_sm == null || !_sm.isSocketConnected) {
            _sfxBuf = null;
            return;
        }
        _sm.sendSocketMessage("S" + _sfxBuf);
        _sfxBuf = null;
    }

    /**
     * 场景切换时清空缓冲区。
     */
    public static function reset():Void {
        _sfxBuf = null;
    }

    /**
     * BGM 播放（JSON 路由，立即发送）
     * @return true 消息已发送，false socket 未连接
     */
    public static function playBGM(url:String, loop:Boolean, vol:Number, fade:Number):Boolean {
        if (_sm == null || !_sm.isSocketConnected) return false;
        _sm.sendSocketMessage('{"task":"audio","cmd":"bgm_play","path":"'
            + url + '","loop":' + (loop ? 1 : 0)
            + ',"vol":' + vol + ',"fade":' + fade + '}');
        return true;
    }

    /**
     * BGM 停止（带淡出）
     * @return true 消息已发送，false socket 未连接
     */
    public static function stopBGM(fade:Number):Boolean {
        if (_sm == null || !_sm.isSocketConnected) return false;
        _sm.sendSocketMessage('{"task":"audio","cmd":"bgm_stop","fade":' + fade + '}');
        return true;
    }

    /**
     * BGM 音量动态调整
     * @param vol    最终有效音量（0.0-∞，已由调用方归一化）
     */
    public static function setBGMVolume(vol:Number):Void {
        if (_sm == null || !_sm.isSocketConnected) return;
        _sm.sendSocketMessage('{"task":"audio","cmd":"bgm_vol","vol":' + vol + '}');
    }

    /**
     * 全局主音量设置
     * @param vol    全局音量（0.0-1.0，已由调用方归一化）
     */
    public static function setMasterVolume(vol:Number):Void {
        if (_sm == null || !_sm.isSocketConnected) return;
        _sm.sendSocketMessage('{"task":"audio","cmd":"master_vol","vol":' + vol + '}');
    }

    /**
     * 运行时修改当前 BGM 的循环状态（不重启播放）
     * @param loop   true=循环, false=不循环
     */
    public static function setBGMLooping(loop:Boolean):Void {
        if (_sm == null || !_sm.isSocketConnected) return;
        _sm.sendSocketMessage('{"task":"audio","cmd":"bgm_loop","loop":' + (loop ? 1 : 0) + '}');
    }
}
