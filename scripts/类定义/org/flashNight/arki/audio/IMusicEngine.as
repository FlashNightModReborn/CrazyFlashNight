/* 
 * 文件：org/flashNight/arki/audio/IMusicEngine.as
 * 说明：音效引擎接口，定义通用的音效控制方法，包括音效播放、暂停、停止等。
 */
interface org.flashNight.arki.audio.IMusicEngine {
    function handleCommand(command:String, params:Object):Void;  // 处理音效命令
    function stop():Void;                                        // 停止当前播放
    function setVolume(volume:Number):Void;                      // 设置音量
}
