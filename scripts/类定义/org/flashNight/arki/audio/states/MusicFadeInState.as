/* 
 * 文件：org/flashNight/arki/audio/states/MusicFadeInState.as
 * 说明：淡入状态，进入该状态时调用 fadeIn，逐帧累计计时，当计时达到设定的淡入时长后，
 *       状态机将通过过渡函数切换到播放状态。
 */
 
import org.flashNight.arki.audio.states.*;

class org.flashNight.arki.audio.states.MusicFadeInState extends BaseMusicState {
    private var fadeDuration:Number; // 淡入所需的帧数（可根据实际需求调整）
    private var elapsed:Number;
    
    public function MusicFadeInState() {
        super(null, null, null);
        fadeDuration = 60; // 例如：60 帧内淡入完成（假设 30fps 则约 2 秒）
        elapsed = 0;
    }
    
    public function onEnter():Void {
        trace("MusicFadeInState: Entering FadeIn State");
        elapsed = 0;
        if (musicPlayer != null) {
            // 调用淡入方法，由具体实现决定淡入效果
            musicPlayer.fadeIn(fadeDuration);
        }
    }
    
    public function onAction():Void {
        // 每帧更新计时器
        elapsed++;
    }
    
    public function onExit():Void {
        trace("MusicFadeInState: Exiting FadeIn State");
    }
    
    // 供状态机过渡函数检测：是否淡入已完成
    public function isComplete():Boolean {
        return elapsed >= fadeDuration;
    }
}
