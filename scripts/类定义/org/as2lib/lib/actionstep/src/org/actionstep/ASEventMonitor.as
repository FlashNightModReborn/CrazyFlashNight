/*
 * Copyright (c) 2005, InfoEther, Inc.
 * All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without modification, 
 * are permitted provided that the following conditions are met:
 * 
 * 1) Redistributions of source code must retain the above copyright notice, 
 *    this list of conditions and the following disclaimer.
 *  
 * 2) Redistributions in binary form must reproduce the above copyright notice, 
 *    this list of conditions and the following disclaimer in the documentation 
 *    and/or other materials provided with the distribution. 
 * 
 * 3) The name InfoEther, Inc. may not be used to endorse or promote products 
 *    derived from this software without specific prior written permission. 
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" 
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE 
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE 
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE 
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) 
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE 
 * POSSIBILITY OF SUCH DAMAGE.
 */
 
 
import org.actionstep.NSEvent;
import org.actionstep.NSApplication;
import org.actionstep.NSPoint;

class org.actionstep.ASEventMonitor {
  
  private static var g_instance:ASEventMonitor;
  
  private var m_app:NSApplication;
  private var m_mouseTrackingClip:MovieClip;
  private var m_currentMouseTargetPath:String;
  private var m_eventCounter:Number;
  private var m_filter:Object;
  private var m_index:Number;
  private var m_multiClickSpeed:Number;
  
  private var m_lastMouseDownTime:Number;
  private var m_lastMouseDownEvent:NSEvent;
  
  private var m_keyTracker:Object;
  
  private var m_timeOffset:Number;
  
  public static function instance():ASEventMonitor {
    if (g_instance == null) {
      g_instance = new ASEventMonitor();
    }
    return g_instance;
  }
  
  /**
   * Returns the clip used to track mouse movement. This clip is also used
   * to draw cursors.
   */
  public function mouseTrackingClip():MovieClip {
    return m_mouseTrackingClip;
  }
  
  public function setMouseEventFilter(filter:Object) {
    m_filter = filter;
  }
  
  public function multiClickSpeed():Number {
    return m_multiClickSpeed;
  }
  
  public function setMultiClickSpeed(value:Number) {
    m_multiClickSpeed = value;
  }
  
  private function ASEventMonitor() {
    m_app = NSApplication.sharedApplication();
    m_multiClickSpeed = 500; // OS X default
    m_mouseTrackingClip = null;
    m_currentMouseTargetPath = "";
    m_eventCounter = 1;
    m_filter = null;
    m_index = _root._target.length;
    if (m_index == 1) m_index = 0;
    m_lastMouseDownTime = 0;
    m_timeOffset = (new Date()).getTime() - getTimer();
  }
  
  public function trackMouseEvents() {
    if (m_mouseTrackingClip != null) { //Already tracking
      return;
    }
    var self:ASEventMonitor = this;
    var mouseTrackingClip:MovieClip = _root.createEmptyMovieClip("mouseTrackingClip", 10000);
    m_mouseTrackingClip = mouseTrackingClip;
    m_mouseTrackingClip.startDrag(false);
    m_mouseTrackingClip.onMouseDown = function() {
      self.mouseDown( mouseTrackingClip._droptarget );
    };    
    m_mouseTrackingClip.onMouseUp = function() {
      self.mouseUp( mouseTrackingClip._droptarget );
    };    
    m_mouseTrackingClip.onMouseMove = function() {
      self.mouseMove( mouseTrackingClip._droptarget );
    };
  }
  
  public function trackKeyboardEvents() {
    if (m_keyTracker != null) { //Already tracking
      return;
    }
    var self:ASEventMonitor = this;
    m_keyTracker = new Object();
    m_keyTracker.onKeyDown = function() {
      self.keyDown();
    };
    m_keyTracker.onKeyUp = function() {
      self.keyUp();
    };
    Key.addListener(m_keyTracker);
  }
  
  private var m_lastKeyDown:Number;
  
  public function keyDown() {
    var event:NSEvent = NSEvent.keyEventWithType(NSEvent.NSKeyDown, new NSPoint(_root._xmouse, _root._ymouse),
       buildModifierFlags(), m_timeOffset+getTimer(), null /* window */, null /*contact*/, String.fromCharCode(Key.getAscii()),
       String.fromCharCode(Key.getAscii()), (m_lastKeyDown == Key.getCode()), Key.getCode());
    m_lastKeyDown = Key.getCode();
    m_app.sendEvent(event);
  }
  
  public function keyUp() {
    if (m_lastKeyDown == Key.getCode()) {
      m_lastKeyDown = 0;
    }
    var event:NSEvent = NSEvent.keyEventWithType(NSEvent.NSKeyUp, new NSPoint(_root._xmouse, _root._ymouse),
       buildModifierFlags(), m_timeOffset+getTimer(), null /* window */, null /*contact*/, String.fromCharCode(Key.getAscii()),
       String.fromCharCode(Key.getAscii()), (m_lastKeyDown == Key.getCode()), Key.getCode());
    m_lastKeyDown = Key.getCode();
    m_app.sendEvent(event);
  }
  
