/** 同一个宠物槽的犬种选择；宠物 ID、成长与自定义名称仍归原存档槽。 */
class org.flashNight.arki.merc.DogFormService {
    public static function isForm(form:String):Boolean {
        return form == "zombie" || form == "thief" || form == "military";
    }
    public static function isDogSlot(info:Array):Boolean {
        return info != null && info.length > 4 && Number(info[0]) == 0;
    }
    public static function form(info:Array):String {
        var selected:String = String(info[5].dogForm);
        return isForm(selected) ? selected : "zombie";
    }
    public static function identifier(info:Array, fallback:String):String {
        if (!isDogSlot(info)) return fallback;
        var selected:String = form(info);
        if (selected == "thief") return "敌人-盗贼撕咬犬";
        if (selected == "military") return "敌人-制式军警犬";
        return "敌人-僵尸1-狗";
    }
    public static function name(info:Array, fallback:String):String {
        if (!isDogSlot(info)) return fallback;
        var selected:String = form(info);
        return selected == "thief" ? "盗贼犬" : (selected == "military" ? "军警犬" : "僵尸犬");
    }
    public static function options():Array {
        return [
            {value:"zombie", label:"僵尸犬", description:"咬中后90帧内目标死亡，回复15%最大生命"},
            {value:"thief", label:"盗贼犬", description:"自动拾取普通掉落物，敌方同类会偷取掉落"},
            {value:"military", label:"军警犬", description:"韧性系数3，较难被打断；仍正常承受伤害"}
        ];
    }
    public static function change(slot:Number, selected:String):Object {
        if (!isFinite(slot) || Math.floor(slot) != slot || slot < 0 || slot >= _root.宠物信息.length)
            return {success:false,error:"invalid_slot"};
        var info:Array = _root.宠物信息[slot];
        if (!isDogSlot(info)) return {success:false,error:"not_dog_pet"};
        if (!isForm(selected)) return {success:false,error:"invalid_dog_form"};
        if (_root.当前为战斗地图 !== false) return {success:false,error:"cannot_change_form_here"};
        if (form(info) == selected) return {success:true,slotIndex:slot,dogForm:selected,unchanged:true};
        var previousAttrs:Object = info[5];
        var attrs:Object = previousAttrs;
        if (attrs == null || typeof attrs != "object") attrs = {};
        var hadForm:Boolean = attrs.hasOwnProperty("dogForm");
        var previousForm:Object = attrs.dogForm;
        _root.存档系统.dirtyMark = true;
        info[5] = attrs;
        attrs.dogForm = selected;
        var rebuilt:Boolean = true;
        var deferred:Boolean = false;
        if (info[4] == 1) {
            try {
                rebuilt = typeof _root.战宠UI函数.重建宠物单位 == "function"
                    && _root.战宠UI函数.重建宠物单位(slot,false,null) === true;
            } catch (rebuildError) {
                // 运行态通知异常不反转已提交的形态；下一次场景加载重建权威投影。
                deferred = true;
                trace("[DogForm] rebuild deferred: " + rebuildError);
            }
        }
        if (!rebuilt && !deferred) {
            if (hadForm) attrs.dogForm = previousForm; else delete attrs.dogForm;
            info[5] = previousAttrs;
            return {success:false,error:"dog_form_rebuild_failed"};
        }
        return {success:true,slotIndex:slot,dogForm:selected,refreshDeferred:deferred};
    }
}
