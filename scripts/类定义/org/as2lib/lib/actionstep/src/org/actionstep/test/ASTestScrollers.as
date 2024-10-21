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

class org.actionstep.test.ASTestScrollers {
  public static function test() {
    
    var testObject:Object = new Object();
    testObject.vscroller = function(scroller) {
      switch(scroller.hitPart()) {
        case NSScrollerPart.NSScrollerIncrementPage:
        case NSScrollerPart.NSScrollerIncrementLine:
          scroller.setFloatValue(scroller.floatValue() + .02);
          break;
        case NSScrollerPart.NSScrollerDecrementPage:
        case NSScrollerPart.NSScrollerDecrementLine:
          scroller.setFloatValue(scroller.floatValue() - .02);
          break;
      }
    };
    testObject.hscroller = function(scroller) {
      switch(scroller.hitPart()) {
        case NSScrollerPart.NSScrollerIncrementPage:
        case NSScrollerPart.NSScrollerIncrementLine:
          scroller.setFloatValue(scroller.floatValue() + .02);
          break;
        case NSScrollerPart.NSScrollerDecrementPage:
        case NSScrollerPart.NSScrollerDecrementLine:
          scroller.setFloatValue(scroller.floatValue() - .02);
          break;
      }
    };
    
    var app:NSApplication = NSApplication.sharedApplication();
    var window1:NSWindow = (new NSWindow()).initWithContentRect(new NSRect(0,0,250,250));
    
    var view:ASTestView = new ASTestView();
    view.initWithFrame(new NSRect(0,0,250,250));
    
    var vscroller:NSScroller = new NSScroller();
    vscroller.initWithFrame(new NSRect(180, 0, 20, 180));
    vscroller.setTarget(testObject);
    vscroller.setAction("vscroller");
    
    var hscroller:NSScroller = new NSScroller();
    hscroller.initWithFrame(new NSRect(0, 180, 180, 20));
    hscroller.setTarget(testObject);
    hscroller.setAction("hscroller");

    view.addSubview(vscroller);
    view.addSubview(hscroller);
    window1.setContentView(view);
    app.run();
  }
}