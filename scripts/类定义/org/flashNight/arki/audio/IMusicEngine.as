/* 
 * 文件：org/flashNight/arki/audio/IMusicEngine.as
 * 说明：音效/音乐引擎接口，定义通用的音频控制方法，包括命令处理、停止、设置音量等。
 */
interface org.flashNight.arki.audio.IMusicEngine {
    function handleCommand(command:String, params:Object):Boolean;  // 处理音效或音乐命令
    function stop():Void;                                        // 停止当前播放
    function setVolume(volume:Number):Void;                      // 设置音量
}
