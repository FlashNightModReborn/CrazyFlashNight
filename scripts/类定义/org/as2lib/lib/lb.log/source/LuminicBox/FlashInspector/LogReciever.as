import LuminicBox.Log.*;
import LuminicBox.FlashInspector.LogEventCollection;

class LuminicBox.FlashInspector.LogReciever extends Object {
	
	private var _lc:LocalConnection;			// local connection obj
	private var _connected:Boolean = false;
	private var _logEvents:LogEventCollection;
	private var _minRequiredVersion:Number = 0.1;		// the ConsolePublisher minimal required version
	private var _log:Logger;
	
	var onError:Function
	var onLogEvent:Function;
	function get isConnected():Boolean { return _connected; }
	function get logEvents():LogEventCollection { return _logEvents; }
	
	function LogReciever() {
		// create event debugger
		_log = new Logger();
		_log.addPublisher( new TracePublisher() );
		_log.setLevel(Level.WARN);
		// create LogEventCollection
		_logEvents = new LogEventCollection();
		if(!connect()) onError("ConnectionInUse");
	}
	
	private function connect():Boolean {
		// create local connection obj
		_lc = new LocalConnection();
		_lc.allowDomain = function(domain) { return true; }
		_lc["log"] = mx.utils.Delegate.create(this, onEvent);
		_connected = _lc.connect("_luminicbox_log_console");
		return _connected;
	}

	
	private function onEvent(e) {
		// debug message
		_log.debug(e);
		// check for minimal required version
		if(e.version <= _minRequiredVersion) {
			_log.warn("incorrect version:" + e.version + " (" + e.loggerId + ")");
			return;
		}
		// save log message
		var logEvent:LogEvent = LogEvent.deserialize(e);
		_logEvents.push( logEvent );
		onLogEvent( logEvent )
	}
	
}

/*
* Tue Apr 19 01:50:18 2005
* 	added isConnected() property
* 	changed event model to callbacks
*/