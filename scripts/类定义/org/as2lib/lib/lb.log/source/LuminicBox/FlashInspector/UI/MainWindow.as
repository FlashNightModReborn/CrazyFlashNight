class LuminicBox.FlashInspector.UI.MainWindow extends MovieClip {
	
	private var mask:MovieClip;
	private var windowBottom:MovieClip;
	private var windowTop:MovieClip;
	// bevel movieclips
	private var bevelT;
	private var bevelB;
	private var bevelL;
	private var bevelR;
	//private var bevelTL;
	private var bevelTR;
	private var bevelBL;
	private var bevelBR;
	
	private var cornerSize:Number = 10;
	
	public function MainWindow() {
		this.gotoAndStop(2);
		var w:Number = _width;
		var h:Number = _height;
		this._xscale = 100;
		this._yscale = 100;
		setSize(w,h);
	}
	
	public function setSize(w:Number,h:Number) {
		windowTop._width = w;
		windowBottom._width = w;
		windowBottom._y = h-windowBottom._height;
		// mask shape
		mask.w._width = w;
		mask.w._height= h-cornerSize*2;
		mask.h._height = h;
		mask.h._width = w-cornerSize*2;
		mask.cornerBL._y = h - cornerSize;
		mask.cornerTR._x = w - cornerSize;
		mask.cornerBR._y = h - cornerSize;
		mask.cornerBR._x = w - cornerSize;
		// bevels
		bevelT._width = w-cornerSize*2;
		bevelB._width = w-cornerSize*2;
		bevelL._height = h-cornerSize*2;
		bevelR._height = h-cornerSize*2;
		bevelB._y = h;
		bevelR._x = w;
		bevelTR._x = w;
		bevelBR._x = w;
		bevelBR._y = h;
		bevelBL._y = h;
	}
	
}