import org.flashNight.gesh.object.ObjectUtil;

// Functional mod lifecycles compose alongside equipment; they do not claim a skill slot.
class org.flashNight.arki.item.equipment.EquipmentLifecyclePolicy {
    public static function isIndependentLifecycle(value:Object):Boolean {
        if (value == undefined) return false;
        if (typeof value != "object" || value instanceof Array) return false;
        var found:Boolean = false;
        for (var key:String in value) {
            if (!value.hasOwnProperty(key)) continue;
            if (key.indexOf("attr") == -1) return false;
            var attr:Object = value[key];
            if (typeof attr != "object" || attr == null || attr instanceof Array
                || attr.skillInteraction !== "independent" || attr.skill != undefined || attr.setGate != undefined) return false;
            if (attr.init == undefined && attr.cycle == undefined) return false;
            if (attr.init != undefined && (typeof attr.init != "object" || attr.init instanceof Array
                || typeof attr.init.initRoutines != "string" || length(attr.init.initRoutines) == 0)) return false;
            if (attr.cycle != undefined && (typeof attr.cycle != "object" || attr.cycle instanceof Array
                || typeof attr.cycle.cycleRoutines != "string" || length(attr.cycle.cycleRoutines) == 0)) return false;
            found = true;
        }
        return found;
    }

    public static function merge(base:Object, mods:Array, registry:Object):Object {
        var result:Object = {};
        var count:Number = 0;
        var key:String;
        if (base != undefined) {
            for (key in base) {
                if (!base.hasOwnProperty(key)) continue;
                // Only our own previous projections are replaced; authored attrs survive.
                if (base[key].__modName != undefined) continue;
                result[key] = ObjectUtil.clone(base[key]);
                count++;
            }
        }
        var seen:Object = {};
        seen.__proto__ = null;
        for (var i:Number = 0; i < mods.length; i++) {
            var name:String = String(mods[i]);
            if (seen[name] === true) continue;
            seen[name] = true;
            var lifecycle:Object = registry[name].lifecycle;
            if (lifecycle == undefined || !isIndependentLifecycle(lifecycle)) continue;
            for (key in lifecycle) {
                if (!lifecycle.hasOwnProperty(key)) continue;
                // Length-prefixes give stable keys across reorder without name collisions.
                var destination:String = "attr_mod_" + length(name) + "_" + name + "_" + length(key) + "_" + key;
                while (result.hasOwnProperty(destination)) destination += "_";
                var attr:Object = ObjectUtil.clone(lifecycle[key]);
                attr.__modName = name;
                result[destination] = attr;
                count++;
            }
        }
        return count > 0 ? result : undefined;
    }
}
