import org.flashNight.arki.audio.MusicPlayer;

player = new MusicPlayer();// 创建 MusicPlayer 实例
var testMusicUrl:String = "sounds/Kevin Macleod/Decisions.mp3";

player.preLoad(testMusicUrl);
setTimeout(function ()
{
trace("开始播放");
player.play(testMusicUrl);
},1000);