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
//import org.actionstep.constants.*;

class org.actionstep.test.ASTestKeyEvents {

  public static function test() {
    var window1:NSWindow;
    var window2:NSWindow;
    var view1:NSView;
    var view2:NSView;
    var textField1:NSTextField;
    var textField2:NSTextField;
    var button:NSButton;

    var textField3:NSTextField;
    var textField4:NSTextField;
    var button2:NSButton;

    var app:NSApplication = NSApplication.sharedApplication();
    window1 = (new NSWindow()).initWithContentRectStyleMask(new NSRect(10,25,250,250), NSWindow.NSTitledWindowMask  | NSWindow.NSResizableWindowMask);
    window2 = (new NSWindow()).initWithContentRectStyleMask(new NSRect(262,25,250,250), NSWindow.NSTitledWindowMask  | NSWindow.NSResizableWindowMask);

    view1 = (new ASTestView()).initWithFrame(new NSRect(0,0,250,250));
    view2 = (new ASTestView()).initWithFrame(new NSRect(0,0,250,250));

    textField1 = (new NSTextField()).initWithFrame(new NSRect(10,20,120,30));
    textField2 = (new NSTextField()).initWithFrame(new NSRect(10,60,120,30));
    button = (new NSButton()).initWithFrame(new NSRect(10,100,70,30));
    button.setTitle("Submit");

    textField1.setNextKeyView(textField2);
    textField2.setNextKeyView(button);
    button.setNextKeyView(textField1);

    textField3 = (new NSTextField()).initWithFrame(new NSRect(10,20,120,30));
    textField4 = (new NSTextField()).initWithFrame(new NSRect(10,60,120,30));
    button2 = (new NSButton()).initWithFrame(new NSRect(10,100,70,30));
    button2.setTitle("Submit 2");

    textField3.setNextKeyView(textField4);
    textField4.setNextKeyView(button2);
    button2.setNextKeyView(textField3);

    
    var o:Object = new Object();
    o.click = function(b:NSButton) {
      trace("Clicked");
    };
    
    button.setTarget(o);
    button.setAction("click");

    view1.addSubview(textField1);
    view1.addSubview(textField2);
    view1.addSubview(button);

    view2.addSubview(textField3);
    view2.addSubview(textField4);
    view2.addSubview(button2);


    window1.setContentView(view1);
    window1.setInitialFirstResponder(textField1);
    window2.setContentView(view2);
    app.run();
  }

}
