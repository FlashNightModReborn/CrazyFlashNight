/** 原作链锤声音的玩家动作映射。只响应已经推进的动作帧，不改变伤害时序。 */
class org.flashNight.arki.unit.Action.Huofeng.HuofengAudio {
    public static function frame(unit:MovieClip,action:Object):Void {
        if(action.recovery>0) return;
        var f:Number=action.frame;
        var cue:String;
        if(action.kind==="normal") {
            if(f==8 || f==45) cue="火凤_挥锤1.wav";
            else if(f==17 || f==55) cue="火凤_挥锤2.wav";
            else if(f==31 || f==66) cue="火凤_挥锤3.wav";
            if(cue!=undefined) _root.播放音效("火凤_链条.wav",unit);
        } else if(action.kind==="run") {
            if(f==12) cue="火凤_回旋.wav";
        } else if(action.kind==="spin") {
            if(f==16 || f==48 || f==80) cue="火凤_回旋.wav";
        }
        if(cue!=undefined) _root.播放音效(cue,unit);
    }
}
