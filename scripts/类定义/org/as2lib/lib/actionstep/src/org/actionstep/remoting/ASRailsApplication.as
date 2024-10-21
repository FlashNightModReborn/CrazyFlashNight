import org.actionstep.remoting.*;

class org.actionstep.remoting.ASRailsApplication {
  private var m_driver:ASRailsDriver;
  private var m_command:ASRailsCommandDispatcher;
  
  public function setCommandContext(command:ASRailsCommandDispatcher) {
    m_command = command;
  }
  
  public function ASRailsApplication(driver:ASRailsDriver) {
    m_driver = driver;
  }
  
  public function loadFromController(controllerName) {
    m_driver.loadComponentsFromURL(controllerName, m_command.component());
  }
  
  public function clearCommandContext() {
    m_command = null;
  }
  
  public function toString():String {
    return "ASRailsApplication";
  }
}