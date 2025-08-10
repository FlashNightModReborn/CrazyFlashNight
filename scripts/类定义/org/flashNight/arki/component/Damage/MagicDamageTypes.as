class org.flashNight.arki.component.Damage.MagicDamageTypes {
	
	private static var magicDamageTypesHash:Object = {
		电: true,
		热: true,
		冷: true,
		波: true,
		蚀: true,
		毒: true,
		冲: true,
		基础: true 
	};
	
	public static function isMagicDamageType(damageType:String):Boolean {
        // _root.发布消息(damageType, magicDamageTypesHash[damageType]);
		return magicDamageTypesHash[damageType] == true;
	}
	
	public static function getMagicDamageTypesArray():Array {
		var result:Array = [];
		for (var key:String in magicDamageTypesHash) {
			result.push(key);
		}
		return result;
	}
	
	public static function getMagicDamageTypes():Array {
		return getMagicDamageTypesArray();
	}
} 
