/* 
 * 文件：org/flashNight/arki/audio/LightweightSoundEngine.as
 * 说明：一个轻量化的音效引擎，实现 IMusicEngine，不使用 FSM。
 *       主要用于短音效播放，具备最小间隔控制等简单功能。
 */

import org.flashNight.arki.audio.IMusicEngine;
import org.flashNight.arki.audio.SoundPreprocessor;
import org.flashNight.arki.audio.IMusicPlayer; // 若要用到多轨 SoundPlayer，也可引入

class org.flashNight.arki.audio.LightweightSoundEngine implements IMusicEngine {
    
    private var preprocessor:SoundPreprocessor; // 引用预处理器（含 soundManager、soundDict 等）
    private var currentVolume:Number;
    // 记录最后一次播放的音效 ID，用于 stop()
    private var lastSoundId:String;
    
    public function LightweightSoundEngine(preprocessor:SoundPreprocessor) {
        this.preprocessor = preprocessor;
        this.currentVolume = 100; // 默认音量
        this.lastSoundId = null;
    }
    
    /**
     * 实现 IMusicEngine.handleCommand()
     * 常用命令：
     *   - "play": { soundId, volumeMultiplier, source }
     *   - "stop": 无参数
     * 其余命令可根据需要扩展或忽略
     */
    public function handleCommand(command:String, params:Object):Boolean {
        switch(command) {
            case "play":
                return this.handlePlayCommand(params);
            case "stop":
                this.stop();
                return true;
            // 可根据需求扩展 "mute", "unmute", "adjust" 等
            default:
                trace("[LightweightSoundEngine] Unknown command: " + command);
                return false;
        }
    }
    
    /**
     * 处理 "play" 命令
     * params: { soundId: String, source: String (可选) }
     *   - 若多次播放间隔 < minInterval，则拒绝播放
     *   - 根据 soundSourceDict 找到分类 MovieClip
     *   - attachSound 并 setVolume、start()
     */
    private function handlePlayCommand(params:Object):Boolean {
        if (params == null || params.soundId == undefined) {
            trace("[LightweightSoundEngine] Error: 'play' requires 'soundId' parameter.");
            return false;
        }
        var soundId:String = params.soundId;
        // var volumeMultiplier:Number = (params.volumeMultiplier != undefined) ? params.volumeMultiplier : 1;
        var source:String = params.source; // 可选分类
        
        // 根据 preprocessor 决定分类
        var category:String = (source != undefined) ? source : this.preprocessor.soundSourceDict[soundId];
        if (category == undefined) {
            trace("[LightweightSoundEngine] Error: No category found for soundId: " + soundId);
            return false;
        }
        
        // 获取对应轨道 MovieClip
        var target_mc:MovieClip = this.getCategoryMovieClip(category);
        if (!target_mc) {
            trace("[LightweightSoundEngine] Error: Could not get target MovieClip for category: " + category);
            return false;
        }
        
        // 检查最小播放间隔
        var time:Number = getTimer();
        var lastTime:Number = this.preprocessor.soundLastTime[soundId];
        if (!isNaN(lastTime) && time - lastTime < this.preprocessor.minInterval) {
            trace("[LightweightSoundEngine] Play ignored due to min interval for soundId: " + soundId);
            return false;
        }
        this.preprocessor.soundLastTime[soundId] = time;
        
        // 若不存在 Sound 对象，则创建并 attachSound
        if (!this.preprocessor.soundDict[soundId]) {
            this.preprocessor.soundDict[soundId] = new Sound(target_mc);
            this.preprocessor.soundDict[soundId].attachSound(soundId);
        }
        
        var soundObj:Sound = this.preprocessor.soundDict[soundId];
        // 计算最终音量
        // var baseVolume:Number = 100;
        // var vol:Number = Math.floor(volumeMultiplier * baseVolume);
        // vol = Math.max(vol, 1); // 不低于 1
        
        // 如果引擎本身有一个 currentVolume，也可在此叠加
        // 这里只是示范：vol * (this.currentVolume / 100)
        // var finalVolume:Number = Math.floor(vol * (this.currentVolume / 100));
        // soundObj.setVolume(finalVolume);
        
        soundObj.start(0, 1); // 播放一次
        
        this.lastSoundId = soundId;
        trace("[LightweightSoundEngine] Playing soundId=" + soundId + ", category=" + category);
        return true;
    }
    
    /**
     * 根据分类返回相应的 MovieClip
     */
    private function getCategoryMovieClip(category:String):MovieClip {
        var mc:MovieClip = null;
        switch (category) {
            case "武器":
                mc = this.preprocessor.soundManager.武器;
                break;
            case "特效":
                mc = this.preprocessor.soundManager.特效;
                break;
            case "人物":
                mc = this.preprocessor.soundManager.人物;
                break;
        }
        return mc;
    }
    
    /**
     * IMusicEngine.stop(): 停止最后一次播放的音效（若需要“停止所有”，可自行扩展）
     */
    public function stop():Void {
        if (this.lastSoundId != null) {
            var soundObj:Sound = this.preprocessor.soundDict[this.lastSoundId];
            if (soundObj) {
                soundObj.stop();
                trace("[LightweightSoundEngine] Stopped soundId=" + this.lastSoundId);
            }
            this.lastSoundId = null;
        }
    }
    
    /**
     * IMusicEngine.setVolume(...)
     * 调整引擎整体音量，后续播放时会受此影响
     * 也可立即对当前播放的音效应用
     */
    public function setVolume(volume:Number):Void {
    this.currentVolume = volume;
    // 如果最后播放的音效存在，调整其音量
    if (this.lastSoundId != null) {
        var soundObj:Sound = this.preprocessor.soundDict[this.lastSoundId];
        if (soundObj) {
            var oldVol:Number = soundObj.getVolume();
            var newVol:Number = Math.floor(oldVol * (volume / 100));
            soundObj.setVolume(newVol);
        }
    }
    trace("[LightweightSoundEngine] setVolume=" + volume);
}

}
