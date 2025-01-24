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

_root.soundManager.武器.loadMovie("flashswf/sounds/音效-武器.swf");
_root.soundManager.特效.loadMovie("flashswf/sounds/音效-特效.swf");
_root.soundManager.人物.loadMovie("flashswf/sounds/音效-人物.swf");

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
	//this.soundDict[音效id].setVolume(音量);
	this.soundDict[音效id].start(0,1);
	return true;
}

//使用BaseLoader分别导入三个DOMDocument里的标识符
var loader0 = new org.flashNight.gesh.xml.LoadXml.BaseXMLLoader("flashswf/sounds/音效-武器/DOMDocument.xml");
loader0.load(function(domdata:Object):Void {
    var soundItems = domdata.media.DOMSoundItem;
    for (var soundName:String in soundItems) {
        var soundIdentifier = soundItems[soundName].linkageIdentifier;
        if (soundIdentifier != null) {
            _root.soundManager.soundSourceDict[soundIdentifier] = "武器";
        }
    }
}, function():Void {
    onError();
});

var loader1 = new org.flashNight.gesh.xml.LoadXml.BaseXMLLoader("flashswf/sounds/音效-特效/DOMDocument.xml");
loader1.load(function(domdata:Object):Void {
    var soundItems = domdata.media.DOMSoundItem;
    for (var soundName:String in soundItems) {
        var soundIdentifier = soundItems[soundName].linkageIdentifier;
        if (soundIdentifier != null) {
            _root.soundManager.soundSourceDict[soundIdentifier] = "特效";
        }
    }
}, function():Void {
    onError();
});

var loader2 = new org.flashNight.gesh.xml.LoadXml.BaseXMLLoader("flashswf/sounds/音效-人物/DOMDocument.xml");
loader2.load(function(domdata:Object):Void {
    var soundItems = domdata.media.DOMSoundItem;
    for (var soundName:String in soundItems) {
        var soundIdentifier = soundItems[soundName].linkageIdentifier;
        if (soundIdentifier != null) {
            _root.soundManager.soundSourceDict[soundIdentifier] = "人物";
        }
    }
}, function():Void {
    onError();
});

/*
function 随机基地音乐(){
	_root.音乐播放界面.音乐跳转(基地音乐ID库[random(基地音乐ID库.length)]);
}
function 随机战斗音乐(){
	_root.音乐播放界面.音乐跳转(战斗音乐ID库[random(战斗音乐ID库.length)]);
}

基地音乐ID库 = [11, 13, 14, 15, 16, 17, 15, 16, 17];
战斗音乐ID库 = [1, 2, 4, 5, 6, 7, 8, 9, 10, 18, 19, 20, 21, 22, 23, 24, 25, 26];
*/