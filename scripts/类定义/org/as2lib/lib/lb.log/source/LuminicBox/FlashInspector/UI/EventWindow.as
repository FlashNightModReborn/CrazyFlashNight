import LuminicBox.UI.*;

class LuminicBox.FlashInspector.UI.EventWindow extends BaseComponent {
	
	private var innerWindow:MovieClip;
	private var outerWindow:MovieClip;
	private var innerShadowT:MovieClip;
	private var innerShadowR:MovieClip;
	private var outerShadow:MovieClip;
	
	private var eventsMark:MovieClip;
	private var events:Repeater;
	private var mask:MovieClip;
	private var scroll:ScrollBar;
	
	private var color:Color;
	
	public function EventWindow() {
		super();
		events = Repeater(eventsMark.attachMovie("Repeater","events",1));
		events._y = 0;
		events.itemTemplate = "LogEventItem";
		events.direction = "vertical";
		events["inspectionDepth"] = 0;
		events.addEventListener("redraw", this, "events_onRedraw");
		events.addEventListener("iteminspect", this, "events_onInspect");
		events.addEventListener("itemrollover", this, "events_onItemRollover");
		events.addEventListener("itemrollout", this, "events_onItemRollout");
		events.setMask(mask);
		color = new Color(outerWindow);
		var w:Number = _width;
		var h:Number = _height;
		this._xscale = 100;
		this._yscale = 100;
		setSize(w,h);
	}
	
	public function populate(logEvents:Array) {
		clear();
		events.databind(logEvents);
		scroll.update();
	}
	
	
	public function addItem(logEvent):Void {
		var scrollDown:Boolean = (scroll.position == 100);
		events.addItem(logEvent);
		scroll.update();
		if(scrollDown) scroll.position = 100;
	}

	public function clear():Void {
		events.reset();
		scroll.reset();
	}
	
	public function setColor(value:Number) {
		color.setRGB(value);
	}
	
	public function setSize(w:Number,h:Number) {
		var scrollDown:Boolean = (scroll.position == 100);
		// mask
		mask._height = h-8;
		mask._width = w - 8 - scroll._width;
		// window
		innerWindow._width = w-8;
		innerWindow._height = h-8;
		outerWindow._width = w;
		outerWindow._height = h;
		// shadows
		outerShadow._width = w;
		outerShadow._height = h;
		innerShadowR._height = h-8;
		innerShadowT._width= w-10;
		// borders
		var outerBorder = this.createEmptyMovieClip("outerBorder",100);
		outerBorder.lineStyle(2,0x777777,100);
		outerBorder.lineTo(w, 0);
		outerBorder.lineTo(w, h);
		outerBorder.lineTo(0, h);
		outerBorder.lineTo(0, 0);
		var innerBorder = this.createEmptyMovieClip("innerBorder",200);
		innerBorder.moveTo(4,4);
		innerBorder.lineStyle(1,0x777777,100);
		innerBorder.lineTo(w-4, 4);
		innerBorder.lineTo(w-4, h-4);
		innerBorder.lineTo(4, h-4);
		innerBorder.lineTo(4, 4);
		// scroll
		scroll._x = w - scroll._width - 4; 
		scroll.setHeight(h-8);
		scroll.update();
		if(scrollDown) scroll.position = 100;
	}
	
	public function events_onInspect(e) {
		dispatchEvent( {type:"eventInspect",logEvent:e.item.dataItem} );
	}
	
	public function events_onRedraw(e) {
		var scrollDown:Boolean = (scroll.position == 100);
		scroll.update();
		if(scrollDown) scroll.position = 100;
	}
	
	public function events_onItemRollover(e) {
		dispatchEvent( {type:"eventInfo",logEvent:e.item.dataItem} );
	}
	
	public function events_onItemRollout(e) {
		dispatchEvent( {type:"eventInfoOut"} );
	}

	
}

/* * Tue Apr 26 01:08:12 2005
 * 	removed itemcreated event handler
 */