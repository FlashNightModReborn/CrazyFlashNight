import org.actionstep.remoting.ASRailsComponentDefinition;
import org.actionstep.remoting.ASRailsControllerScope;
import org.actionstep.remoting.ASRailsCommandDispatcher;
import org.actionstep.remoting.ASRailsApplication;
import org.actionstep.*;

class org.actionstep.remoting.ASRailsDriver {
  
  private var defaultURL:String;
  private var components:Array;
  private var m_app:NSApplication;
  private var m_appRunning:Boolean;
  private var m_application:ASRailsApplication;
  
  public function ASRailsDriver() {
    components = new Array();
    m_application = new ASRailsApplication(this);
    m_appRunning = false;
  }
  
  public function application():ASRailsApplication {
    return m_application;
  }
  
  public function connect() {
    var url:Object = parse_url();
    defaultURL = url.parameters.controller;
    if (defaultURL == undefined) {
      defaultURL = "window";
    }
    m_app = NSApplication.sharedApplication();
    loadComponentsFromURL(defaultURL, null);
  }
  
  public function loadComponentsFromURL(url:String, parent:ASRailsComponentDefinition) {
    // create a new XML object
    var xml:XML = new XML();

    // set the ignoreWhite property to true (default value is false)
    xml.ignoreWhite = true;

    // After loading is complete, start app or load ui elements
    var self:ASRailsDriver = this;
    var parentComponent:ASRailsComponentDefinition = parent;
    var scope:ASRailsControllerScope = new ASRailsControllerScope(this, url);
    xml.onLoad = function(success) {
      if (success) {
        self.parseComponents(scope, xml, parentComponent);
        if (!self.m_appRunning) {
          NSApplication.sharedApplication().run();
          self.m_appRunning = true;
        }
        scope.executeCommands();
      }
    };
    xml.load(scope.viewUrl());
  }
  
  public function parseComponents(scope:ASRailsControllerScope, xml, parent:ASRailsComponentDefinition) {
    var node:XMLNode = xml.firstChild;
    while(node != undefined) {
      switch(node.nodeName) {
        case "c":
          parseComponent(scope, node, parent).render();
        break;
        case "command":
          scope.addCommand(new ASRailsCommandDispatcher(node));
        break;
      }
      if (node.nodeName != "c") {
        return;
      } else {
      }
      node = node.nextSibling;
    }
    return; 
  }
  
  private function parseComponent(scope:ASRailsControllerScope, xml:XMLNode, parent:ASRailsComponentDefinition):ASRailsComponentDefinition {
    var comp:ASRailsComponentDefinition = new ASRailsComponentDefinition(scope, xml.attributes.k, xml.attributes.n);
    if (parent != null) {
      parent.subviews().push(comp);
      comp.setParent(parent);
    }
    var node:XMLNode = xml.firstChild;
    while (node != undefined) {
      switch(node.nodeName) {
        case "a":
          comp.attributes()[node.attributes.n] = parseObject(node.firstChild);
        break;
        case "r":
          loadComponentsFromURL(node.attributes.u, comp);
        break;
        case "p":
          parsePublishesTo(comp, node);
        break;
        case "c":
          parseComponent(scope, node, comp);
        break;
        case "command":
          var cmd:ASRailsCommandDispatcher = new ASRailsCommandDispatcher(node);
          cmd.setComponent(comp);
          scope.addCommand(cmd);
        break;
        
      }
      node = node.nextSibling;
    }
    return comp;
  }
  
  private function parsePublishesTo(comp:ASRailsComponentDefinition, node:XMLNode) {
    var meth:String = node.attributes.m;
    var publishes:Object = new Object();
    var anode:XMLNode = node.firstChild;
    while (anode != null) {
      publishes[anode.attributes.n] = parseObject(anode.firstChild);
      publishes[anode.attributes.n].setComponent(comp);
      anode = anode.nextSibling;
    }
    comp.publishes()[meth] = publishes;
  }
  
  public static function parseObject(node:XMLNode) {
    var tmp;
    switch(node.nodeName) {
      case "h":
        var result:Object = new Object();
        var anode:XMLNode = node.firstChild;
        var x:Number = 0;
        while(anode != null) {
          result[anode.attributes.k] = parseObject(anode.firstChild);
          anode = anode.nextSibling;
        }
        return result;
      break;
      case "a":
        var result:Array = new Array();
        var anode:XMLNode = node.firstChild;
        while(anode != null) {
          result.push(parseObject(anode));
          anode = anode.nextSibling;
        }
        return result;
      break;
      case "s":
        return node.firstChild.nodeValue;
      break;
      case "b":
        return Boolean(node.attributes.v);
      break;
      case "n":
        return Number(node.attributes.v);
      case "q":
        return null;
      case "command":
         return new ASRailsCommandDispatcher(node);
      break;
    }
  }
  
  private function parse_url() {
    var base:String = _global._url.split("?")[0];
    var paramlist:String = _global._url.split("?")[1];
    paramlist = paramlist.split("&");
    var params:Object = new Object();
    for(var i:Number = 0;i<paramlist.length;i++) {
      var pv:Array = paramlist[i].split("=");
      params[pv[0]]=pv[1];
    }
    var result:Object = new Object();
    result.base = base;
    result.parameters = params;
    return result;
  }


}
