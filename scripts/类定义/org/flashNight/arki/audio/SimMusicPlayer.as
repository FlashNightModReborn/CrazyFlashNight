/* 
 * 文件：org/flashNight/arki/audio/SimMusicPlayer.as
 * 说明：一个模拟的音乐播放器，通过 trace 输出来模拟播放、淡入淡出、跳转、循环、静音等行为。
 */
 
import org.flashNight.arki.audio.IMusicPlayer;

class org.flashNight.arki.audio.SimMusicPlayer implements IMusicPlayer {
    
    private var currentClip:String;
    private var volume:Number;
    private var looping:Boolean;
    private var isMuted:Boolean;
    
    public function SimMusicPlayer() {
        currentClip = "";
        volume = 100;
        looping = false;
        isMuted = false;
    }
    
    public function play(clip:String):Void {
        currentClip = clip;
        trace("[SimMusicPlayer] play: " + clip);
    }
    
    public function stop():Void {
        trace("[SimMusicPlayer] stop playback");
        currentClip = "";
    }
    
    public function fadeIn(duration:Number):Void {
        trace("[SimMusicPlayer] fadeIn over " + duration + " frames");
    }
    
    public function fadeOut(duration:Number):Void {
        trace("[SimMusicPlayer] fadeOut over " + duration + " frames");
    }
    
    public function setVolume(volume:Number):Void {
        this.volume = volume;
        trace("[SimMusicPlayer] setVolume: " + volume);
    }
    
    public function jumpTo(position:Number):Void {
        trace("[SimMusicPlayer] jump to position: " + position);
    }
    
    public function setLoop(loop:Boolean):Void {
        this.looping = loop;
        trace("[SimMusicPlayer] setLoop: " + loop);
    }
    
    public function mute():Void {
        isMuted = true;
        trace("[SimMusicPlayer] mute");
    }
    
    public function unmute():Void {
        isMuted = false;
        trace("[SimMusicPlayer] unmute");
    }

    public function preLoad(clip:String):Void {
        isMuted = false;
        trace("[SimMusicPlayer] preLoad " + clip);
    }
}
