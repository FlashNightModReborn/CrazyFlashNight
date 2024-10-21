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

import org.actionstep.NSWindow;
import org.actionstep.NSEvent;
import org.actionstep.NSRect;

class org.actionstep.NSPanel extends NSWindow {
  private var m_isFloatingPanel:Boolean;
  private var m_worksWhenModal:Boolean;
  private var m_becomesKeyOnlyIfNeeded:Boolean;
  
  //Style Mask
  public static var NSUtilityWindowMask:Number = 16;
  public static var NSDocModalWindowMask:Number = 32;
  
  /*
  //
  // New alert interface of Mac OS X
  //
  public static function NSBeginAlertSheet
  (title:String, msg:String, defaultButton:String, alternateButton:String, otherButton:String, 
  docWindow:NSWindow, modalDelegate:Object, willEndSelector:String, didEndSelector:String, 
  contextInfo, msg:String):Void
  
  public static function NSBeginCriticalAlertSheet
  (title:String, msg:String, defaultButton:String, alternateButton:String, otherButton:String, 
  docWindow:NSWindow, modalDelegate:Object, willEndSelector:String, didEndSelector:String, 
  contextInfo, msg:String):Void
  
  public static function NSBeginInformationalAlertSheet
  (title:String, msg:String, defaultButton:String, alternateButton:String, otherButton:String, 
  docWindow:NSWindow, modalDelegate:Object, willEndSelector:String, didEndSelector:String, 
  contextInfo, msg:String):Void
  */
  
  public function NSPanel() {
    //init();
  }
  
  public function init():NSPanel {
    var style:Number =  NSTitledWindowMask;// | NSClosableWindowMask;
    initWithContentRectStyleMask(new NSRect(0, 0, 100, 100), style);
    
    //setReleasedWhenClosed(false);
    //setHidesOnDeactivate(true);
    //setExcludedFromWindowsMenu(true);
  
    //return initWithContentRectStyleMaskBackingDefer
    return this;
  }
  
  public function canBecomeKeyWindow():Boolean {
    return true;
  }
  
  public function canBecomeMainWindow():Boolean {
    return false;
  }
  
  /*
   * If we receive an escape, close.
   
  public function keyDown(theEvent:NSEvent) {
    if (
      ("\e" == theEvent.charactersIgnoringModifiers()) && 
      (styleMask & NSClosableWindowMask)  ==  NSClosableWindowMask)
      close();
    else
      super.keyDown(theEvent);
  }*/
  
  /*
   * Determining the Panel's Behavior
   */
  public function isFloatingPanel():Boolean {
    return m_isFloatingPanel;
  }
  
  public function setFloatingPanel(flag:Boolean):Void {
    if (m_isFloatingPanel != flag) {
      m_isFloatingPanel = flag;
      if (flag)
        setLevel(NSWindow.NSFloatingWindowLevel);
      else
        setLevel(NSWindow.NSNormalWindowLevel);
    }
  }
  
  public function worksWhenModal():Boolean {
    return m_worksWhenModal;
  }
  
  public function setWorksWhenModal(flag:Boolean):Void {
    m_worksWhenModal = flag;
  }
  
  public function becomesKeyOnlyIfNeeded():Boolean {
    return m_becomesKeyOnlyIfNeeded;
  }
  
  public function setBecomesKeyOnlyIfNeeded(flag:Boolean):Void {
    m_becomesKeyOnlyIfNeeded = flag;
  }

  public function sendEvent(theEvent:NSEvent):Void {
    __sendEventBecomesKeyOnlyIfNeeded(theEvent, m_becomesKeyOnlyIfNeeded);
  }
  
  public function description():String {
    return "NSPanel()";
  }
}