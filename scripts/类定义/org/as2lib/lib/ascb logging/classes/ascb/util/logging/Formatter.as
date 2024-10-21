import ascb.util.logging.Level;

class ascb.util.logging.Formatter {

  public function Formatter() {

  }

  public function format(oLogRecord:Object):String {
    return "Log Message\n\tlevel - " + Level.LABELS[oLogRecord.level] + "\n\ttime - " + new Date() + "\n\tname - " + oLogRecord.name + "\n\tmessage - " + oLogRecord.message;
  }

}