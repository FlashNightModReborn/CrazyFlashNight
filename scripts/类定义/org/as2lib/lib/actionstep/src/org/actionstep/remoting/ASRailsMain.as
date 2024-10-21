import org.actionstep.ASDebugger;
import org.actionstep.remoting.ASRailsDriver;

class org.actionstep.remoting.ASRailsMain {
  
  private static var driver:ASRailsDriver;
  
  public static function main() {
    Stage.align="LT";
    Stage.scaleMode="noScale";
    ASDebugger.setLevel(ASDebugger.INFO);
    try
    {
      driver = new ASRailsDriver();
      driver.connect();
    }
    catch (e:Error)
    {
      trace(e.message);
    }
  }

}
