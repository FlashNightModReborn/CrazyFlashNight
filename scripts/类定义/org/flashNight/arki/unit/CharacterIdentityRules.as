/** 建角与整形共用的身份字段规则；价格、存档和角色生命周期归调用领域。 */
class org.flashNight.arki.unit.CharacterIdentityRules {
    public static function validate(profile:Object):String {
        if (profile == null || typeof profile.characterName != "string"
                || profile.characterName.length < 1 || profile.characterName.length > 15) {
            return "invalid_character_name";
        }
        var visible:Boolean = false;
        for (var i:Number = 0; i < profile.characterName.length; i++) {
            var code:Number = profile.characterName.charCodeAt(i);
            if (code < 32 || (code >= 127 && code <= 159)) return "invalid_character_name";
            if (code != 32 && code != 12288) visible = true;
        }
        if (!visible) return "invalid_character_name";
        if (profile.gender !== "male" && profile.gender !== "female") return "invalid_gender";
        if (typeof profile.height != "number" || isNaN(profile.height)
                || Math.floor(profile.height) != profile.height
                || profile.height < 150 || profile.height > 200) return "invalid_height";
        return "";
    }

    public static function copy(profile:Object):Object {
        return {characterName:String(profile.characterName), gender:String(profile.gender), height:Number(profile.height)};
    }

    public static function same(a:Object, b:Object):Boolean {
        return a != null && b != null && a.characterName === b.characterName
            && a.gender === b.gender && a.height === b.height;
    }
}
