import LuminicBox.FlashInspector.*;

/**
* FlashInspection starter
*/
class LuminicBox.FlashInspector.Application {
	
	private var _uiController:UIController;
	
	/**
	* Inits FlashInspector application
	* @param root Reference to _root.
	*/
	public function Application(root:MovieClip) {
		_uiController = new UIController(root);
		
	}
	
}

/*
 * Changelog
 * 
 * Mon May 02 23:55:59 2005
 * 	detection for more than one instance of FlashInspector
 */