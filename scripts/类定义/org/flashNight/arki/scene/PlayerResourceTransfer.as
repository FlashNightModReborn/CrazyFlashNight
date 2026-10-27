import org.flashNight.arki.unit.Action.Regeneration.ResourceNumber;

/** 一个清场票据的一次性内存事务。样本/预期身份均私有，不接受外部修改的 payload。 */
class org.flashNight.arki.scene.PlayerResourceTransfer {
    private var state:String;
    private var source:Object;
    private var sample:Object;
    private var destination:Object;
    private var handle:Object;
    private var lastTicket:Object;
    public var reason:String;
    public var diagnostic:String;
    public function PlayerResourceTransfer() {state="empty";reason="";diagnostic="";}
    public function status():String {return state;}
    public function sourceRun():Object {return source.run;}
    public function sourceContext():Object {return source.context;}
    private function fail(code:String):Boolean {reason=code;state="failed";sample=null;return false;}
    public function retire(code:String):Void {
        state="retired";reason=code;source=null;sample=null;destination=null;handle=null;
    }
    private static function identity(i:Object):Boolean {
        return i!=null && i.context!=null && i.run!=null && i.world!=null && i.actor!=null
            && typeof i.slot=="string" && i.slot!="" && typeof i.name=="string" && i.name!=""
            && (i.kind=="player" || i.kind=="lee") && ResourceNumber.nonnegative(i.stage)
            && Math.floor(i.stage)==i.stage;
    }
    private static function pair(v:Object,kind:String):Boolean {
        return ResourceNumber.positive(v.hp) && ResourceNumber.nonnegative(v.mp)
            && ResourceNumber.positive(v.hpMax)
            && (ResourceNumber.positive(v.mpMax) || (kind=="lee" && v.mpMax===0 && v.mp===0));
    }
    /** 仅在 admission/loot/preflight 全部通过之后调用；仍未发布为可消费状态。 */
    public function capture(ticket:Object,i:Object,v:Object,targetStage:Number):Boolean {
        if(state=="captured" || state=="committed" || state=="bound") {reason="transfer_busy";return false;}
        if(ticket!=null && ticket===lastTicket) {reason="terminal_ticket_reuse";return false;}
        lastTicket=ticket;
        if(ticket==null || !identity(i) || !ResourceNumber.nonnegative(targetStage)
                || targetStage!==i.stage+1) return fail("capture_identity_invalid");
        if(!pair(v,i.kind)) return fail("capture_resources_invalid");
        source={ticket:ticket,context:i.context,run:i.run,world:i.world,actor:i.actor,
            slot:i.slot,name:i.name,kind:i.kind,stage:i.stage,targetStage:targetStage,frame:ticket.frame};
        sample={hp:v.hp,mp:v.mp,hpMax:v.hpMax,mpMax:v.mpMax};
        destination=null;handle=null;reason="";diagnostic="";state="captured";return true;
    }
    /** 只有持有原清场票据的成功销毁路径能提交。 */
    public function commit(ticket:Object):Boolean {
        if(state!="captured" || source.ticket!==ticket || source.frame!==ticket.frame) return false;
        state="committed";return true;
    }
    public function abort(ticket:Object,code:String):Boolean {
        if(source.ticket!==ticket || state!="captured") return false;
        retire(code);return true;
    }
    public function bind(i:Object):Object {
        if(state!="committed") {reason="not_committed";return null;}
        if(!identity(i) || i.context!==source.context || i.run!==source.run || i.world===source.world
                || i.actor===source.actor || i.slot!==source.slot || i.name!==source.name
                || i.kind!==source.kind || i.stage!==source.targetStage) {fail("destination_mismatch");return null;}
        destination={context:i.context,run:i.run,world:i.world,actor:i.actor,slot:i.slot,name:i.name,kind:i.kind,stage:i.stage};
        handle={};state="bound";return handle;
    }
    private function matches(i:Object):Boolean {
        return identity(i) && i.context===destination.context && i.run===destination.run
            && i.world===destination.world && i.actor===destination.actor && i.slot===destination.slot
            && i.name===destination.name && i.kind===destination.kind && i.stage===destination.stage;
    }
    /** 相同/提高上限不补资源；降低普通上限夹取；旧溢出仅服从显式有效 cap。 */
    public static function project(value:Number,oldMax:Number,newMax:Number,cap):Number {
        if(!(newMax < oldMax)) return value;
        if(!(value > oldMax)) return Math.min(value,newMax);
        if(ResourceNumber.positive(cap) && !(cap < newMax)) return Math.min(value,cap);
        return value;
    }
    public function consume(token:Object,target:Object,i:Object,caps:Object):Boolean {
        if(state!="bound" || token!==handle) {reason="consume_token_mismatch";return false;}
        if(!matches(i) || target.__playerSceneActorIdentity!==destination.actor) return fail("consume_identity_invalid");
        var actual:Object={hp:target.hp,mp:target.mp,hpMax:target.hp满血值,mpMax:target.mp满血值};
        if(!pair(sample,source.kind) || !pair(actual,source.kind)) return fail("consume_resources_invalid");
        var hp:Number=project(sample.hp,sample.hpMax,actual.hpMax,caps.hp);
        var mp:Number=project(sample.mp,sample.mpMax,actual.mpMax,caps.mp);
        if(!ResourceNumber.positive(hp) || !ResourceNumber.nonnegative(mp)) return fail("project_resources_invalid");
        if((actual.hpMax < sample.hpMax && sample.hp > sample.hpMax && !(ResourceNumber.positive(caps.hp) && !(caps.hp < actual.hpMax)))
                || (actual.mpMax < sample.mpMax && sample.mp > sample.mpMax && !(ResourceNumber.positive(caps.mp) && !(caps.mp < actual.mpMax))))
            diagnostic="overflow_without_explicit_cap_preserved";
        // 先计算并检查两项；两次赋值之间无通知、刷新或用户回调。
        target.hp=hp;target.mp=mp;state="consumed";sample=null;reason="";return true;
    }
}
