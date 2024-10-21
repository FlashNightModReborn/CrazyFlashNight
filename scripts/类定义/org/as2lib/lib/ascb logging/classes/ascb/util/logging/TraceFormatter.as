import ascb.util.logging.Level;

class ascb.util.logging.TraceFormatter {

  public function TraceFormatter() {

  }

  public function format(oLogRecord:Object):String {
    return "Log Message\n\tlevel - " + Level.LABELS[oLogRecord.level] + "\n\ttime - " + new Date() + "\n\tname - " + oLogRecord.name + "\n\tmessage - " + oLogRecord.message;
  }

}