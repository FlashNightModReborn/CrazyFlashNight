import ascb.util.logging.Handler;
import ascb.util.logging.Formatter;
import ascb.util.logging.Level;

class ascb.util.logging.TraceHandler extends Handler {

  public function TraceHandler(fmtInstance:Object, nLevel:Number) {
    _fmtInstance = fmtInstance;
    _nLevel = nLevel;
  }

  public function log(oLogRecord:Object):Void {
    if(oLogRecord.level <= _nLevel) {
      trace(_fmtInstance.format(oLogRecord));
    }
  }

}