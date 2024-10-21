class LuminicBox.FlashInspector.UI.InfoBar extends LuminicBox.UI.BaseComponent {
	
	private var txtInfo:TextField;
	
	public function InfoBar() {
		super();
	}
	
	public function databind(e) {
		var s;
		var o;
		if(e.loggerId) {
			var time = e.time.getHours() + ":" + e.time.getMinutes() + ":" + e.time.getSeconds();
			s = "LogId: " + e.loggerId + "\t\tTime: " + time + "\n";
			o = e.argument;
			
			//s += "Type: " + typeOf;
			//if(typeOf == "array") s += "\t\tCount: " + e.argument.value.length;
			
		} else {
			o = e.value;
			//s += "Type: " + typeOf;
			//if(typeOf == "array") s += "\t\tCount: " + e.value.value.length;
			if(isNaN(e.property)) {
				s = "Propery: " + e.property + "\n";
			} else {
				s = "Index: " + e.property + "\n";
			}
		}
		
		var typeOf = o.type;

		s += "Type: " + typeOf;
		if(typeOf == "array") s += "\t\tCount: " + o.value.length;
		if(o.reachLimit) s += "\t<font color=\"#FF0000\">MaxDepth reached!</font>"
		if(o.crossRef) s += "\t<font color=\"#FF0000\">Cross-Reference detected</font>"
		
		txtInfo.htmlText = s;
	}
	
}