  public function postPeriodicEvent() {
    var modifierFlags:Number = buildModifierFlags();
    var event:NSEvent = NSEvent.otherEventWithType(NSEvent.NSPeriodic, new NSPoint(_root._xmouse, _root._ymouse), 
         modifierFlags, m_timeOffset+getTimer(), eval(m_mouseTrackingClip._dropTarget).view, 
         null /* context*/, 0 /*subType */, null /*data1 */, null /*data 2*/);
    m_app.sendEvent(event);
  }
  
  public function mouseDown(targetPath:String) {
    if (m_index > 0) {
      targetPath = targetPath.slice(m_index);
    }
    
    var x:Number = _root._xmouse;
    var y:Number = _root._ymouse;
    
    if ((getTimer() - m_lastMouseDownTime) < m_multiClickSpeed &&
        (Math.abs(x -  m_lastMouseDownEvent.mouseLocation.x)) < 10 &&
        (Math.abs(y -  m_lastMouseDownEvent.mouseLocation.y)) < 10) {
      m_lastMouseDownEvent.clickCount++;
      m_lastMouseDownTime = getTimer();
      m_app.sendEvent(m_lastMouseDownEvent);
      return;
    }
    
    var modifierFlags:Number = buildModifierFlags();

    m_lastMouseDownEvent = NSEvent(NSEvent.mouseEventWithType(NSEvent.NSLeftMouseDown, new NSPoint(x, y), 
         modifierFlags, m_timeOffset+getTimer(), eval(targetPath).view, 
         null /* context */, m_eventCounter++, 1 /*click count*/, 0).memberwiseClone());
    m_lastMouseDownTime = getTimer();
    m_app.sendEvent(m_lastMouseDownEvent);
  }
  
  public function mouseUp(targetPath:String) {
    if (m_index > 0) {
      targetPath = targetPath.slice(m_index);
    }
    var modifierFlags:Number = buildModifierFlags();

    var event:NSEvent = NSEvent.mouseEventWithType(NSEvent.NSLeftMouseUp, new NSPoint(_root._xmouse, _root._ymouse), 
      modifierFlags, m_timeOffset+getTimer(), eval(targetPath).view,  null /* context */, m_eventCounter++, 
      1 /*click count*/, 0);
    m_app.sendEvent(event);
  }
  
  public function mouseMove(targetPath:String) {  
    if (m_index > 0) {
      targetPath = targetPath.slice(m_index);
    }
    var event:NSEvent;
    // MouseEnter/exit messages
    if (m_currentMouseTargetPath != targetPath) {
      if (m_currentMouseTargetPath != "") {
        event = NSEvent.enterExitEventType(NSEvent.NSMouseExited, new NSPoint(_root._xmouse, _root._ymouse), 
          buildModifierFlags() , m_timeOffset+getTimer(), eval(m_currentMouseTargetPath).view, null /* context */, 
          m_eventCounter++, 0/*trackingNumber:Number*/, null/*userData:Object*/);
        m_app.sendEvent(event);
      }
      m_currentMouseTargetPath = targetPath;
      if (m_currentMouseTargetPath != "") {
        event = NSEvent.enterExitEventType(NSEvent.NSMouseEntered, new NSPoint(_root._xmouse, _root._ymouse), 
          buildModifierFlags() , m_timeOffset+getTimer(), eval(targetPath).view, null /* context */, 
          m_eventCounter++, 0/*trackingNumber:Number*/, null/*userData:Object*/);
        m_app.sendEvent(event);
      }
    }
    event = NSEvent.mouseEventWithType(NSEvent.NSMouseMoved, new NSPoint(_root._xmouse, _root._ymouse), 
      buildModifierFlags(), m_timeOffset+getTimer(), eval(targetPath).view, null /* context */, 
      m_eventCounter++, 0/*clickCount:Number*/, 0/*pressure:Number*/);
    m_app.sendEvent(event);
  }
  
  /**
   * Builds the modifier flags for an event object based on keys pressed
   * at the time.
   */
  private function buildModifierFlags():Number {
    var flags:Number = 0;
    
    if (Key.isDown(Key.SHIFT)) {
      flags |= NSEvent.NSShiftKeyMask;
    }
    if (Key.isDown(Key.CONTROL)) {
      flags |= (System.capabilities.os == "MacOS") ? 
        NSEvent.NSCommandKeyMask : NSEvent.NSControlKeyMask;
    }
    if (Key.isDown(Key.ALT)) {
      flags |= NSEvent.NSAlternateKeyMask;
    }
    if (Key.isDown(112)) {
      flags |= NSEvent.NSHelpKeyMask;
    }
    if (Key.isDown(96) || // 0
      Key.isDown(97) ||   // 1
      Key.isDown(98) ||   // 2
      Key.isDown(99) ||   // 3
      Key.isDown(100) ||  // 4
      Key.isDown(101) ||  // 5
      Key.isDown(102) ||  // 6
      Key.isDown(103) ||  // 7
      Key.isDown(104) ||  // 8
      Key.isDown(105) ||  // 9
      Key.isDown(106) ||  // Multiply
      Key.isDown(107) ||  // Add
      Key.isDown(109) ||  // Subtract
      Key.isDown(110) ||  // Decimal
      Key.isDown(111) ||  // Divide
      Key.isDown(13))     // Enter
    {
    	flags |= NSEvent.NSNumericPadKeyMask;
    }
    
    //! I don't know what the NSAlphaShiftKeyMask or NSFunctionKeyMask
    return flags;     
  }
}