import org.flashNight.arki.scene.*;
import org.flashNight.gesh.object.ObjectUtil;

/**
StageEvent 关卡事件
——————————————————————————————————————————
*/
class org.flashNight.arki.scene.StageEvent {
    public var eventName:String;
    public var parameters:Array;

    public var isDestroyed:Boolean;

    public var animation:Object; // 播放动画
    public var bgm:Object; // BGM控制
    public var callback:Object; // 回调函数
    public var camera:Object; // 摄像机控制
    public var dialogue:Array; // 播放对话
    public var enemy:Array; // 生成单位
    public var followingEvent:Object; // 下个事件
    public var guidance:String; // 引导界面
    public var stageprogress:Object; // 关卡状态
    public var performance:Array; // 关卡演出
    public var sound:Array; // 播放声音

    // ————————————————————————
    // 构造函数
    // ————————————————————————
    public function StageEvent(data) {
        isDestroyed = false;

        eventName = data.EventName;
        parameters = ObjectUtil.toArray(data.Parameter);

        animation = data.Animation;
        bgm = data.BGM;
        callback = data.Callback;
        camera = data.Camera;
        enemy = ObjectUtil.toArray(data.Enemy);
        followingEvent = data.FollowingEvent;
        guidance = data.Guidance;
        stageprogress = data.StageProgress;
        // 
        dialogue = ObjectUtil.toArray(data.Dialogue);
        performance = ObjectUtil.toArray(data.Performance);
        sound = ObjectUtil.toArray(data.Sound);
    }

    public function execute(){
        //动画
        if (animation.Path){
            _root.最上层加载外部动画(animation.Path);
            if (animation.Pause == 1) _root.暂停 = true;
        }

        // 音乐
        if(this.bgm.Command == "play"){
            _root.soundEffectManager.playBGM(this.bgm.Title, this.bgm.Loop, null);
        }else if (this.bgm.Command == "stop"){
            _root.soundEffectManager.stopBGM();
        }

        // 对话（目前跟随事件只能由对话触发）
        executeDialogue();
        // 刷怪
        executeEnemy();

        // 加载引导界面
        if(typeof this.guidance === "string" && this.guidance.length > 0) _root.加载引导界面(this.guidance);

        // 关卡状态
        if(stageprogress === "Finish"){
            _root.gameworld.dispatcher.publish("StageFinished");
        }else if(stageprogress === "Fail"){
            _root.gameworld.dispatcher.publish("StageFailed");
        }else if(stageprogress === "NextStage"){
            _root.gameworld.dispatcher.publish("NextStage");
        }

        //最后执行回调函数
        if(callback.Name){
            if(callback.Parameter){
                var para = ObjectUtil.toArray(callback.Parameter);
                _root.关卡回调函数[callback.Name].apply(_root.关卡回调函数, para);
            }else{
                _root.关卡回调函数[callback.Name]();
            }
        }
        
        this.clear();
    }

    private function executeDialogue(){
       if(dialogue.length > 0){
            _root.暂停 = true;
            _root.SetDialogue(StageInfo.parseSingleDialogue(dialogue));
            // 附加跟随事件
            if(followingEvent.EventName){
                _root.对话框界面.followingEvent = {
                    name: followingEvent.EventName,
                    args: followingEvent.Parameter ? ObjectUtil.toArray(followingEvent.Parameter).unshift(followingEvent.EventName) : null
                }
            }
        }
    }

    private function executeEnemy(){
        if(this.enemy == null) return;
        var emenyinfoList:Array = StageInfo.parseEnemyGroup(this.enemy);
        for(var i=0; i< emenyinfoList.length; i++){
            var emenyinfo = emenyinfoList[i];
            var id = emenyinfo.Attribute.兵种名;
            var para = ObjectUtil.clone(emenyinfo.Attribute);
            if(emenyinfo.Level > 0) para.等级 = emenyinfo.Level;
            para.兵种名 = null;
            para.产生源 = "无";
            if(emenyinfo.Parameters){
                ObjectUtil.cloneParameters(para, emenyinfo.Parameters);
            }
            var instanceName = emenyinfo.InstanceName ? emenyinfo.InstanceName : id + "_event_" + eventName + "_" + i;
            WaveSpawner.instance.spawnEnemy(id, instanceName, para, emenyinfo.SpawnIndex, emenyinfo.x, emenyinfo.y);
        }
    }

    public function clear(){
        parameters = null;

        animation = null;
        bgm = null;
        callback = null;
        camera = null;
        dialogue = null;
        enemy = null;
        stageprogress = null;
        performance = null;
        sound = null;

        isDestroyed = true;
    }

}