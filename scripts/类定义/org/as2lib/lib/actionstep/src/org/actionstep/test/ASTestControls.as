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

import org.actionstep.*;
import org.actionstep.test.*;
import org.actionstep.constants.*;

class org.actionstep.test.ASTestControls {
  
  public static function test() {
    var triggerButton:NSButton;
    var actionButton:NSButton;
    var window1:NSWindow;
    var window2:NSWindow;
    var view1:NSView;
    var view2:NSView;
    var textField:NSTextField;
    var textField2:NSTextField;
    var box:NSBox;
    
    var target:Object = new Object();
    target.trigger = function(button) {
      trace(button.state());
    };
    target.move = function(button) {
      if (view1.window() == window1) {
        window2.setContentView(view1);
        //window1.setContentView(view2);
      } else {
        window1.setContentView(view1);
        //window2.setContentView(view2);
      }
    };
    target.bam = function(editfield) {
      trace(editfield.stringValue());
      trace(window1.firstResponder());
    };
    
    var app:NSApplication = NSApplication.sharedApplication();
    window1 = (new NSWindow()).initWithContentRectSwf(new NSRect(0,0,250,500));
    //window1 = (new NSWindow()).initWithContentRect(new NSRect(0,0,250,500));
    window2 = (new NSWindow()).initWithContentRect(new NSRect(251,0,250,500));
    
    view1 = (new ASTestView()).initWithFrame(new NSRect(0,0,250,500));
    view2 = (new ASTestView()).initWithFrame(new NSRect(0,0,250,500));
    
    box = (new NSBox()).initWithFrame(new NSRect(10,10,160,100));
    //box.setBorderType(NSBorderType.NSLineBorder);
    var boxFont:NSFont = NSFont.fontWithNameSize("Arial", 12);
    boxFont.setBold(true);
    box.setTitleFont(boxFont);
    //box.setTitlePosition(NSTitlePosition.NSAboveTop);
    box.setTitle("button");
    view2.addSubview(box);
    
    triggerButton = (new NSButton()).initWithFrame(new NSRect(10,80,70,30));
    triggerButton.setTitle("Press");
    triggerButton.setButtonType(NSButtonType.NSPushOnPushOffButton);
    actionButton = (new NSButton()).initWithFrame(new NSRect(10,120,150,28));
    actionButton.setTitle("LOGIN");
    
    var tv:Object = new Object();
    
    textField = (new NSTextField()).initWithFrame(new NSRect(10,160,120,30));
    textField.setDelegate(tv);
    
    
    textField2 = (new NSTextField()).initWithFrame(new NSRect(10,200,120,30));
    textField2.setDrawsBackground(false);
    textField2.setStringValue("My String");
    textField2.setEditable(false);
    textField2.setSelectable(false);
    
    window1.setInitialFirstResponder(textField);
    textField.setNextKeyView(triggerButton);
    textField.setTarget(target);
    textField.setAction("bam");
    triggerButton.setNextKeyView(actionButton);
    actionButton.setNextKeyView(textField);
    
    
    //box.setContentView(triggerButton);
    view1.addSubview(triggerButton);
    view1.addSubview(actionButton);
    view1.addSubview(textField);
    view1.addSubview(textField2);
    
    triggerButton.setTarget(target);
    triggerButton.setAction("trigger");
    
    actionButton.setTarget(target);
    actionButton.setAction("move");
    window1.setContentView(view1);
    window2.setContentView(view2);
    app.run();
  }

}
