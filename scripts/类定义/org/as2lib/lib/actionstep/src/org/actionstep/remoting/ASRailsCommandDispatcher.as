import org.actionstep.remoting.*;

class org.actionstep.remoting.ASRailsCommandDispatcher  {
  
  private var m_variable:String;
  private var m_functionCalls:Array;
  private var m_component:ASRailsComponentDefinition;
  
  public function variable():String {
    return m_variable;
  }
  
  public function component():ASRailsComponentDefinition {
    return m_component;
  }
  
  public function setComponent(comp:ASRailsComponentDefinition) {
    m_component = comp;
  }
  
  public function ASRailsCommandDispatcher(node:XMLNode) {
    m_functionCalls = new Array();
    m_variable = node.attributes.variable;
    var func:XMLNode = node.firstChild;
    while(func != undefined) {
      var f:Object = {name : func.attributes.name, params : new Array()};
      var param:XMLNode = func.firstChild;
      while (param != undefined) {
        f.params.push(ASRailsDriver.parseObject(param));
        param = param.nextSibling;
      }
      m_functionCalls.push(f);
      func = func.nextSibling;
    }
  }
  
  public function dispatch(scope:ASRailsControllerScope) {
    var value:Object = m_variable == "this" ? m_component.widget() : scope.resolveNameToObject(m_variable);
    var tmp;
    for(var i:Number = 0;i < m_functionCalls.length;i++) {
     value.setCommandContext(this);
     tmp = value[m_functionCalls[i].name].apply(value, m_functionCalls[i].params);
     value.clearCommandContext();
     value = tmp;
    }
    return value;
  }
}