import LuminicBox.FlashInspector.UI.*;
import LuminicBox.Utils.Delay;

class LuminicBox.FlashInspector.UI.InspectionWindow extends LuminicBox.UI.BaseComponent {
	
	private var data:Object;
	private var txtInspect:TextField;
	private var scrollbar:MovieClip;
	private var btnClose:Button;
	private var windowContainer:MovieClip;
	private var window:MainWindow;
	private var d:Delay;
	
	function InspectionWindow() {
		super();
		window = MainWindow( windowContainer.attachMovie("MainWindow", "window", 1) );
		//scrollbar = this .attachMovie("Vscrollbar", "scrollbar", 100);
		//scrollbar.enabled = true;
		//scrollbar.target = txtInspect;
		btnClose.onRelease = mx.utils.Delegate.create(this, close);
	}
	
	public function close() {
		dispatchEvent( {type:"close"} );
		this.removeAllEventListeners();
		this.removeMovieClip();
	}
	
	
	public function setSize(w:Number, h:Number):Void {
		window.setSize(w,h);
		btnClose._x = w - 25;
		txtInspect._width = w - 35;
		txtInspect._height = h - 35;
		scrollbar._x = txtInspect._x + txtInspect._width;
		d = new Delay(10, this, updateScroll);
		//scrollbar.setSize(15, txtInspect._height);
	}
	
	private function updateScroll() {
		trace("updating scroll");
		scrollbar.setSize(15, txtInspect._height);
	}
	
	public function inspect(o:Object) {
		data = o;
		showTxt();
		/*if(data.type == "xml") {
			showXml();
		} else {
			showTxt();
		}*/
	}	
	
	/*private function showXml():Void {
		var xml = new XML(data.value.toString());
		trace(xml);
		var html:String = XMLHighlighter.highlight( xml );
		txtInspect.htmlText = html;
	}*/
	
	private function showTxt():Void {
		txtInspect.text = data.value.toString();
	}
	
}

/*
 * Changelog
 * 
 * Sat Apr 30 13:25:36 2005
 * 	added delay for scrollbar.setSize()
 * 	removed showXml()
 * 	InspectWindow now decides how to format the string.
 */