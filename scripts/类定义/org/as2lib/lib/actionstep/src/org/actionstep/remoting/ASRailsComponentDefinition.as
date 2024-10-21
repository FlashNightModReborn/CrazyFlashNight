import org.actionstep.*;
import org.actionstep.test.ASTestView;
import org.actionstep.remoting.ASRailsControllerScope;
//import org.actionstep.constants.*;

class org.actionstep.remoting.ASRailsComponentDefinition {
  
  private var m_name:String;
  private var m_className:String;
  private var m_attributes:Array;
  private var m_publishes:Object;
  private var m_parent:ASRailsComponentDefinition;
  private var m_subviews:Array;
  private var m_rendered:Boolean;
  private var m_widget:Object;
  private var m_scope:ASRailsControllerScope;

  public function ASRailsComponentDefinition(scope:ASRailsControllerScope, className:String, name:String) {
    this.m_scope = scope;
    scope.addComponent(this);
    this.m_className = className;
    this.m_name = name;
    this.m_attributes = new Array();
    this.m_publishes = new Object();
    this.m_subviews = new Array();
    this.m_rendered = false;
  }
  
  public function scope():ASRailsControllerScope {
    return m_scope;
  }
  
  public function name():String {
    return m_name;
  }
  
  public function className():String {
    return m_className;
  }
  
  public function attributes():Array {
    return m_attributes;
  }
  
  public function subviews():Array {
    return m_subviews;
  }
  
  public function publishes():Object {
    return m_publishes;
  }
  
  public function parent():ASRailsComponentDefinition {
    return m_parent;
  }
  
  public function setParent(parent:ASRailsComponentDefinition) {
    m_parent = parent;
  }
  
  private function action(widget) {
    m_scope.updateFromComponent(this);
  }
  
  public function render() {
    if (m_rendered) {
      return;
    }
    var attribute;
    switch(m_className) {
      case "NSWindow":
        m_widget = new NSWindow();
        attribute = m_attributes["contentRect"];
        if (attribute) {
          m_widget.initWithContentRectStyleMask(new NSRect(attribute.x, attribute.y, attribute.width, attribute.height), 
            NSWindow.NSTitledWindowMask | NSWindow.NSResizableWindowMask);
        } else {
          m_widget.initWithContentRectStyleMask(new NSRect(30, 30, 300, 300), 
            NSWindow.NSTitledWindowMask | NSWindow.NSResizableWindowMask);
        }
        attribute = m_attributes["title"];
        if (attribute) {
          m_widget.setTitle(attribute);
        }
        m_widget.setContentView((new ASTestView()).initWithFrame(new NSRect(0,0,0,0)));
        m_widget = m_widget.contentView();
      break;
      case "NSView":
        m_widget = new ASTestView();
        attribute = m_attributes["rect"];
        if (attribute) {
          m_widget.initWithFrame(new NSRect(attribute.x, attribute.y, attribute.width, attribute.height));
        }
        attribute = m_attributes["backgroundColor"];
        if (attribute) {
          m_widget.setBackgroundColor(new NSColor(attribute));
        }
        m_parent.widget().addSubview(m_widget);
      break;
      case "NSButton":
        m_widget = new NSButton();
        attribute = m_attributes["rect"];
        if (attribute) {
          m_widget.initWithFrame(new NSRect(attribute.x, attribute.y, attribute.width, attribute.height));
        }
        attribute = m_attributes["title"];
        if (attribute) {
          m_widget.setTitle(attribute);
        }
        for (var x:Object in m_publishes) {
          m_widget.setTarget(this);
          m_widget.setAction("action");
        }
        m_parent.widget().addSubview(m_widget);
      break;
      case "ASTextEditor":
        m_widget = new ASTextEditor();
        attribute = m_attributes["rect"];
        if (attribute) {
          m_widget.initWithFrame(new NSRect(attribute.x, attribute.y, attribute.width, attribute.height));
        }
        attribute = m_attributes["hScroller"];
        if (attribute) {
          m_widget.setHasHorizontalScroller(attribute);
        }
        attribute = m_attributes["vScroller"];
        if (attribute) {
          m_widget.setHasVerticalScroller(attribute);
        }
        attribute = m_attributes["text"];
        if (attribute) {
          m_widget.setString(attribute);
        }
        m_parent.widget().addSubview(m_widget);
        break;
      case "ASList":
        m_widget = new ASList();
        attribute = m_attributes["rect"];
        if (attribute) {
          m_widget.initWithFrame(new NSRect(attribute.x, attribute.y, attribute.width, attribute.height));
        }
        attribute = m_attributes["items"];
        if (attribute) {
          var labels:Array = new Array();
          var datum:Array = new Array();
          for(var key:Object in attribute) {
            labels.push(key);
            datum.push(attribute[key]);
          }
          m_widget.addItemsWithLabelsData(labels, datum);
        }
        m_parent.widget().addSubview(m_widget);
      break;
    }
    for(var i:Number = 0;i<m_subviews.length;i++) {
      m_subviews[i].render();
    }
  }
  
  public function toString():String {
    return m_className+"_"+m_name;
  }
  
  public function widget() {
    return m_widget;
  }
  
}