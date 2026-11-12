// Parse and link the visual catalog once. Consumers only read the installed maps.
class org.flashNight.arki.render.LightRegistry {
    public static var error:String = "";

    private static function dictionary():Object {
        var values:Object = {};
        values.__proto__ = null;
        return values;
    }
    public static function empty():Object {
        return {projectile:dictionary(), effect:dictionary(), pulse:dictionary(), area:dictionary(), count:0};
    }
    private static function invalid(message:String):Object {
        error = message;
        return null;
    }
    private static function keyValid(key:String):Boolean {
        if (key == undefined || key.length < 1 || key.length > 128 || key == "__proto__" || key == "__resolve") return false;
        if (key.charCodeAt(0) <= 32 || key.charCodeAt(key.length - 1) <= 32) return false;
        for (var i:Number = 0; i < key.length; i++) if (key.charCodeAt(i) < 32) return false;
        return true;
    }
    private static function value(attrs:Object, key:String, low:Number, high:Number, fallback:Number):Number {
        var raw:String = attrs[key];
        if (raw == undefined) return fallback;
        var n:Number = Number(raw);
        return raw.length && isFinite(n) && n >= low && n <= high ? n : Number.NaN;
    }
    private static function known(attrs:Object, fields:String):Boolean {
        for (var key:String in attrs) if (fields.indexOf("|" + key + "|") < 0) return false;
        return true;
    }
    private static function profile(attrs:Object):Object {
        if (!known(attrs, "|id|radius|energy|color|forwardOffset|offsetY|totalFrames|isExplosion|stageFrame|stageRadius|stageEnergy|stageOffsetY|")) return null;
        var rgb:String = attrs.color;
        if (rgb.length != 7 || rgb.charAt(0) != "#") return null;
        for (var i:Number = 1; i < 7; i++) if ("0123456789abcdefABCDEF".indexOf(rgb.charAt(i)) < 0) return null;
        var col:Number = parseInt(rgb.substr(1), 16);
        var p:Object = {radius:value(attrs,"radius",1,320,Number.NaN), energy:value(attrs,"energy",0.001,2,Number.NaN),
            r:0.2 + (((col >> 16) & 255) / 255) * 0.8, g:0.2 + (((col >> 8) & 255) / 255) * 0.8,
            b:0.2 + ((col & 255) / 255) * 0.8, forwardOffset:value(attrs,"forwardOffset",-1000000,1000000,0),
            offsetY:value(attrs,"offsetY",-1000000,1000000,0), totalFrames:value(attrs,"totalFrames",1,65535,Number.NaN),
            isExplosion:attrs.isExplosion == "true", stageFrame:0, stageRadius:0, stageEnergy:0, stageOffsetY:0};
        if (!isFinite(p.radius + p.energy + p.forwardOffset + p.offsetY + p.totalFrames) ||
            p.totalFrames != Math.floor(p.totalFrames) || (attrs.isExplosion != "true" && attrs.isExplosion != "false")) return null;
        if (attrs.stageFrame != undefined || attrs.stageRadius != undefined || attrs.stageEnergy != undefined || attrs.stageOffsetY != undefined) {
            p.stageFrame = value(attrs,"stageFrame",1,p.totalFrames,Number.NaN);
            p.stageRadius = value(attrs,"stageRadius",1,320,Number.NaN);
            p.stageEnergy = value(attrs,"stageEnergy",0.001,2,Number.NaN);
            p.stageOffsetY = value(attrs,"stageOffsetY",-1000000,1000000,Number.NaN);
            if (!isFinite(p.stageFrame + p.stageRadius + p.stageEnergy + p.stageOffsetY) || p.stageFrame != Math.floor(p.stageFrame)) return null;
        }
        return p;
    }
    private static function link(result:Object, profiles:Object, a:Object):Boolean {
        var kind:String = a.kind, key:String = a.key;
        if (!keyValid(key) || !keyValid(a.profile)) return false;
        var spec:Object = profiles[a.profile];
        if (typeof spec != "object") return false;
        var fields:String = "|kind|key|profile|";
        var record:Object = {key:key, spec:spec};
        if (kind == "area" && a.auxProfile != undefined) {
            fields += "auxProfile|minSpan|nearFraction|farFraction|widthScale|referenceRadius|maxRadius|energyScale|maxEnergy|auxEnergyScale|";
            if (!keyValid(a.auxProfile) || typeof profiles[a.auxProfile] != "object") return false;
            record.aux = profiles[a.auxProfile];
            record.minSpan = value(a,"minSpan",1,1000000,180);
            record.nearFraction = value(a,"nearFraction",0,1,0.28);
            record.farFraction = value(a,"farFraction",0,1,0.74);
            record.widthScale = value(a,"widthScale",0,4,0.65);
            record.referenceRadius = value(a,"referenceRadius",1,320,spec.radius);
            record.maxRadius = value(a,"maxRadius",1,320,320);
            record.energyScale = value(a,"energyScale",0.001,8,1);
            record.maxEnergy = value(a,"maxEnergy",0.001,2,2);
            record.auxEnergyScale = value(a,"auxEnergyScale",0.001,4,1);
            if (!isFinite(record.minSpan + record.nearFraction + record.farFraction + record.widthScale + record.referenceRadius
                + record.maxRadius + record.energyScale + record.maxEnergy + record.auxEnergyScale)
                || record.nearFraction >= record.farFraction) return false;
        }
        if (!known(a,fields)) return false;
        if (kind == "asset") {
            if (typeof result.projectile[key] != "undefined" || typeof result.effect[key] != "undefined") return false;
            result.projectile[key] = result.effect[key] = record;
        } else {
            if (kind != "area" && kind != "pulse" && kind != "projectile" && kind != "effect") return false;
            if (typeof result[kind][key] != "undefined") return false;
            result[kind][key] = record;
        }
        return true;
    }
    public static function parse(doc:XML):Object {
        error = "";
        var root:XMLNode = doc.firstChild;
        if (doc.status != 0 || root.nodeName != "LightProfiles" || root.attributes.version != "1" ||
            root.nextSibling != null || !known(root.attributes,"|version|")) return invalid("LightProfiles version");
        var defs:XMLNode, bindings:XMLNode, n:XMLNode;
        for (n = root.firstChild; n != null; n = n.nextSibling) {
            if (n.nodeName == "Profiles" && defs == null) defs = n;
            else if (n.nodeName == "Bindings" && bindings == null) bindings = n;
            else return invalid("unexpected section " + n.nodeName);
        }
        if (defs == null || bindings == null || !known(defs.attributes,"") || !known(bindings.attributes,"")) return invalid("Profiles / Bindings");
        var profiles:Object = dictionary(), result:Object = empty();
        for (n = defs.firstChild; n != null; n = n.nextSibling) {
            var id:String = n.attributes.id;
            if (n.nodeName != "Profile" || n.firstChild != null || !keyValid(id) || typeof profiles[id] != "undefined") return invalid("Profile " + id);
            var p:Object = profile(n.attributes);
            if (p == null) return invalid("Profile " + id);
            profiles[id] = p; result.count++;
        }
        for (n = bindings.firstChild; n != null; n = n.nextSibling) {
            if (n.nodeName != "Binding" || n.firstChild != null || !link(result, profiles, n.attributes)) return invalid("Binding " + n.attributes.key);
        }
        return result;
    }
}
