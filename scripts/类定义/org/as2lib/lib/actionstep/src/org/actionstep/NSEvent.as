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
 
import org.actionstep.NSObject;
import org.actionstep.NSPoint;
import org.actionstep.NSView;
import org.actionstep.NSWindow;
import org.actionstep.NSTimer;

import org.actionstep.ASEventMonitor;

class org.actionstep.NSEvent extends NSObject {
  public static var NSLeftMouseDown:Number = 0;
  public static var NSLeftMouseUp:Number = 1;
  public static var NSRightMouseDown:Number = 2;
  public static var NSRightMouseUp:Number = 3;
  public static var NSOtherMouseDown:Number = 4;
  public static var NSOtherMouseUp:Number = 5;
  public static var NSMouseMoved:Number = 6;
  public static var NSLeftMouseDragged:Number = 7;
  public static var NSRightMouseDragged:Number = 8;
  public static var NSOtherMouseDragged:Number = 9;
  public static var NSMouseEntered:Number = 10;
  public static var NSMouseExited:Number = 11;
  public static var NSCursorUpdate:Number = 12;
  public static var NSKeyDown:Number = 13;
  public static var NSKeyUp:Number = 14;
  public static var NSFlagsChanged:Number = 15;
  public static var NSAppKitDefined:Number = 16;
  public static var NSSystemDefined:Number = 17;
  public static var NSApplicationDefined:Number = 18;
  public static var NSPeriodic:Number = 19;
  public static var NSScrollWheel:Number = 20;

  public static var NSLeftMouseDownMask:Number = (1 << NSLeftMouseDown);
  public static var NSLeftMouseUpMask:Number = (1 << NSLeftMouseUp);  
  public static var NSRightMouseDownMask:Number = (1 << NSRightMouseDownMask);  
  public static var NSRightMouseUpMask:Number = (1 << NSRightMouseUp);  
  public static var NSOtherMouseDownMask:Number = (1 << NSOtherMouseDown);  
  public static var NSOtherMouseUpMask:Number = (1 << NSOtherMouseUp);  
  public static var NSMouseMovedMask:Number = (1 << NSMouseMoved);  
  public static var NSLeftMouseDraggedMask:Number = (1 << NSLeftMouseDragged);  
  public static var NSRightMouseDraggedMask:Number = (1 << NSRightMouseDragged);  
  public static var NSOtherMouseDraggedMask:Number = (1 << NSOtherMouseDragged);  
  public static var NSMouseEnteredMask:Number = (1 << NSMouseEntered);  
  public static var NSMouseExitedMask:Number = (1 << NSMouseExited);  
  public static var NSCursorUpdateMask:Number = (1 << NSCursorUpdate);  
  public static var NSKeyDownMask:Number = (1 << NSKeyDown);  
  public static var NSKeyUpMask:Number = (1 << NSKeyUp);  
  public static var NSFlagsChangedMask:Number = (1 << NSFlagsChanged);  
  public static var NSAppKitDefinedMask:Number = (1 << NSAppKitDefined);  
  public static var NSSystemDefinedMask:Number = (1 << NSSystemDefined);  
  public static var NSApplicationDefinedMask:Number = (1 << NSApplicationDefined);  
  public static var NSPeriodicMask:Number = (1 << NSPeriodic);  
  public static var NSScrollWheelMask:Number = (1 << NSScrollWheel);  
  public static var NSAnyEventMask:Number = 0xffffffff;

  public static var NSAlphaShiftKeyMask:Number = 1;
  public static var NSShiftKeyMask:Number = 2;
  public static var NSControlKeyMask:Number = 4;
  public static var NSAlternateKeyMask:Number = 8;
  public static var NSCommandKeyMask:Number = 16;
  public static var NSNumericPadKeyMask:Number = 32;
  public static var NSHelpKeyMask:Number = 64;
  public static var NSFunctionKeyMask:Number = 128;
  
  // Private instance variables
  public var context:Object;
  public var locationInWindow:NSPoint;
  public var modifierFlags:Number;
  public var timestamp:Number;
  public var type:Number;
  public var view:NSView;
  public var window:NSWindow;
  public var windowNumber:Number;
  public var characters:String;
  public var charactersIgnoringModifiers:String;
  public var isARepeat:Boolean;
  public var keyCode:Number;
  public var mouseLocation:NSPoint;
  public var buttonNumber:Number;
  public var clickCount:Number;
  public var pressure:Number;
  public var eventNumber:Number;
  public var trackingNumber:Number;
  public var userData:Object;
  public var data1:Object;
  public var data2:Object;
  public var subtype:Number;
  public var deltaX:Number;
  public var deltaY:Number;
  public var deltaZ:Number;

  // static singleton instance
  
  private static var g_instance:NSEvent = (new NSEvent()).init();
  private static var g_periodicTimer:NSTimer;
  
  // static constructors
  
