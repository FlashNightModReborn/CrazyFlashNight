/** AVM1 的 Number 注解不做运行时转换；资源写入只接受原始有限 number。 */
class org.flashNight.arki.unit.Action.Regeneration.ResourceNumber {
    public static function finite(value):Boolean {
        return typeof value == "number" && isFinite(value) && !isNaN(value);
    }
    public static function nonnegative(value):Boolean {return finite(value) && !(value < 0);}
    public static function positive(value):Boolean {return finite(value) && value > 0;}
    /** 一次故障只记录首个写入边界，不以满值覆盖污染输入。 */
    public static function reject(target:Object, boundary:String):Boolean {
        if(target!=null && target.__resourceFirstFault==undefined) {
            target.__resourceFirstFault=boundary;
            var line:String="[ResourceFault] boundary="+boundary+" actor="+target._name;
            trace(line);
            if(typeof _root.服务器.发布服务器消息=="function") _root.服务器.发布服务器消息(line);
        }
        return false;
    }
    public static function payMp(target:Object,cost):Boolean {
        if(!canPayMp(target,cost) || target.mp < cost) return false;
        target.mp-=cost;return true;
    }
    public static function canPayMp(target:Object,cost):Boolean {
        if(!nonnegative(cost)) return reject(target,"cost_invalid");
        if(!finite(target.hp) || !nonnegative(target.mp)) return reject(target,"resource_invalid");
        return target.hp > 0;
    }
}
