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

import org.actionstep.*;
import org.actionstep.test.*;
import org.actionstep.constants.*;

class org.actionstep.test.ASTestPanel {
	public static var
	self = ASTestPanel,
	app:NSApplication = NSApplication.sharedApplication(),
	main:NSWindow, other:NSWindow,
	view1:ASTestView, view2:ASTestView,
	b1:NSButton, b2:NSButton, b3:NSButton,
	textField:NSTextField, textField2:NSTextField,
	alertArgs:Array;

	public static function test() {
		trace("app: "+app);
		main= (new NSWindow()).initWithContentRectStyleMask(new NSRect(50,50,250,250), NSWindow.NSTitledWindowMask);
		main.setTitle("Main");
		other = (new NSWindow()).initWithContentRectStyleMask(new NSRect(400,100,250,250), NSWindow.NSTitledWindowMask);
		other.setTitle("Some Other Window");

		view1 = ASTestView((new ASTestView()).initWithFrame(new NSRect(0,0,25,25)));
		view1.setBorderColor(new NSColor(0xFFF000));
		view2 = ASTestView((new ASTestView()).initWithFrame(new NSRect(0,0,250,250)));
		view2.setBorderColor(new NSColor(0xFF0000));

		b1 = (new NSButton()).initWithFrame(new NSRect(10,20,80,30));
		b1.setTitle("panel");
		b1.sendActionOn(NSEvent.NSLeftMouseUpMask);
		b1.setBezelStyle(NSBezelStyle.NSShadowlessSquareBezelStyle);
		b1.setTarget(self);
		b1.setAction("panel");

		b2 = (new NSButton()).initWithFrame(new NSRect(10,60,80,30));
		b2.setTitle("critical");
		b2.sendActionOn(NSEvent.NSLeftMouseUpMask);
		b2.setBezelStyle(NSBezelStyle.NSShadowlessSquareBezelStyle);
		b2.setTarget(self);
		b2.setAction("critical");

		b3 = (new NSButton()).initWithFrame(new NSRect(10,100,80,30));
		b3.setTitle("informational");
		b3.sendActionOn(NSEvent.NSLeftMouseUpMask);
		b3.setBezelStyle(NSBezelStyle.NSShadowlessSquareBezelStyle);
		b3.setTarget(self);
		b3.setAction("informational");

		textField = (new NSTextField()).initWithFrame(new NSRect(10,160,120,30));
		textField2 = (new NSTextField()).initWithFrame(new NSRect(10,160,120,30));

		view1.addSubview(b1);
		view1.addSubview(b2);
		view1.addSubview(b3);
		view1.addSubview(textField);

		view2.addSubview(textField2);

		main.setContentView(view1);
		other.setContentView(view2);

		main.makeMainWindow();

		app.run();

		alertArgs = [null,
		"A very long line of text...lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.",
		"OK","Cancel", "None", self, "done"];
	}

	public static function done(panel:ASAlertPanel, ret:Object) {
		if(ret==NSRunResponse.NSContinues)	return;
		var ans = ASUtils.findMatch([NSAlertReturn,NSRunResponse], ret);
		//trace("button clicked: "+ans.prop);
		if(!panel.isSheet()) {
			ASAlertPanel.NSRelease(panel);
		}
	}

	//look like NSObject
	public static function respondsToSelector(sel:String):Boolean {
		return self.hasOwnProperty(sel);
	}
	
	/**
	* The following are wrapper functions.
	*/
	
	public static function panel() {
		ASAlertPanel.NSRunAlert.apply(ASAlertPanel, alertArgs);
	}

	public static function critical() {
		ASAlertPanel.NSRunCriticalAlert.apply(ASAlertPanel, alertArgs);
	}

	public static function informational() {
		ASAlertPanel.NSRunInformationalAlert.apply(ASAlertPanel, alertArgs);
	}

	public static function toString():String {
		return "Test::ASTestPanel";
	}
}