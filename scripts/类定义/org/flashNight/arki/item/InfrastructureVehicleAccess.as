/** Vehicle ownership accepts supported primitive save values; never coerces objects or repairs saves. */
class org.flashNight.arki.item.InfrastructureVehicleAccess {
    public static function owned(infrastructure:Object, key:String):Boolean {
        if (typeof infrastructure != "object" || typeof infrastructure.hasOwnProperty != "function"
                || !infrastructure.hasOwnProperty(key)) return false;
        var value = infrastructure[key];
        var kind:String = typeof value;
        if (kind != "number" && kind != "string" && kind != "boolean") return false;
        var level:Number = Number(value);
        return !isNaN(level) && isFinite(level) && level >= 1
            && level <= 9007199254740991 && Math.floor(level) == level;
    }
}