  public static function keyEventWithType(type:Number, location:NSPoint, modifierFlags:Number, 
                                          timestamp:Number, window:NSWindow, context:Object, 
                                          characters:String, charactersIgnoringModifiers:String, 
                                          isARepeat:Boolean, keyCode:Number):NSEvent {
    g_instance.type = type;
    g_instance.mouseLocation = location;
    g_instance.modifierFlags = modifierFlags;
    g_instance.timestamp = timestamp;
    g_instance.window = window;
    g_instance.windowNumber = window.windowNumber();
    g_instance.context = context;
    g_instance.characters = characters;
    g_instance.charactersIgnoringModifiers = charactersIgnoringModifiers;
    g_instance.isARepeat = isARepeat;
    g_instance.keyCode = keyCode;
    
    // Clear our unused data
    g_instance.locationInWindow = null;
    g_instance.buttonNumber = 0;
    g_instance.clickCount = 0;
    g_instance.pressure = 0;
    g_instance.eventNumber = -1;
    g_instance.trackingNumber = 0;
    g_instance.userData = null;
    g_instance.data1 = null;
    g_instance.data2 = null;
    g_instance.subtype = 0;
    g_instance.deltaX = 0;
    g_instance.deltaY = 0;
    g_instance.deltaZ = 0;
    
    return g_instance;
  }
  
  public static function enterExitEventType(type:Number, location:NSPoint, modifierFlags:Number, 
                                            timestamp:Number, view:NSView, context:Object,
                                            eventNumber:Number, trackingNumber:Number, userData:Object):NSEvent {
    g_instance.type = type;
    g_instance.mouseLocation = location;
    g_instance.modifierFlags = modifierFlags;
    g_instance.timestamp = timestamp;
    g_instance.view = view;
    g_instance.window = view.window();
    g_instance.windowNumber =  g_instance.window.windowNumber();
    g_instance.context = context;
    g_instance.eventNumber = eventNumber;
    g_instance.trackingNumber = trackingNumber;
    g_instance.userData = userData;

    // Clear our unused data
    g_instance.characters = null;
    g_instance.charactersIgnoringModifiers = null;
    g_instance.isARepeat = false;
    g_instance.keyCode = 0;
    g_instance.locationInWindow = null;
    g_instance.buttonNumber = 0;
    g_instance.clickCount = 0;
    g_instance.pressure = 0;
    g_instance.data1 = null;
    g_instance.data2 = null;
    g_instance.subtype = 0;
    g_instance.deltaX = 0;
    g_instance.deltaY = 0;
    g_instance.deltaZ = 0;
    
    return g_instance;
  }
  
  public static function mouseEventWithType(type:Number, location:NSPoint, modifierFlags:Number, 
                                            timestamp:Number, view:NSView, context:Object,
                                            eventNumber:Number, clickCount:Number, pressure:Number):NSEvent {
    g_instance.type = type;
    g_instance.mouseLocation = location;
    g_instance.modifierFlags = modifierFlags;
    g_instance.timestamp = timestamp;
    g_instance.view = view;
    g_instance.window = view.window();
    g_instance.windowNumber =  g_instance.window.windowNumber();
    g_instance.context = context;
    g_instance.eventNumber = eventNumber;
    g_instance.clickCount = clickCount;
    g_instance.pressure = pressure;
    
    // Clear our unused data
    g_instance.characters = null;
    g_instance.charactersIgnoringModifiers = null;
    g_instance.isARepeat = false;
    g_instance.keyCode = 0;
    g_instance.locationInWindow = null;
    g_instance.buttonNumber = 0;
    g_instance.trackingNumber = 0;
    g_instance.userData = null;
    g_instance.data1 = null;
    g_instance.data2 = null;
    g_instance.subtype = 0;
    g_instance.deltaX = 0;
    g_instance.deltaY = 0;
    g_instance.deltaZ = 0;
    
    return g_instance;
  }

  public static function otherEventWithType(type:Number, location:NSPoint, modifierFlags:Number, 
                                            timestamp:Number, view:NSView, context:Object,
                                            subtype:Number, data1:Object, data2:Object):NSEvent {
    g_instance.type = type;
    g_instance.mouseLocation = location;
    g_instance.modifierFlags = modifierFlags;
    g_instance.timestamp = timestamp;
    g_instance.view = view;
    g_instance.window = view.window();
    g_instance.windowNumber =  g_instance.window.windowNumber();
    g_instance.context = context;
    g_instance.subtype = subtype;
    g_instance.data1 = data1;
    g_instance.data2 = data2;
    
    // Clear our unused data
    g_instance.characters = null;
    g_instance.charactersIgnoringModifiers = null;
    g_instance.isARepeat = false;
    g_instance.keyCode = 0;
    g_instance.locationInWindow = null;
    g_instance.buttonNumber = 0;
    g_instance.clickCount = 0;
    g_instance.pressure = 0;
    g_instance.eventNumber = -1;
    g_instance.trackingNumber = 0;
    g_instance.userData = null;
    g_instance.deltaX = 0;
    g_instance.deltaY = 0;
    g_instance.deltaZ = 0;
    
    return g_instance;
  }
  
