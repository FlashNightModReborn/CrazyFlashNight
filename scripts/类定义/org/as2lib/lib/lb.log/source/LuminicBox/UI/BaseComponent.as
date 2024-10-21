import com.gskinner.net.GDispatcher;

/*
 * Class: LuminicBox.UI.BaseComponent
 * 
 * This is a base class for MovieClips that require an EventDispatcher implementation.
 * 
 * Example:
 * (begin example)
 * // SpecialButton.as:
 * class SpecialButton extends LuminicBox.UI.BaseComponent {
 * 		function onRelease() {
 * 			dispatchEvent( {type:"click",coords:{x:this._xmouse,y:this._ymouse}} );
 * 		}
 * }
 * 
 * // Place an instance of a movieclip at _root and add this to the main timeline:
 * mcSpecialButton.addEventListener("click", this, "mcSpecialButton_onClick");
 * function mcSpecialButton_onClick(e) {
 *		trace("mcSpecialButton.Coords");
 * 		trace("\t X: " + e.coords.x);
 * 		trace("\t Y: " + e.coords.y);
 * }
 * (end)
 */
class LuminicBox.UI.BaseComponent extends MovieClip {

// Group: Event Related Functions
	/*
	 * Function: dispatchEvent
	 * 
	 * Broadcasts an event.
	 * 
	 * Parameters:
	 * 	e - Object. The event's type is defined within the 'type' field of the event object
	 * 
	 * See also:
	 * 	GDispatcher usage: <http://www.gskinner.com/blog/archives/000027.html>
	 */
	function dispatchEvent() {}
	
	/*
	 * Function: addEventListener
	 * 
	 * Adds an observer to object's events.
	 * 
	 * Parameters:
	 * 	type - String. The event's type you want to subscribe to.
	 * 		You can also pass 'ALL' for subscribing to any event.
	 * 	listener - Object. A reference to the listener.
	 * 	handler - String (optional). The name of the function to call.
	 * 
	 * See also:
	 * 	GDispatcher usage: <http://www.gskinner.com/blog/archives/000027.html>
	 */
	function addEventListener() {}
	
	/*
	 * Function: dispatchEvent
	 * 
	 * Removes an event listener.
	 * 
	 * Parameters:
	 * 	Same as addEventListener.
	 * 
	 * 	type - String. The event's type you want to subscribe to.
	 * 		You can also pass 'ALL' for subscribing to any event.
	 * 	listener - Object. A reference to the listener.
	 * 	handler - String (optional). The name of the function to call.
	 * 
	 * See also:
	 * 	GDispatcher usage: <http://www.gskinner.com/blog/archives/000027.html>
	 */
	function removeEventListener() {}
	
	/*
	 * Function: removeAllEventListeners
	 * 
	 * Removes all event listeners from the dispatcher .
	 * 
	 * See also:
	 * 	GDispatcher usage: <http://www.gskinner.com/blog/archives/000027.html>
	 */
	function removeAllEventListeners() {}
	
// Group: Constructor
	/*
	 * Constructor: BaseComponent
	 * 
	 * Initializes de event broadcaster.
	 * 
	 * Uses GDispatcher internally: <http://www.gskinner.com/blog/archives/2003/09/gdispatcher_bug.html>
	 * 
	 */
	function BaseComponent() {
		GDispatcher.initialize(this);
		initFromClipParameters();
	}
	
// Group: Private implementation
	private var clipParameters;
	private function initFromClipParameters(Void):Void {
		var bFound:Boolean = false;
		var i:String;
		for (i in clipParameters) {
			if (this.hasOwnProperty(i)) {
				bFound = true;
				this["def_" + i] = this[i];
				delete this[i];
			}
		}
		if (bFound) {
			for (i in clipParameters) {
				var v = this["def_" + i];
				if (v != undefined) this[i] = v;
			}
		}
	}
	
}

/*
 * Group: Changelog
 * 
 * Wed Apr 27 16:00:16 2005:
 * 	- class documentation.
 * 
 */