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

import org.actionstep.NSForm;
import org.actionstep.NSApplication;
//import org.actionstep.NSView;
import org.actionstep.NSWindow;
import org.actionstep.NSRect;
import org.actionstep.NSTextField;
import org.actionstep.NSButton;
import org.actionstep.constants.NSTextAlignment;
import org.actionstep.NSColor;
import org.actionstep.test.ASTestView;

/**
 * Test class for NSForm
 *
 * @author Scott Hyndman
 */
class org.actionstep.test.ASTestForm 
{	
	public function ASTestForm()
	{
		
	}
	//******************************************************															 
	//*					  Properties					   *
	//******************************************************
	//******************************************************															 
	//*					 Public Methods					   *
	//******************************************************	
	//******************************************************															 
	//*					    Events						   *
	//******************************************************
	//******************************************************															 
	//*				    Protected Methods				   *
	//******************************************************
	//******************************************************															 
	//*					 Private Methods				   *
	//******************************************************
	//******************************************************															 
	//*			   Public Static Properties				   *
	//******************************************************
	//******************************************************															 
	//*				 Public Static Methods				   *
	//******************************************************	
	
	public static function test():Void
	{
		trace("application start");
		var txtLabel:NSTextField;
		var btnAdd:NSButton;
		var app:NSApplication = NSApplication.sharedApplication();
		var window:NSWindow = (new NSWindow()).initWithContentRect(new NSRect(0,0,500,500));
		var view:ASTestView = ASTestView((new ASTestView()).initWithFrame(new NSRect(0,0,500,500)));
		view.setBackgroundColor(new NSColor(0x995555));
		window.setContentView(view);
		
		//
		// Create form
		//
		var form:NSForm = NSForm((new NSForm()).initWithFrame(new NSRect(10, 40, 300, 400)));
		form.setEntryWidth(300);
		form.setInterlineSpacing(10);
		form.setTextAlignment(NSTextAlignment.NSRightTextAlignment);
		view.addSubview(form);
		
		//
		// Create test controls:
		//
		var controller:Object = new Object(); // Build controller.
		controller.addEntry = function()
		{
			trace("Adding form entry: " + txtLabel.stringValue());
			var cell = form.addEntry(txtLabel.stringValue());
			//cell.setStringValue("foo");
		};
		
		//
		// Label
		//
		txtLabel = (new NSTextField()).initWithFrame(new NSRect(10, 10, 100, 20));
		view.addSubview(txtLabel);
		
		//
		// Add button
		//
		btnAdd = (new NSButton()).initWithFrame(new NSRect(120, 10, 80, 20));
		btnAdd.setTitle("Add Entry");
		btnAdd.setTarget(controller);
		btnAdd.setAction("addEntry");
		
		view.addSubview(btnAdd);
		
		window.setInitialFirstResponder(txtLabel);
		txtLabel.setNextKeyView(btnAdd);
		btnAdd.setNextKeyView(form);
		form.setNextKeyView(txtLabel);
		
		//
		// Run app
		//
		app.run();
	}
}
