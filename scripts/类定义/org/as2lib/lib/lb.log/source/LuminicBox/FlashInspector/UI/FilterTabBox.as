import LuminicBox.UI.*;
import LuminicBox.Log.Level;

class LuminicBox.FlashInspector.UI.FilterTabBox extends BaseComponent {
	
	private var _tabRepeater:Repeater;
	
	public function FilterTabBox() {
		super();
		// tabs
		var tabData:Array = new Array();
		var o:Object;
		o = new Object();
		o.level = Level.LOG;
		o.color = 0xDEDFE0;
		tabData.push(o);
		o = new Object();
		o.level = Level.DEBUG;
		o.color = 0x1394D6;
		tabData.push(o);
		o = new Object();
		o.level = Level.INFO;
		o.color = 0x12C9AC;
		tabData.push(o);
		o = new Object();
		o.level = Level.WARN;
		o.color = 0xFFCC00;
		tabData.push(o);
		o = new Object();
		o.level = Level.ERROR;
		o.color = 0xFF6600;
		tabData.push(o);
		o = new Object();
		o.level = Level.FATAL;
		o.color = 0xFF0000;
		tabData.push(o);
		// repeater
		_tabRepeater = Repeater(this.attachMovie("Repeater","tabRepeater",1));
		_tabRepeater.itemTemplate = "FilterTabItem";
		_tabRepeater.separatorTemplate = "FilterTabItem_spacer";
		_tabRepeater.direction = "horizontal";
		_tabRepeater.addEventListener("itemselected", this, "tab_onSelection");
		_tabRepeater.databind(tabData);
	}
	
	public function setFilter(level:Level):Boolean {
		var items:Array = _tabRepeater.items;
		for(var i:Number=0; i<items.length; i++) {
			if(items[i].dataItem.level == level) {
				_tabRepeater.selectedItem = items[i];
				return true;
			}
		}
		return false;
	}
	
	public function getFilter():Level {
		return _tabRepeater.selectedItem.dataItem.level;
	}
	
	private function tab_onSelection(e) {
		dispatchEvent( {type:"changeFilter",level:e.item.dataItem.level,color:e.item.dataItem.color} );
	}
	
	
	
}