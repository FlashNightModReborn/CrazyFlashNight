// Connection-local format choice. Gameplay and native ownership remain in their existing services.
class org.flashNight.arki.render.VisualWireService {
    private static var pending:Object = null;
    private static var committed:Boolean = false;
    private static var parser:FastJSON;
    private static var senderForTests:Function;
    public static function retire():Void { pending = null; committed = false; }
    public static function f5OfferId():Number { return committed && pending.f5 == "q1" ? pending.offerId : 0; }
    public static function handle(message:Object):Void {
        if (message.task == "visual_wire_offer") {
            if (!keys(message,["task","version","token","offerId","channels","f5Quant"])
                || message.version !== 1 || !token(message.token) || !integer(message.offerId)
                || !keys(message.channels,["f5","scenePose"])
                || !(message.channels.f5 instanceof Array) || !(message.channels.scenePose instanceof Array)
                || !quantOffer(message.f5Quant)) return;
            if (pending != null) {
                if (pending.token === message.token && pending.offerId === message.offerId) sendSelection();
                return;
            }
            var f5:String = contains(message.channels.f5,"q1") ? "q1"
                : contains(message.channels.f5,"legacy") ? "legacy" : "";
            if (f5 == "" || !contains(message.channels.scenePose,"legacy")) return;
            pending = {token:message.token,offerId:message.offerId,f5:f5};
            sendSelection();
            return;
        }
        if (message.task == "visual_wire_commit") {
            if (pending == null || !keys(message,["task","version","token","offerId","channels","f5QuantProfile","qAllowed"])
                || message.version !== 1 || message.token !== pending.token || message.offerId !== pending.offerId
                || !keys(message.channels,["f5","scenePose"]) || message.channels.f5 !== pending.f5
                || message.channels.scenePose !== "legacy" || message.f5QuantProfile !== "none" || message.qAllowed !== false) return;
            if (committed) return;
            committed = true;
            if (pending.f5 == "q1") org.flashNight.arki.render.BulletVisualProbe.activateQ1();
        }
    }
    private static function sendSelection():Void {
        if (parser == null) parser = new FastJSON();
        var message:Object = {task:"visual_wire_select",version:1,token:pending.token,offerId:pending.offerId,
            channels:{f5:pending.f5,scenePose:"legacy"},f5QuantProfile:"none"};
        var wire:String = parser.stringify(message);
        if (senderForTests != null) senderForTests(wire);
        else _root.server.sendSocketMessage(wire);
    }
    private static function contains(values:Array, value:String):Boolean {
        if (values.length < 1 || values.length > 16) return false;
        var found:Boolean = false;
        for (var i:Number=0;i<values.length;i++) {
            if (typeof values[i] != "string" || length(values[i]) > 64) return false;
            if (values[i] === value) found=true;
        }
        return found;
    }
    private static function quantOffer(value:Object):Boolean {
        var fields:Array=["profile","allowed","denominator","absXY","maxCameraScale","maxCameraOffset",
            "maxAbsScalePercent","maxCatalogRadius","maxOutputScale"];
        if(!keys(value,fields) || typeof value.profile!="string" || value.profile.length<1 || value.profile.length>64
            || typeof value.allowed!="boolean")return false;
        for(var i:Number=2;i<fields.length;i++) {
            var number:Number=value[fields[i]];
            if(typeof value[fields[i]]!="number" || !isFinite(number) || number<=0 || number>1000000)return false;
        }
        // Unknown profiles can still select raw R; this candidate always requests quantProfile=none.
        return value.profile!="q64-safe-v1" || (value.denominator===64 && value.absXY===8192
            && value.maxCameraScale===4 && value.maxCameraOffset===8192 && value.maxAbsScalePercent===400
            && value.maxCatalogRadius===128 && value.maxOutputScale===4);
    }
    private static function integer(value):Boolean {
        return typeof value == "number" && isFinite(value) && value >= 1 && value <= 2147483647 && Math.floor(value) == value;
    }
    private static function token(value):Boolean {
        if (typeof value != "string" || length(value) != 32) return false;
        for (var i:Number=0;i<32;i++) {
            var c:Number=value.charCodeAt(i);
            if (!((c>=48 && c<=57) || (c>=97 && c<=102))) return false;
        }
        return true;
    }
    private static function keys(value:Object, names:Array):Boolean {
        if (value == null || value instanceof Array || typeof value.hasOwnProperty != "function") return false;
        var count:Number=0;
        for (var key:String in value) {
            if (!value.hasOwnProperty(key)) continue;
            var known:Boolean=false;
            for (var i:Number=0;i<names.length;i++) if (key === names[i]) {known=true;break;}
            if (!known) return false;
            count++;
        }
        if (count != names.length) return false;
        for (var n:Number=0;n<names.length;n++) if (!value.hasOwnProperty(names[n])) return false;
        return true;
    }
    public static function setSenderForTests(sender:Function):Void { senderForTests=sender; }
}
