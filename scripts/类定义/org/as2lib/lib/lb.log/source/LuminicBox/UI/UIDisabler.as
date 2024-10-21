class LuminicBox.UI.UIDisabler extends MovieClip {
	
	function UIDisabler() {
		super();
		this._x = 0;
		this._y = 0;
		enabled = true;
	}
	
	function set enabled(v:Boolean) {
		if(!v) {
			Stage.removeListener(this);
			this._visible = false;
			delete this.onRelease;
		} else {
			Stage.addListener(this);
			onResize();
			this.useHandCursor = false;
			this.onRelease = function() { }
			this._visible = true;
		}
	}
	
	function onResize() {
		this._width = Stage.width;
		this._height = Stage.height;
	}
	
}