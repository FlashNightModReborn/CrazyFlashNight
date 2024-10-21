/*
 * Copyright (c) 2005, InfoEther, Inc.
 * All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without modification, 
 * are permitted provided that the following conditions are met:
 * 
 * 1) Redistributions of source code must retain the above copyright notice, 
 *		this list of conditions and the following disclaimer.
 *	
 * 2) Redistributions in binary form must reproduce the above copyright notice, 
 *		this list of conditions and the following disclaimer in the documentation 
 *		and/or other materials provided with the distribution. 
 * 
 * 3) The name InfoEther, Inc. may not be used to endorse or promote products 
 *		derived from this software without specific prior written permission. 
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
 
 //too lazy...*sigh*
import org.actionstep.*;
import org.actionstep.test.*;
import org.actionstep.constants.*;

/**
 * Below is for matrix options -- no longer applicable
 * Send if drag for cell
 * Restart delay process when moved back
 * Stop sending periodic when mouse up
 * Call callback with false if continueTrackingInView
 * Set highlight when mouseUp
 */

class org.actionstep.test.ASTestStepper {
	public static function test() {
		//note the commas
		var app:NSApplication = NSApplication.sharedApplication(),
		window1:NSWindow = (new NSWindow()).initWithContentRect(new NSRect(0,20,250,300)),
		//window2:NSWindow = (new NSWindow()).initWithContentRect(new NSRect(251,20,250,300)),
		view1:NSView = (new ASTestView()).initWithFrame(new NSRect(0,0,250,300));
		//view2:NSView = (new ASTestView()).initWithFrame(new NSRect(0,0,250,300)),
		
		//_global.$c=[];
		
		var testObject = new Object();
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
		testObject.check = function(loc) {
			var row = loc.row;
			var x=_global.$c;
			if(x[row])	x[row] = false;
			else x[row]=true;
			trace(row+": "+x[row]);
		};
		testObject.trigger = function() {
			trace("bam");
		};
		testObject.foo = function() {
			trace("step");
		};
		
		var step:NSStepper =(new NSStepper()).initWithFrame(new NSRect(20, 20, 100, 100));
		
		step.setMaxValue(10);
		step.setAction("foo");
		step.setTarget(testObject);
		
		var vscroller:NSScroller = new NSScroller();
		vscroller.initWithFrame(new NSRect(180, 0, 20, 180));
		vscroller.setTarget(testObject);
		vscroller.setAction("vscroller");
		
		var hscroller:NSScroller = new NSScroller();
		hscroller.initWithFrame(new NSRect(0, 180, 180, 20));
		hscroller.setTarget(testObject);
		hscroller.setAction("hscroller");
		
		var triggerButton:NSButton = (new NSButton()).initWithFrame(new NSRect(10,240,70,30));
		triggerButton.setTitle("Draw");
		triggerButton.sendActionOn(NSEvent.NSLeftMouseDownMask);
		triggerButton.setContinuous(true);
		triggerButton.setPeriodicDelayInterval(.3, .5);
		triggerButton.setBezelStyle(NSBezelStyle.NSShadowlessSquareBezelStyle);
		triggerButton.setAction("trigger");
		triggerButton.setTarget(testObject);
		
		view1.addSubview(triggerButton);
		view1.addSubview(vscroller);
		view1.addSubview(hscroller);		
		view1.addSubview(step);
		window1.setContentView(view1);
		
		//var cell:NSButtonCell = (new NSButtonCell()).initTextCell("test");
		//cell.setButtonType(NSButtonType.NSSwitchButton);
		//var matrix:NSMatrix = (new NSMatrix()).initWithFrameModePrototypeNumberOfRowsNumberOfColumns
		//	(new NSRect(10,10,70,200), NSMatrixMode.NSListModeMatrix,
		//	cell, 5, 1);
		
		//matrix.setBackgroundColor(new NSColor(0xFF0000));
		//matrix.setCellBackgroundColor(new NSColor(0xFFF000));
		//matrix.setIntercellSpacing(new NSSize(1, 1));
		//matrix.setAction("check");
		//matrix.setTarget(testObject);
		
		//view2.addSubview(matrix);
		//window2.setContentView(view2);
		
		app.run();
	}
}
