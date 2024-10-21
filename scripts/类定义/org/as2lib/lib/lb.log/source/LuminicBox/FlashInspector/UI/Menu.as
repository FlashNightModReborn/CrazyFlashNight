class LuminicBox.FlashInspector.UI.Menu extends LuminicBox.UI.BaseComponent {
	
	private var txtMenu:TextField;
	private var cssEnabled;
	private var cssDisabled;
	
	public function Menu() {
		super();
		cssEnabled = new TextField.StyleSheet();
		cssEnabled.parseCSS("a{color:#FFFFFF;} a:hover{color:#00CCFF;}")
		cssDisabled = new TextField.StyleSheet();
		cssDisabled.parseCSS("a{color:#FFFFFF;}")
		//var html = "<a href=\"asfunction:openLink,settings\">SETTINGS</a> | <a href=\"asfunction:openLink,help\">HELP</a> | <a href=\"asfunction:openLink,about\">ABOUT</a>";
		var html = "<a href=\"asfunction:openLink,about\">ABOUT</a>";
		
		txtMenu.autoSize = true;
		txtMenu.htmlText = html;
		enabled = true;
	}
	
	function set enabled(v:Boolean) {
		if(!v) {
			txtMenu.styleSheet = cssDisabled;
		} else {
			txtMenu.styleSheet = cssEnabled;
		}
	}

	function openLink(id) {
		dispatchEvent( {type:"click",item:id} );
	}
}