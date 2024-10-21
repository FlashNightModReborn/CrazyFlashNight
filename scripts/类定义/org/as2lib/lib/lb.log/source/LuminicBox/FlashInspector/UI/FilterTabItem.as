class LuminicBox.FlashInspector.UI.FilterTabItem extends LuminicBox.UI.RepeaterItem {
	
	private var mcBg:MovieClip;
	private var mcBgMask:MovieClip;
	private var innerShadow:MovieClip;
	private var outerShadow:MovieClip;
	
	private var _selected:Boolean;
	private var title:String;
	
	public function get selected():Boolean { return _selected; }
	public function set selected(value:Boolean) {
		_selected = value;
		if(value) {
			removeEvents();
			mcBgMask.gotoAndStop("selected");
			dispatchEvent({type:"itemselected",item:this});
		} else {
			setupEvents();
			mcBgMask.gotoAndStop("unselected");
		}
		innerShadow._visible = !value;
		outerShadow._visible = value;
	}
	
	public function FilterTabItem() {
		super();
		mcBg.setMask(mcBgMask);
		outerShadow._visible = false;
	}
	
	private function init() {
		_selected = false;
		title = dataItem.level.getName();
		setColor(dataItem.color);
		setupEvents();
	}
	
	private function setColor(hex:Number) {
		var c:Color = new Color(mcBg);
		c.setRGB(hex);
	}
	
	private function setupEvents() {
		mcBg.onRelease = function() { _parent._parent.selectedItem = _parent;  }
	}
	
	private function removeEvents() {
		delete mcBg.onRelease;
	}
	
}