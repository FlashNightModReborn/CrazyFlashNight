import ascb.util.logging.Level;

class ascb.util.logging.LocalConnectionHandler {

  private var _lcWindow:LocalConnection;

  public function LocalConnectionHandler() {
    _lcWindow = new LocalConnection();
  }

  public function log(oLogRecord:Object):Void {
    _lcWindow.send("_logger", "onMessage", "Log Message\n\tlevel - " + Level.LABELS[oLogRecord.level] + "\n\ttime - " + new Date() + "\n\tname - " + oLogRecord.name + "\n\tmessage - " + oLogRecord.message);
  }

}