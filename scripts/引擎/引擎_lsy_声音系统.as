import org.flashNight.arki.audio.SoundPreprocessor;
import org.flashNight.arki.audio.SoundEffectManager;

_root.createEmptyMovieClip("musicManager", 65532); // BGM总影片剪辑

var preproc = new SoundPreprocessor(null);
_root.soundEffectManager = new SoundEffectManager(preproc);

_root.播放音效 = function(音效id, 声音源){
	_root.soundEffectManager.playSound(音效id, 声音源);
}

/*
_root.createEmptyMovieClip("soundManager",_root.层级管理器.soundManager);
_root.soundManager.soundDict = new Object();
_root.soundManager.soundLastTime = new Object();
_root.soundManager.soundSourceDict = new Object();

//相同声音播放的最小间隔为90ms
_root.soundManager.minInterval = 90;

//音效分为武器，特效，人物三个文件
_root.soundManager.createEmptyMovieClip("武器",0);
_root.soundManager.createEmptyMovieClip("特效",1);
_root.soundManager.createEmptyMovieClip("人物",2);

_root.soundManager.武器.loadMovie("sounds/音效-武器.swf");
_root.soundManager.特效.loadMovie("sounds/音效-特效.swf");
_root.soundManager.人物.loadMovie("sounds/音效-人物.swf");

_root.播放音效 = function(音效id, 音量乘数, 声音源){
	_root.soundManager.playSound(音效id,音量乘数,声音源);
}

_root.soundManager.playSound = function(音效id, 音量乘数, 声音源){
    var target_mc;
    switch(this.soundSourceDict[音效id]){
        case "武器":
            target_mc = this.武器;
            break;
        case "特效":
            target_mc = this.特效;
            break;
        case "人物":
            target_mc = this.人物;
            break;
        default:
            return false;
    }
    if(!this.soundDict[音效id]){
		this.soundDict[音效id] = new Sound(target_mc);
		this.soundDict[音效id].attachSound(音效id);
	}
	var time = getTimer();
	//若两次播放声音小于最小间隔则无法播放
	if(!isNaN(this.soundLastTime[音效id]) && time - this.soundLastTime[音效id] < this.minInterval) return false;
	this.soundLastTime[音效id] = time;
	音量乘数 = (音量乘数 >= 1 || 音量乘数 <= 0) ? 1 : 音量乘数;
	var 音量 = Math.floor(音量乘数 * _root.音效音量);
	音量 = Math.max(音量, 1);
	this.soundDict[音效id].setVolume(音量);
	this.soundDict[音效id].start(0,1);
	return true;
}

//使用BaseLoader分别导入三个DOMDocument里的标识符
var loader0 = new org.flashNight.gesh.xml.LoadXml.BaseXMLLoader("sounds/音效-武器/DOMDocument.xml");
loader0.load(function(domdata:Object):Void {
    var soundItems = domdata.media.DOMSoundItem;
    for (var i in soundItems) {
        var soundIdentifier = soundItems[i].linkageIdentifier;
        if (soundIdentifier != null) {
            _root.soundManager.soundSourceDict[soundIdentifier] = "武器";
        }
    }
}, function():Void {
    onError();
});

var loader1 = new org.flashNight.gesh.xml.LoadXml.BaseXMLLoader("sounds/音效-特效/DOMDocument.xml");
loader1.load(function(domdata:Object):Void {
    var soundItems = domdata.media.DOMSoundItem;
    for (var i in soundItems) {
        var soundIdentifier = soundItems[i].linkageIdentifier;
        if (soundIdentifier != null) {
            _root.soundManager.soundSourceDict[soundIdentifier] = "特效";
        }
    }
}, function():Void {
    onError();
});

var loader2 = new org.flashNight.gesh.xml.LoadXml.BaseXMLLoader("sounds/音效-人物/DOMDocument.xml");
loader2.load(function(domdata:Object):Void {
    var soundItems = domdata.media.DOMSoundItem;
    for (var i in soundItems) {
        var soundIdentifier = soundItems[i].linkageIdentifier;
        if (soundIdentifier != null) {
            _root.soundManager.soundSourceDict[soundIdentifier] = "人物";
        }
    }
}, function():Void {
    onError();
});
*/