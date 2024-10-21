import mx.utils.Delegate;

class LuminicBox.FlashInspector.UI.LogInspectionItem extends LuminicBox.UI.RepeaterItem {
	
	private var mcBg:MovieClip;
	private var mcToggleIcon:MovieClip;
	private var txtValue:TextField;
	private var _childItems:LuminicBox.UI.Repeater;
	
	var crossRefItem:MovieClip;

	private var _printValue:String;
	private var _expandable:Boolean;
	private var _expanded:Boolean;
	private var _showBg:Boolean = true;
	
// properties
	function set showBg(value:Boolean) {
		_showBg = value;
		mcBg._alpha = (value)?100:0;
	}
	
	function get expandable():Boolean { return _expandable; }
	function set expandable(value:Boolean) {
		mcToggleIcon._visible = value;
		_expandable = value;
	}
	
	function showCrossRefHint() {
		mcBg._alpha = 100;
		mcBg.gotoAndStop(3);
	}
	
	function hideCrossRefHint() {
		if(!_showBg) {
			mcBg._alpha = 0;
		} else {
			mcBg.gotoAndStop(1);
		}
	}
	
// init function
	private function init():Void {
		_expandable = false;
		_expanded = false;
		mcToggleIcon._visible = false;
		// bg events
		mcBg.onRollOver = Delegate.create(this, onBgRollOver);
		mcBg.onRollOut = Delegate.create(this, onBgRollOut);
		mcBg.onReleaseOutside = mcBg.onRollOut;
		mcBg.onRelease = Delegate.create(this, onBgRelease);
		// calculate left margin
		var offsetX:Number = (_parent["inspectionDepth"]*20)
		mcToggleIcon._x = mcToggleIcon._x + offsetX;
		txtValue._x = txtValue._x + offsetX;
		// what to print
		switch(getObj().type) {
			// null / undefined
			case("undefined"):
			case("null"):
				printNull();
				break;
			// objects
			case("properties"):
				txtValue.textColor = 0x3366cc;
				_printValue = getObj().type
				expandable = true;
				delete dataItem.property;
				if(!getObj().value.reversed) {
					// reverse items
					getObj().value.reverse();
					getObj().value.reversed = true;
				}
				break;
			case("object"):
				printObject();
				expandable = true;
				break;
			// primitives
			case("string"):
			case("boolean"):
			case("number"):
			case("date"):
				printValue();
				break;
			// array
			case("array"):
				printArray();
				expandable = (getObj().value.length > 0);
				break;
			// stage objs
			case("button"):
			case("movieclip"):
			case("textfield"):
				printId();
				expandable = true;
				break;
			// xml
			case("xml"):
			case("xmlnode"):
				printType();
				expandable = false;
				break;
			case("sound"):
			case("color"):				/*re-CHECK*/
				printType();
				expandable = true;
				break;
			case("function"):
				printType();
				break;
		}
		
		if(dataItem.property != undefined) _printValue = dataItem.property + ": " + _printValue;
		
		// validate (max depth || cross-reference)
		if(getObj().reachLimit || getObj().crossRef) expandable = false;
		
		txtValue.text = _printValue;
	}
	
	/*
	   available types:
	    function
		properties
		object
		string
		boolean
		number
		undefined
		null
		date
		array
		button
		movieclip
		xml
		xmlnode
		color
	*/
		
	function getObj():Object {
		return dataItem.value;
	}
	
	private function printValue():Void {
		_printValue = getObj().value;
	}
	
	private function printNull():Void {
		_printValue = "(" + getObj().type + ")";
	}
	
	private function printId():Void {
		//_printValue = "(" + getObj().type + " " + getObj().id + ")";
		_printValue = "(" + getObj().id + ")";
	}
	
	private function printType():Void {
		_printValue = "(" + getObj().type + ")";
	}
	
	private function printObject():Void {
		_printValue = "(" + getObj().id + ")";
	}
	
	private function printArray():Void {
		_printValue = "(" + getObj().type + ":" + getObj().value.length + ")";
	}


/* collapse methods (TODO: summarize) */	
	private function toogleInspect():Void {
		dispatchEvent( {type:"iteminspect",item:this} );
	}
	
	private function toogleExpand():Void {
		if(_expanded) {
			mcToggleIcon.gotoAndStop(2);
			collapse();
		} else {
			mcToggleIcon.gotoAndStop(4);
			expand();
		}
	}
	
	function collapse():Void {
		_expanded = false;
		
		if(_childItems) {
			_childItems._visible = false;
			_childItems._yscale = 0;
		}
		
		dispatchEvent( {type:"redraw",item:this} );
	}
	
	function expand():Void {
		_expanded = true ;
		if(!_childItems) {
			_childItems = LuminicBox.UI.Repeater ( attachMovie("Repeater", "mcChildItems", 1) );
			_childItems["inspectionDepth"] = _parent["inspectionDepth"]+1;
			_childItems._y = 20;
			_childItems.direction = "vertical";
			_childItems.addEventListener("ALL", this, "onItemEvent");
			_childItems.itemTemplate = "LogInspectionItem";
			_childItems.databind( getObj().value );
		} else {
			_childItems._visible = true;
			_childItems._yscale = 100;
		}
			
		dispatchEvent( {type:"redraw",item:this} );
	}
	
/* subitems event handler */
	private function onItemEvent(e) {
		if(e.type == "redraw") {
			dispatchEvent( {type:"redraw",item:this} );
		} else if(e.type == "crossreferencehint" && e.item.getObj().value == this.getObj().value) {
			e.item.crossRefItem = this;
			showCrossRefHint();
		} else {
			dispatchEvent(e);
		}
	}
	
/* ui event handlers */
	private function onBgRollOver() {
		mcBg._alpha = 100;
		mcBg.gotoAndStop( (!getObj().crossRef)?2:3 );
		if(getObj().crossRef) dispatchEvent( {type:"crossreferencehint",item:this} );
		if(_expandable)  mcToggleIcon.nextFrame();
		/* TODO: show props in statusbar */
		if(getObj().type != "properties") dispatchEvent( {type:"itemrollover",item:this} );
	}
	
	private function onBgRollOut() {
		if(!_showBg) {
			mcBg._alpha = 0;
		} else {
			mcBg.gotoAndStop(1);
		}
		if(_expandable) mcToggleIcon.prevFrame()
		if(getObj().crossRef) crossRefItem.hideCrossRefHint();
		dispatchEvent( {type:"itemrollout",item:this} );
	}
	
	private function onBgRelease() {
		var type = getObj().type;
		if(_expandable) {
			// inspectable (expandable)
			toogleExpand();
		} else if(getObj().crossRef) {
			// cross-reference
			//crossRefItem.collapse();
		} else if(type == "xml" || type == "xmlnode" || type == "string") {
			// call inspect window
			toogleInspect();
		}
	}

}

/*
 * Tue May 03 01:12:42 2005
 * 	added call to properties.reverse()
 * Sat Apr 30 13:06:08 2005
 * 	new printObj() function for writting object's type using toString().
 * Mon Apr 25 23:11:22 2005
 * 	the cross-reference obj is now highlighted
 * 	getObj(), collapse() and expand() are now public methods
 * 	mcBg.onReleaseOutside = mcBg.onRollOut
 * Tue Mar 22 22:02:06 2005
 * 	added Property inspection. properties are now inspected
 * 	added array.length within {array} label
 * 	fixed xmlnode inspection
 * Mon Nov 29 21:36:51 2004
 * 	fixed redraw bug last items from the second(+) levels
 */