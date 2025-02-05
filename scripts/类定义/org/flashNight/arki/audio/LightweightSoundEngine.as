/* 
 * 文件：org/flashNight/arki/audio/LightweightSoundEngine.as
 * 说明：轻量化音效引擎，负责音效的快速播放，满足不需要状态机的简单音效需求。
 */

import org.flashNight.arki.audio.IMusicEngine;

class org.flashNight.arki.audio.LightweightSoundEngine implements IMusicEngine {
    private var soundDict:Object;
    private var soundLastTime:Object;
    private var soundSourceDict:Object;
    private var minInterval:Number;
    
    public function LightweightSoundEngine() {
        this.soundDict = new Object();
        this.soundLastTime = new Object();
        this.soundSourceDict = new Object();
        this.minInterval = 90;  // 最小播放间隔为 90ms
    }

    // 实现 IMusicEngine 接口的 handleCommand 方法
    public function handleCommand(command:String, params:Object):Void {
        switch (command) {
            case "play":
                this.playSound(params.soundId, params.volumeMultiplier, params.soundSource);
                break;
            case "stop":
                this.stop();
                break;
            case "setVolume":
                this.setVolume(params.volume);
                break;
            default:
                trace("[LightweightSoundEngine] Command not recognized: " + command);
        }
    }

    // 播放音效
    private function playSound(soundId:String, volumeMultiplier:Number, soundSource:String):Void {
        var target_mc:MovieClip;
        switch (this.soundSourceDict[soundId]) {
            case "武器":
                target_mc = _root.soundManager.武器;
                break;
            case "特效":
                target_mc = _root.soundManager.特效;
                break;
            case "人物":
                target_mc = _root.soundManager.人物;
                break;
            default:
                return;
        }
        
        if (!this.soundDict[soundId]) {
            this.soundDict[soundId] = new Sound(target_mc);
            this.soundDict[soundId].attachSound(soundId);
        }
        
        var time:Number = getTimer();
        // 若两次播放声音小于最小间隔则无法播放
        if (!isNaN(this.soundLastTime[soundId]) && time - this.soundLastTime[soundId] < this.minInterval) {
            return;
        }
        
        this.soundLastTime[soundId] = time;
        var volume:Number = Math.floor(volumeMultiplier * _root.音效音量);
        volume = Math.max(volume, 1);
        this.soundDict[soundId].setVolume(volume);
        this.soundDict[soundId].start(0, 1);  // 播放一次
        trace("[LightweightSoundEngine] Playing soundId: " + soundId + " with volume: " + volume);
    }

    public function stop():Void {
        trace("[LightweightSoundEngine] Stopping sound.");
        // 停止播放当前音效
    }

    public function setVolume(volume:Number):Void {
        trace("[LightweightSoundEngine] Setting volume to: " + volume);
        // 设置音量
    }
}
