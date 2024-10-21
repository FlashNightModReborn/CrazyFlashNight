import ascb.util.logging.Logger;
import ascb.util.logging.TraceHandler;
import ascb.util.logging.LocalConnectionHandler;
import ascb.util.logging.Level;
import ascb.util.Proxy;

class ascb.util.logging.LogManager {

  private static var _lmInstance:LogManager = new LogManager();
  private static var _importProxy:Object = ascb.util.Proxy["a"]();
  private static var _importEventDispatcher:Object = mx.events.EventDispatcher["a"]();

  private var _oLoggers:Object;
  private var _xmlConfiguration:XML;
  private var _nInterval:Number;
  private var _aHandlers:Array;
  private var _nLevel:Number;

  public var addEventListener:Function;
  public var removeEventListener:Function;
  private var dispatchEvent:Function;

  private function LogManager() {
    mx.events.EventDispatcher.initialize(this);
    _oLoggers = new Object();
    _aHandlers = new Array();
    _nLevel = Level.ALL;

    // Wait 10 milliseconds before initializing the manager because
    // otherwise ascb.util.Proxy hasn't loaded into memory yet.
    _nInterval = setInterval(this, "run", 10);
  }

  private function run():Void {
    clearInterval(_nInterval);
    _xmlConfiguration = new XML();
    _xmlConfiguration.ignoreWhite = true;
    _xmlConfiguration.onLoad = ascb.util.Proxy.create(this, initialize);
    _xmlConfiguration.load("logconfiguration.xml");
  }

  public static function getLogManager():LogManager {
    return _lmInstance;
  }

  private function initialize():Void {
    var aHandlers:Array = _xmlConfiguration.firstChild.firstChild.childNodes;
    var fmtInstance:Object;
    var nLevel:Number;
    for(var i:Number = 0; i < aHandlers.length; i++) {
      if(aHandlers[i].firstChild.nodeValue == "true") {
        fmtInstance = (aHandlers[i].attributes.formatter == undefined) ? (new ascb.util.logging.Formatter()) : (new [aHandlers[i].attributes.formatter]());
        nLevel = (aHandlers[i].attributes.level == undefined) ? Level.ALL : Level["" + aHandlers[i].attributes.level];
        switch(aHandlers[i].nodeName) {
          case "trace":
            _aHandlers.push(new TraceHandler(fmtInstance,  nLevel));
            break;
          case "localconnection":
            _aHandlers.push(new LocalConnectionHandler(fmtInstance, nLevel));
            break;
          default:
            _aHandlers.push(new [aHandlers[i].nodeName](fmtInstance, nLevel));
            break;
        }
      }
    }
    dispatchEvent({type: "initialized", target: this});
  }

  public function getLogger(sName:String):Logger {
    return _oLoggers[sName];
  }

  public function addLogger(lInstance:Logger):Void {
    _oLoggers[lInstance.getName()] = lInstance;
  }

  public function log(oLogRecord:Object):Void {
    for(var i:Number = 0; i < _aHandlers.length; i++) {
      _aHandlers[i].log(oLogRecord);
    }
  }

}