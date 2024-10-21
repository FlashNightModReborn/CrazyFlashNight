import LuminicBox.FlashInspector.LogReciever;
import LuminicBox.FlashInspector.UI.*;
import LuminicBox.Log.*;
import LuminicBox.UI.*;
import mx.utils.Delegate;
/**
* Manages UI related actions and communicates with the log reciever (model) and ui components (view)
*/
class LuminicBox.FlashInspector.UIController {
	
	private var logReciever:LogReciever;
	private var log:Logger;
	
	private var selectedFilter:Level;
	
	private var root:MovieClip;
	private var bg:MovieClip;
	private var uiDisabler:UIDisabler;
	private var mainWindow:MainWindow;
	private var eventWindow:EventWindow;
	private var filterTabBox:FilterTabBox;
	private var infoBar:InfoBar;
	private var inspectWindow:InspectionWindow;
	private var aboutWindow:AboutWindow;
	private var warningWindow:MovieClip;
	private var menu:Menu;
	private var btnClear:Button;
	
	private var minWidth:Number = 500;
	private var minHeight:Number = 300;
	
	/**
	* @param root Reference to _root mc.
	*/
	public function UIController(root:MovieClip, reciever:LogReciever) {
		// log obj
		log = new Logger("FI:UIController");
		var tp:TracePublisher = new TracePublisher();
		tp.maxDepth = 2;
		log.addPublisher(tp);
		// setup stage
		Stage.scaleMode = "noScale";
		Stage.align = "TL";
		var stageListener:Object = new Object();
		stageListener.owner = this;
		stageListener.onResize = function() { this.owner.onStageResize(); }
		Stage.addListener(stageListener);
		// save controls
		this.root = root;
		mainWindow = MainWindow(root.mainWindow);
		eventWindow = EventWindow(root.eventWindow);
		filterTabBox = FilterTabBox(root.filterTabBox);
		infoBar = InfoBar(root.infoBar);
		btnClear = Button(root.btnClear);
		uiDisabler = UIDisabler(root.uiDisabler);
		menu = Menu(root.menu);
		bg = root.bg;
		// attach events
		filterTabBox.addEventListener("changeFilter", this, "onFilterChange");
		eventWindow.addEventListener("eventInfo", this, "onEventInfo")
		eventWindow.addEventListener("eventInfoOut", this, "onEventInfoOut")
		eventWindow.addEventListener("eventInspect", this, "onEventInspect")
		btnClear["owner"] = this;
		btnClear.onRelease = function() { this.owner.onClearRequest(); }
		menu.addEventListener("click", this, "onMenuClick");
		// set initial state controls
		uiDisabler.enabled = false;
		infoBar._visible = false;
		filterTabBox.setFilter(LuminicBox.Log.Level.LOG)
		// create for logReciever
		if(!createLogReciever()) {
			// halt
			uiDisabler.enabled = true;
			warningWindow = root.attachMovie("warningWindow", "warningWindow", 1);
			warningWindow.onClose = Delegate.create(this, warningWindow_onClose);
		}
		onStageResize();
	}
	
	private function createLogReciever():Boolean {
		logReciever = new LogReciever();
		logReciever.onLogEvent = Delegate.create(this, logReciever_onLogEvent);
		logReciever.onError = Delegate.create(this, logReciever_onError);
		return logReciever.isConnected;
	}

	
	private function createInspectionWindow():InspectionWindow {
		uiEnabled = false;
		inspectWindow = InspectionWindow( root.attachMovie("InspectionWindow", "inspectWindow",1) );
		inspectWindow.addEventListener("close", this, "onWindowClose");
		inspectWindow._x = 45;
		inspectWindow._y = 89;
		onStageResize();
		return inspectWindow;
	}
	
	private function createAboutWindow():AboutWindow {
		uiEnabled = false;
		aboutWindow = AboutWindow( root.attachMovie("AboutWindow", "aboutWindow",1) );
		aboutWindow.addEventListener("close", this, "onWindowClose");
		aboutWindow._y = 60;
		onStageResize();
		return aboutWindow;
	}
	
	function set uiEnabled(v:Boolean):Void {
		uiDisabler.enabled = !v;
		menu.enabled = v;
	}
	
	private function logReciever_onLogEvent(event:LogEvent) {
		var filterValue = selectedFilter.getValue();
		if(filterValue<=event.level.getValue() || filterValue == 0) {
			eventWindow.addItem( event );
		}
	}
	
	private function logReciever_onError(e) {
		log.fatal("logReciever.error!");
	}
		
	/**
	* Event handler for Stage.onResize. Resizes inner windows.
	* <pre>
	*	Stage.scaleMode = "noScale";<br>
	*	Stage.align = "TL";<br>
	*	var stageListener:Object = new Object();<br>
	*	stageListener.owner = uiController;<br>
	*	stageListener.onResize = function() { this.owner.onStageResize(); }<br>
	*	Stage.addListener(stageListener);<br>
	* </pre>
	*/
	private function onStageResize():Void {
		var w:Number = Stage.width;
		var h:Number = Stage.height;
		if(w<minWidth) w = minWidth;
		if(h<minHeight) h = minHeight;
		mainWindow.setSize(w-20,h-45);
		eventWindow.setSize(w-40,h-105);
		//mainTabBox._x = w-mainTabBox._width-20;
		btnClear._x = w-btnClear._width-20;
		bg._width = w;
		infoBar._y = h-35;
		menu._x = w-menu._width-25;
		if(inspectWindow) inspectWindow.setSize(w-90,h-115);
		if(aboutWindow) aboutWindow._x = Math.round((w-aboutWindow._width+30)/2);
		if(warningWindow) {
			warningWindow._x = Math.round( (w-warningWindow._width)/2 );
			warningWindow._y = Math.round( (h-warningWindow._height)/2 );
		}
	}
	
	/**
	* Event handler for EventWindow.changeFilter. Changes events window's color and filters events.<br/>
	* Usage: <code>filterTabBox.addEventListener("changeFilter", uiController, "onFilterChange");</code>
	* @param e Event Obj
	*/
	private function onFilterChange(e):Void {
		selectedFilter = e.level;
		eventWindow.setColor(e.color);
		eventWindow.populate( logReciever.logEvents.getByLevel(selectedFilter) );
	}
	
	private function onEventInspect(e):Void {
		//log.debug(e.logEvent);
		createInspectionWindow();
		inspectWindow.inspect(e.logEvent.argument);
	}
	
	private function onEventInfo(e):Void {
		infoBar.databind( e.logEvent );
		infoBar._visible = true;
	}
	
	private function onEventInfoOut():Void {
		infoBar._visible = false;
	}
	
	private function onMenuClick(e):Void {
		uiDisabler.enabled = true;
		menu.enabled = false;
		switch(e.item) {
			case("about"):
				createAboutWindow();
				break;
		}
	}
	
	private function onClearRequest():Void {
		logReciever.logEvents.clear();
		eventWindow.clear();
	}
	
	private function onWindowClose(e):Void {
		uiEnabled = true;
	}
	
	private function warningWindow_onClose():Void {
		if(createLogReciever()) {
			warningWindow.removeMovieClip();
			delete warningWindow;
			uiEnabled = true;
		}
	}

	
}

/*
 * Changelog
 * 
 * Mon May 02 23:55:59 2005
 * 	detection for more than one instance of FlashInspector
 * Sat Apr 30 13:25:36 2005
 * 	InspectWindow now decides how to format the string.
 * Tue Mar 22 22:07:21 2005
 * 	added xml highlighting for xmlnodes
 * 
 */