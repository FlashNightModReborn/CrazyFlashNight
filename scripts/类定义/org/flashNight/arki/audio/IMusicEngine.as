/* 
 * 文件：org/flashNight/arki/audio/IMusicEngine.as
 * 说明：定义音效引擎的基本接口，适用于轻量化音效引擎（例如用于音效播放）和复杂音乐引擎（例如背景音乐、点歌等）。
 */
 
interface org.flashNight.arki.audio.IMusicEngine {
    // 播放音效（clip 为音效标识）
    function play(clip:String):Void;
    // 停止当前播放的音效
    function stop():Void;
    // 设置音量
    function setVolume(volume:Number):Void;
    // 跳转到指定播放位置（单位由具体实现定义）
    function jumpTo(position:Number):Void;
    // 设置是否循环播放
    function setLoop(loop:Boolean):Void;
    // 静音
    function mute():Void;
    // 取消静音
    function unmute():Void;
}
