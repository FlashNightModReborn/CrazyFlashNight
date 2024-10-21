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
 * 3) The name InfoEther, Inc. and Affinity Systems may not be used to endorse or promote products  
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

class org.actionstep.test.ASTestList 
{	
	public static function test():Void
	{
		var app:NSApplication = NSApplication.sharedApplication();
		var window:NSWindow = (new NSWindow()).initWithContentRectSwf(new NSRect(0,0,500,500));
		var view:NSView = (new NSView()).initWithFrame(new NSRect(0,0,500,500));
		var list:ASList = (new ASList()).initWithFrame(new NSRect(10, 10, 150, 200));
		list.setFont(NSFont.fontWithNameSizeEmbedded("Arial", 14, false));
		list.setFontColor(new NSColor(0x50545d));
		var labels:Array = new Array();
		var data:Array = new Array();
		for(var i:Number = 0;i<511;i++) {
		  labels[i] = "Test Item "+i;
		  data[i] = i;
		}
		var begin:Number = getTimer();
		list.addItemsWithLabelsData(labels, data);
		trace("elapsed seconds: "+(getTimer() - begin)/1000);
		view.addSubview(list);
		
		var o:Object = new Object();
		o.select = function() { 
		  list.selectItem(list.visibleItems()[100]);
		};
		
		var button:NSButton = (new NSButton()).initWithFrame(new NSRect(170,10,70,30));
		button.setTitle("Test");
		button.setTarget(o);
		button.setAction("select");
		view.addSubview(button);
		window.setContentView(view);
		app.run();
	}
}