  public static function startPeriodicEventsAfterDelayWithPeriod(delay:Number, period:Number) {
    g_periodicTimer = new NSTimer();
    var startDate:Date = new Date();
    startDate.setTime(startDate.getTime()+(delay*1000));
    g_periodicTimer.initWithFireDateIntervalTargetSelectorUserInfoRepeats(
      startDate, period, ASEventMonitor.instance(), "postPeriodicEvent", {}, true);
  }
  
  public static function stopPeriodicEvents() {
    if (g_periodicTimer != null) {
      g_periodicTimer.invalidate();
      g_periodicTimer = null;
    }
  }
  
  private function NSEvent() {
  }
  
  private function init():NSEvent {
    super.init();
    return this;
  }
  
  public function description():String {
    return "NSEvent(type="+type+",mouseLocation="+mouseLocation+")";
  }
  
  public function matchesMask(mask:Number):Boolean {
    return (((mask >> type) & 1) == 1);
  }
  
  /*  
  
  // Getting general event information
  
  public function get context():Object {
    return m_context;
  }
  
  public function set context(value:Object) {
    m_context = value;
  }
  
  public function get locationInWindow():NSPoint {
    return m_locationInWindow;
  }
  
  public function set locationInWindow(value:NSPoint) {
    m_locationInWindow = value;
  }
  
  public function get modifierFlags():Number {
    return m_modifierFlags;
  }
  
  public function set modifierFlags(value:Number) {
    m_modifierFlags = value;
  }
  
  public function get timestamp():Number {
    return m_timestamp;
  }
  
  public function set timestamp(value:Number) {
    m_timestamp = value;
  }
  
  public function get type():Number {
    return m_type;
  }
  
  public function set type(value:Number) {
    m_type = value;
  }
  
  public function get window():NSWindow {
    return null;
  }
  
  public function get windowNumber():Number {
    return m_windowNumber;
  }
  
  public function set windowNumber(value:Number) {
    m_windowNumber = value;
  }
  
  // Getting key event information
  
  public function get characters():String {
    return m_characters;
  }
  
  public function set characters(value:String) {
    m_characters = value;
  }
  
  public function get charactersIgnoringModifiers():String {
    return m_charactersIgnoringModifiers;
  }
  
  public function set charactersIgnoringModifiers(value:String) {
    m_charactersIgnoringModifiers = value;
  }
  
  public function get isARepeat():Boolean {
    return m_isARepeat;
  }
  
  public function set isARepeat(value:Boolean) {
    m_isARepeat = value;
  }
  
  public function get keyCode():Number {
    return m_keyCode;
  }
  
  public function set keyCode(value:Number) {
    m_keyCode = value;
  }
  
  // Getting mouse event information
  
  public function get mouseLocation():NSPoint {
    return new NSPoint(_root._xmouse, _root._ymouse);
  }
  
  public function get buttonNumber():Number {
    return m_buttonNumber;
  }
  
  public function set buttonNumber(value:Number) {
    m_buttonNumber = value;
  }
  
  public function get clickCount():Number {
    return m_clickCount;
  }
  
  public function set clickCount(value:Number) {
    m_clickCount = value;
  }
  
  public function get pressure():Number {
    return m_pressure;
  }
  
  public function set pressure(value:Number) {
    m_pressure = value;
  }
  
  // Getting tracking-rectangle event information
  
  public function get eventNumber():Number {
    return m_eventNumber;
  }
  
  public function set eventNumber(value:Number) {
    m_eventNumber = value;
  }
  
  public function get trackingNumber():Number {
    return m_trackingNumber;
  }
  
  public function set trackingNumber(value:Number) {
    m_trackingNumber = value;
  }
  
  public function get userData():Object {
    return m_userData;
  }
  
  public function set userData(value:Object) {
    m_userData = value;
  }
  
  // Getting custom event information
  
  public function get data1():Object {
    return m_data1;
  }
  
  public function set data1(value:Object) {
    m_data1 = value;
  }
  
  public function get data2():Object {
    return m_data2;
  }
  
  public function set data2(value:Object) {
    m_data2 = value;
  }
  
  public function get subtype():Number {
    return m_subtype;
  }
  
  public function set subtype(value:Number) {
    m_subtype = value;
  }
  
  // Getting scroll wheel event information
  
  public function get deltaX():Number {
    return m_deltaX;
  }
  
  public function set deltaX(value:Number) {
    m_deltaX = value;
  }
  
  public function get deltaY():Number {
    return m_deltaY;
  }
  
  public function set deltaY(value:Number) {
    m_deltaY = value;
  }
  
  public function get deltaZ():Number {
    return m_deltaZ;
  }
  
  public function set deltaZ(value:Number) {
    m_deltaZ = value;
  }
  */
  
}