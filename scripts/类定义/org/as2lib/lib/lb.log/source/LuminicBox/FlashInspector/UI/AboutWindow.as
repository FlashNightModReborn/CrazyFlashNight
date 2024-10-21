import LuminicBox.FlashInspector.UI.*;

class LuminicBox.FlashInspector.UI.AboutWindow extends LuminicBox.UI.BaseComponent {
	
	private var btnClose:Button;
	private var mcText:MovieClip;
	private var window:MovieClip;
	
	function AboutWindow() {
		super();
		btnClose["owner"] = this;
		btnClose.onRelease = function() { this.owner.close(); }
		
		Mouse.addListener(this);
		//mcText.useHandCursor = false;
		//mcText.onRollOver = function() { this.stop(); }
		//mcText.onRollOut = function() { this.play(); }
	}
	
	public function close() {
		dispatchEvent( {type:"close"} );
		this.removeAllEventListeners();
		this.removeMovieClip();
	}
	
	public function onMouseMove() {
		var xmouse = window._xmouse;
		var ymouse = window._ymouse;
		
		var maxX = 300;
		var maxY = 160;
		
		trace(maxX + ";" + maxY);
		
		if (xmouse >= 0 && xmouse <= maxX && ymouse >= 0 && ymouse <= maxY) {
			mcText.stop();
		} else {
			mcText.play();
		}
	}
}