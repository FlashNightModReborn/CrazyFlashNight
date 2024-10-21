import LuminicBox.UI.Repeater;

class LuminicBox.FlashInspector.UI.MainTabBox extends LuminicBox.UI.BaseComponent {
		
	private var _itemLabels:Array;
	
	private var dummy:MovieClip;
	private var tabRepeater:Repeater;

	[Inspectable(type="Array")]
	public function set itemLabels(value:Array) {
		_itemLabels = value;
		if(tabRepeater) tabRepeater.databind(value)
	}
	public function get itemLabels():Array { return _itemLabels; }
	
	public function set selectedTab(value:Number) {
		tabRepeater.selectedItem = tabRepeater.items[value];
	}
	
	public function MainTabBox() {
		super();
		this._xscale = 100;
		this._yscale = 100;
		dummy._width = 0;
		tabRepeater = Repeater(this.attachMovie("Repeater","tabRepeater",1));
		tabRepeater.direction = "horizontal";
		tabRepeater.itemTemplate = "MainTabItem";
		tabRepeater.separatorTemplate = "MainTabItem_spacer";
		tabRepeater.addEventListener("click", this, "onTabRepeater_click");
		tabRepeater.databind(_itemLabels);
	}
	
	private function onTabRepeater_click(e) {
		if(tabRepeater.selectedItem != e.item) {
			tabRepeater.selectedItem = e.item;
			dispatchEvent( {type:"tabChange",label:e.label,index:e.item.itemPosition} );
		}
	}

	
}