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

class org.actionstep.test.ASTestScrollView {
  public static function test() {
    var app:NSApplication = NSApplication.sharedApplication();
    var window1:NSWindow = (new NSWindow()).initWithContentRect(new NSRect(0,0,500,500));
    
    var view:ASTestView = new ASTestView();
    view.initWithFrame(new NSRect(0, 0, 1024, 350));
    view.setBorderColor(new NSColor(0xff0000));
    view.addHeaderView();
    view.addCornerView();
    
    var grow:NSButton = (new NSButton()).initWithFrame(new NSRect(260,10,70,30));
    grow.setTitle("Grow!");
    var shrink:NSButton = (new NSButton()).initWithFrame(new NSRect(260,90,70,30));
    shrink.setTitle("Shrink!");
    
    var target:Object = new Object();
    target.shrink = function(button) {
      view.setFrameSize(new NSSize(200, 300));
    };
    target.grow = function(button) {
      view.setFrameSize(new NSSize(1024, 350));
    };    
    
    shrink.setTarget(target);
    shrink.setAction("shrink");
    grow.setTarget(target);
    grow.setAction("grow");    
    
    var scrollView:NSScrollView = (new NSScrollView()).initWithFrame(new NSRect(0,0,250,250));
    scrollView.setBorderType(NSBorderType.NSLineBorder);
    scrollView.setDocumentView(view);
    scrollView.setHasHorizontalScroller(true);
    scrollView.setHasVerticalScroller(true);
    
    var view2:ASTestView = new ASTestView();
    view2.initWithFrame(new NSRect(0, 0, 500,500));
    view2.addSubview(scrollView);
    view2.addSubview(grow);
    view2.addSubview(shrink);
    
    window1.setContentView(view2);
    app.run();
  }
}