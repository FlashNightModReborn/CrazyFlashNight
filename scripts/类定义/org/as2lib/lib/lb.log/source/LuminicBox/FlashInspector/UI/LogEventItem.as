class LuminicBox.FlashInspector.UI.LogEventItem extends LuminicBox.FlashInspector.UI.LogInspectionItem {
	
	private var txtLevel:TextField;
	
	private function init():Void {
		
		super.init();
		
		txtLevel.textColor = getLevelColors()[dataItem.level.getName()];
		txtLevel.text = dataItem.level.getName();
		
		showBg = (itemPosition%2==0);
	
	}
	
	private function getObj():Object {
		return dataItem.argument;
	}
	
	static function getLevelColors():Object {
		var a:Object = new Object();
		a["LOG"] = 0x999999;
		a["DEBUG"] = 0x0066CC;
		a["INFO"] = 0x009999;
		a["WARN"] = 0xFF9900;
		a["ERROR"] = 0xFF6600
		a["FATAL"] = 0xFF0000;
		return a;
	}
	
}

/*
 * Tue Apr 26 01:10:26 2005
 * 	showBg called within init() method
 */