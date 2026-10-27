import org.flashNight.arki.skill.SkillFeatureRegistry;

/** 子能力偏好属于角色扩展存档；战斗只读父技能及预投影的布尔缓存。 */
class org.flashNight.arki.skill.SkillFeaturePolicy {
    public static function validId(value):Boolean {
        if (typeof value!="string" || length(value)<3 || length(value)>64) return false;
        var start:Boolean=true;var dots:Number=0;
        for(var i:Number=0;i<length(value);i++) {
            var c:Number=value.charCodeAt(i);
            if(c==46) {if(start)return false;start=true;dots++;}
            else if(start) {if(c<97||c>122)return false;start=false;}
            else if(!((c>=97&&c<=122)||(c>=48&&c<=57)||c==95))return false;
        }
        return dots>0&&!start;
    }
    public static function readState(r:Object):Object {
        var ext:Object=r._saveExt;
        if(typeof ext=="undefined")return {valid:true,disabled:{}};
        if(ext==null||typeof ext!="object"||ext instanceof Array)return {valid:false,disabled:{}};
        var s:Object=ext.skillFeatures;
        if(typeof s=="undefined")return {valid:true,disabled:{}};
        if(s==null||typeof s!="object"||s instanceof Array||typeof s.v!="number"||s.v!=1)
            return {valid:false,disabled:{}};
        var keys:Number=0;var key:String;
        for(key in s)if(s.hasOwnProperty(key)) {keys++;if(key!="v"&&key!="disabledIds")return {valid:false,disabled:{}};}
        var ids:Object=s.disabledIds;
        if(keys!=2||ids==null||typeof ids!="object"||ids instanceof Array)return {valid:false,disabled:{}};
        keys=0;
        for(key in ids)if(ids.hasOwnProperty(key)) {
            if(++keys>128||!validId(key)||ids[key]!==true)return {valid:false,disabled:{}};
        }
        return {valid:true,disabled:ids};
    }
    public static function signature(r:Object):String {
        var s:Object=readState(r);
        if(!s.valid)return "invalid:"+typeof r._saveExt.skillFeatures+":"+String(r._saveExt.skillFeatures.v);
        var keys:Array=[];
        for(var key:String in s.disabled)if(s.disabled.hasOwnProperty(key))keys.push(key);
        keys.sort();return "v1:"+keys.join(",");
    }
    /** 返回新命名空间；null 表示移除最后一项，undefined 表示拒绝（含容量上限）。旧对象与未知合法 ID 保留。 */
    public static function withChoice(r:Object,id:String,enabled:Boolean):Object {
        var s:Object=readState(r);
        if(!s.valid||!validId(id)||typeof enabled!="boolean")return undefined;
        var ids:Object={};var n:Number=0;
        for(var key:String in s.disabled)if(s.disabled.hasOwnProperty(key)&&key!=id) {ids[key]=true;n++;}
        if(!enabled){ids[id]=true;n++;}
        if(n>128)return undefined;
        return n==0?null:{v:1,disabledIds:ids};
    }
    public static function meetsLevel(level:Number,required:Number):Boolean {
        return isFinite(level)&&Math.floor(level)==level&&level>=required&&required>=1&&required<=100;
    }
    public static function project(r:Object):Void {
        var s:Object=readState(r);var list:Array=SkillFeatureRegistry.all();
        for(var i:Number=0;i<list.length;i++) {
            var d:Object=list[i];var parent:Object=r.主角被动技能[d.skillKey];
            if(parent==undefined)continue;
            if(parent.__featurePrefs==undefined)parent.__featurePrefs={};
            parent.__featurePrefs[d.id]=!s.valid||s.disabled[d.id]!==true;
        }
    }
    public static function isEnabled(unit:Object,id:String):Boolean {
        var d:Object=SkillFeatureRegistry.get(id);
        if(d==undefined)return false;
        var parent:Object=unit.被动技能[d.skillKey];
        if(!parent.启用)return false;
        var level:Number=typeof parent.等级=="undefined"?1:Number(parent.等级);
        return meetsLevel(level,d.minLevel)&&parent.__featurePrefs[id]!==false;
    }
}
