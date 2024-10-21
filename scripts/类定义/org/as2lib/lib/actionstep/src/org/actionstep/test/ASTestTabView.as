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
import org.actionstep.constants.*;
import org.actionstep.test.*;

class org.actionstep.test.ASTestTabView {
  public static function test() {
    var app:NSApplication = NSApplication.sharedApplication();
    var window1:NSWindow = (new NSWindow()).initWithContentRect(new NSRect(0,0,500,500));
    var tabView:NSTabView = new NSTabView();
    tabView.initWithFrame(new NSRect(10,10,400,400));
    
    // tabView.setTabViewType(org.actionstep.constants.NSTabViewType.NSNoTabsNoBorder);
    //tabView.setTabViewType(org.actionstep.constants.NSTabViewType.NSNoTabsLineBorder);

    var tabItem1:NSTabViewItem = (new NSTabViewItem()).initWithIdentifier(1);
    tabItem1.setLabel("This is a long tab");
    var tabItemView1:ASTestView = new ASTestView();
    tabItemView1.initWithFrame(new NSRect(0,0,10,10));
    tabItemView1.setBackgroundColor(new NSColor(0xffff00));
    tabItem1.setView(tabItemView1);
    
    var tabItem2:NSTabViewItem = (new NSTabViewItem()).initWithIdentifier(2);
    tabItem2.setLabel("Short tab");
    var tabItemView2:ASTestView = new ASTestView();
    tabItemView2.initWithFrame(new NSRect(0,0,10,10));
    tabItemView2.setBackgroundColor(new NSColor(0x00ff00));
    tabItem2.setView(tabItemView2);
    
    
    var view:ASTestView = new ASTestView();
    view.initWithFrame(new NSRect(0, 0, 1024, 350));
    view.setBorderColor(new NSColor(0xff0000));

    var scrollView:NSScrollView = (new NSScrollView()).initWithFrame(new NSRect(0,0,250,250));
    scrollView.setBorderType(NSBorderType.NSLineBorder);
    scrollView.setDocumentView(view);
    scrollView.setHasHorizontalScroller(true);
    scrollView.setHasVerticalScroller(true);
    scrollView.contentView().scrollToPoint(new NSPoint(0,100));
    tabItemView2.addSubview(scrollView);

    tabView.addTabViewItem(tabItem1);
    tabView.addTabViewItem(tabItem2);
    tabView.selectFirstTabViewItem(null);
    window1.setContentView(tabView);
    app.run();
  }
}