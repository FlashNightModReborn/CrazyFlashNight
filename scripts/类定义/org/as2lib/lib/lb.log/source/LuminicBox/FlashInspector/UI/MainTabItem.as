import LuminicBox.UI.*;

class LuminicBox.FlashInspector.UI.MainTabItem extends RepeaterItem {
	
	private var _selected:Boolean=false;

	private var bevelB:MovieClip;
	private var bevelR:MovieClip;
	private var innerShadow:MovieClip;
	private var outerShadow:MovieClip;
	private var bg:MovieClip;
	private var txtName:TextField;
	private var txtShadow:TextField;
	
	private var shadowMask:MovieClip;
	private var mask:MovieClip;
	private var maskSelected:MovieClip;
	
	public function init() {
		setText(dataItem.toString());
		this.hitArea = bg;
	}
	
	private function setText(text:String) {
		text = text.toUpperCase();
		// set text
		txtName.text = text;
		txtShadow.text = text;
		var width = txtName.textWidth+5
		txtName._width = width;
		txtShadow._width = width;
		// bg
		bg.body._width = width;
		bg.sideR._x = width+16;
		// inner shadow
		innerShadow._width = width+16;
		// bevels
		bevelB._width = width;
		bevelR._x = width+16;
		// outer shaow
		outerShadow._x = width+18;
		
		shadowMask._width = width+16;
		mask._width = width+16;
		maskSelected._width = width+16;
	}
	
	public function get selected():Boolean { return _selected; }
	public function set selected(value:Boolean) {
		_selected = value;
		gotoAndStop( (value)?"selected":"unselected" );
		setText(dataItem.toString());
	}
	
	public function onRelease() {
		dispatchEvent( {type:"click",item:this,label:dataItem.toString()} );
	}
	
}