/* 
 * 文件：org/flashNight/arki/audio/IMusicPlayer.as
 * 说明：定义音乐播放接口，供 MusicEngine 及其各状态调用。
 */
interface org.flashNight.arki.audio.IMusicPlayer {
    function play(clip:String):Void;        // 播放指定音频资源（clip 为音频标识或路径）
    function stop():Void;                   // 停止播放
    function fadeIn(duration:Number):Void;  // 指定时间内淡入（duration 单位：帧或秒，由具体实现决定）
    function fadeOut(duration:Number):Void; // 指定时间内淡出
    function setVolume(volume:Number):Void; // 设置音量（例如 0～100）
}
