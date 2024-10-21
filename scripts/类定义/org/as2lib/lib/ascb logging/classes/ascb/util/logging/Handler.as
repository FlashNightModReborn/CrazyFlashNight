import ascb.util.logging.Level;
import ascb.util.logging.Formatter;

class ascb.util.logging.Handler {

  private var _fmtInstance:Object;
  private var _nLevel:Number;

  public function Handler(fmtInstance:Object, nLevel:Number) {
    _fmtInstance = fmtInstance;
    _nLevel = nLevel;
  }

  public function log(oLogRecord:Object):Void {
    if(oLogRecord.level >= _nLevel) {
      trace(_fmtInstance.format(oLogRecord));
    }
  }

}