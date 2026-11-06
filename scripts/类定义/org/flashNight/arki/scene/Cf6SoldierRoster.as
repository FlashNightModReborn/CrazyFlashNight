import org.flashNight.gesh.object.ObjectUtil;

/** Fixed personnel use authored instance ordinals, independent of display names and retries. */
class org.flashNight.arki.scene.Cf6SoldierRoster {
    private static function whole(value,low:Number,high:Number):Boolean {
        return typeof value=="number" && isFinite(value) && Math.floor(value)==value && value>=low && value<=high;
    }
    private static function text(value):Boolean {
        return typeof value=="string" && length(value)>0 && length(value)<129;
    }
    public static function prepare(source:Object,ordinal:Number,initial:Object):Object {
        var slots:Array=source.Parameters.cf6FixedSlots;
        if(!(slots instanceof Array) || !whole(source.Quantity,1,6) || slots.length!=source.Quantity
            || !whole(ordinal,0,slots.length-1))throw new Error("CF6 fixed spawn has no exact instance ordinal");
        var slot:Object=slots[ordinal],parameters:Object=slot.parameters;
        if(slot.ordinal!==ordinal || !text(parameters.cf6UnitIdentity) || !text(parameters.cf6SourceSeat)
            || !text(parameters.cf6RosterVersion) || parameters.cf6RosterVersion!==source.Parameters.cf6RosterVersion
            || !text(parameters.cf6ProfileId) || !whole(parameters.cf6SourceOrdinal,0,5)
            || !whole(parameters.特种兵初始阶段,1,2) || parameters.不掉装备!==true
            || typeof slot.x!="number" || !isFinite(slot.x) || typeof slot.y!="number" || !isFinite(slot.y))
            throw new Error("CF6 fixed spawn identity or geometry is invalid");
        if(parameters.cf6G1111FixedMode!==undefined){
            if(typeof parameters.cf6G1111FixedMode!="boolean" || parameters.长枪.name!=="G1111"
                || typeof parameters.长枪.value.isRocketMode!="boolean"
                || parameters.长枪.value.isRocketMode!==parameters.cf6G1111FixedMode)
                throw new Error("CF6 G1111 requires an independent Boolean mode instance");
        }
        ObjectUtil.cloneParameters(initial,parameters);
        delete initial.cf6FixedSlots;
        delete initial.cf6EliteQuota;
        initial.cf6BirthIdentity={};
        initial.cf6BirthX=slot.x;initial.cf6BirthZ=slot.y;
        return slot;
    }
}
