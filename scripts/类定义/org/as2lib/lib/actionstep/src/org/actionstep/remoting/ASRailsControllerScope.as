import org.actionstep.remoting.ASRailsComponentDefinition;
import org.actionstep.remoting.ASRailsCommandDispatcher;
import org.actionstep.remoting.ASRailsDriver;

class org.actionstep.remoting.ASRailsControllerScope {
  private var m_url:String;
  private var m_components:Array;
  private var m_loadVars:LoadVars;
  private var m_commands:Array;
  private var m_driver:ASRailsDriver;
  
  public function ASRailsControllerScope(driver:ASRailsDriver, url:String) {
    m_driver = driver;
    m_url = url;
    m_components = new Array();
    m_commands = new Array();
  }
  
  public function url():String {
    return m_url;
  }
  
  public function driver():ASRailsDriver {
    return m_driver;
  }
  
  public function addCommand(command:ASRailsCommandDispatcher) {
    m_commands.push(command);
  }
  
  public function executeCommands() {
    for (var i:Number = 0;i<m_commands.length;i++) {
      m_commands[i].dispatch(this);
    }
  }
  
  public function addComponent(component:ASRailsComponentDefinition) {
    m_components.push(component);
  }
  
  public function updateFromComponent(component:ASRailsComponentDefinition) {
    for (var publishTo:String in component.publishes()) {
      var m_loadVars:LoadVars = new LoadVars();
      var self:ASRailsControllerScope = this;
      m_loadVars.onLoad = function(success:Boolean) {
        if (success) {
        } else {
        }
      };
      m_loadVars.load(updateUrl(publishTo, component.publishes()[publishTo]));
    }
  }
  
  public function viewUrl():String {
    return m_url+"/"+m_url;
  }
  
  public function updateUrl(publishTo:String, params:Object):String {
    var url:String = "/"+m_url+"/"+publishTo;
    var paramString:String = publishedParams(params).join("&");
    if (paramString != null && paramString.length > 0) {
      url += "?"+paramString;
    }
    return url;
  }
  
  private function publishedParams(params:Object):Array {
    var result:Array = new Array();
    for (var name:String in params) {
      result.push(processPublishedParam(name, params[name]));
    }
    return result;
  }
  
  public function processPublishedParam(param, dynamicCommand):String {
    return param+"="+dynamicCommand.dispatch(this);
  }
  
  public function getComponentByName(name):ASRailsComponentDefinition {
    for(var i:Number = 0;i<m_components.length;i++) {
      if (m_components[i].name() == name) {
        return m_components[i];
      }
    }
    return null;
  }
  
  public function resolveNameToObject(name:String):Object {
    if (name == "application") {
      return m_driver.application();
    }
    for(var i:Number = 0;i<m_components.length;i++) {
      if (m_components[i].name() == name) {
        return m_components[i].widget();
      }
    }
  }
}
