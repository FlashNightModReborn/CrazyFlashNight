class LuminicBox.UI.ScrollBar extends LuminicBox.UI.BaseComponent {

// fields	
	// controls
	private var btnB:Button;
	private var btnF:Button;
	private var btnBar:Button;
	private var mcBg:MovieClip;
	// content & mask
	private var mcContent:MovieClip;
	private var mcMask:MovieClip;
	// vars
	private var pageSize:Number;
	private var contentSize:Number;
	private var _smoothScroll:Boolean=false;
	
// properties:
	[Inspectable(type="Boolean",defaultValue="false")]
	public function get smoothScroll():Boolean { return _smoothScroll; }
	public function set smoothScroll(value:Boolean) { _smoothScroll = value; }
	
	[Inspectable()]
	public function get content():MovieClip { return mcContent; }
	public function set content(mc:MovieClip) {
		if(typeof(mc) == "string") mc = this._parent[mc];
		mcContent = mc;
	}
	[Inspectable()]
	public function get mask():MovieClip { return mcMask; }
	public function set mask(mc:MovieClip) {
		if(typeof(mc) == "string") mc = this._parent[mc];
		mcMask = mc;
	}
	
	public function get position():Number {
		if(contentSize>pageSize) {
			return (mcContent._y-mcMask._y)*-100 / (contentSize-pageSize);
		} else {
			return 100;
		}
	}
	public function set position(value:Number) {
		setContentPosition(value);
		updateBar();
	}

// constructor
	function ScrollBar() {
		super();
		// set initial state
		var h = this._height;
		this._xscale = 100;
		this._yscale = 100;
		setHeight(h);
		// add event handlers
		btnB.onPress = mx.utils.Delegate.create(this,btnB_onClick);
		btnF.onPress = mx.utils.Delegate.create(this,btnF_onClick);
		btnBar.onPress = mx.utils.Delegate.create(this,btnBar_onPress);
		btnBar.onRelease = mx.utils.Delegate.create(this,btnBar_onRelease);
		btnBar.onReleaseOutside = mx.utils.Delegate.create(this,btnBar_onRelease);
		reset();
	}
	
// methods
	function update() {
		updateBar();
	}
	
	function reset() {
		if(!mcMask || !mcContent) return;
		mcContent._y = mcMask._y;
		updateBar();
	}
	
	function setHeight(h:Number) {
		mcBg._y = 0;
		mcBg._height = h;
		btnF._y = h-btnF._height;
	}
	
// private methods
	private function calculateSize() {
		pageSize = mcMask._height;
		contentSize = mcContent._height;
	}
	
	private function updateBar() {
		calculateSize();
		var barArea = mcBg._height - (btnB._height + btnF._height);
		var barStart = btnB._height;
		// caculate bar size
		var pageSizePer = (pageSize *  100) / contentSize;
		// validate size
		btnBar._visible = (pageSizePer < 100)
		if(pageSizePer >= 100) return;
		var barSize = (barArea * pageSizePer) / 100;
		btnBar._height = barSize;
		// calculate bar position
		var posPer = (mcContent._y-mcMask._y)*-100 / (contentSize-pageSize);
		var newPos = barStart +  (barArea-barSize) * posPer / 100;
		// validate new bar position
		//if(newPos < (barArea + barStart - barSize)) newPos = (barArea + barStart - barSize);
		var maxPos = (barStart + barArea) - barSize
		if(newPos > maxPos) newPos = maxPos;
		btnBar._y = newPos;
	}
	
	private function scroll(direction) {
		var offset = (pageSize * .1) * direction;
		var newPos = mcContent._y + offset;
		var minPos = mcMask._y;
		var maxPos = mcMask._y - (contentSize-pageSize);
		if(newPos > minPos) {
			newPos = minPos;
		} else if(newPos < maxPos) {
			newPos = maxPos;
		}
		moveContent(newPos);
	}
	
	private function setContentPosition(posPer) {
		calculateSize();
		var minPos = mcMask._y;
		var maxPos = mcMask._y - (contentSize-pageSize);
		var newPos = (posPer*(contentSize-pageSize))/-100+mcMask._y;
		if(newPos > minPos) {
			newPos = minPos;
		} else if(newPos < maxPos) {
			newPos = maxPos;
		}
		moveContent(newPos)
	}
	
	private function moveContent(posY) {
		if(!_smoothScroll) {
			mcContent._y = posY;
		} else {
			new mx.transitions.Tween(mcContent,"_y",mx.transitions.easing.Regular.easeOut,mcContent._y, posY, 5);
		}
	}
	

	
// event handlers
	private function btnB_onClick() {
		scroll(1);
		updateBar();
	}
	private function btnF_onClick() {
		scroll(-1);
		updateBar();
	}
	private var lastMousePos=0;
	private function btnBar_onPress() {
		lastMousePos = this._ymouse;
		this.onMouseMove = mouse_onMove;
	}
	private function btnBar_onRelease() {
		Mouse.removeListener(this);
		delete this.onMouseMove;
	}
	private function mouse_onMove() {
		var minPos = btnB._height;
		var maxPos = btnF._y - btnBar._height;
		var newMousePos = this._ymouse;
		if(newMousePos<minPos) {
			newMousePos = minPos;
		} else if(newMousePos > (this._height-btnF._height)) {
			newMousePos = this._height-btnF._height;
		}
		var newPos = btnBar._y + (lastMousePos - newMousePos) * -1;
		if(newPos < minPos) {
			newPos = minPos;
		} else if(newPos > maxPos) {
			newPos = maxPos;
		}
		btnBar._y = newPos;
		lastMousePos = newMousePos;
		
		var barArea = mcBg._height - (btnB._height + btnF._height);		
		var posPer = 100/(barArea-btnBar._height) * (newPos-minPos);
		setContentPosition(posPer);
	}

	// 	reset
	// 	update
	// event handlers
	// 	mcBar_onDrag
	// 	btnB_onClick
	// 	btnF_onClick

	
}