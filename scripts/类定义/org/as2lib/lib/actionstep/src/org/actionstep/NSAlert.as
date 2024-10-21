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

import org.actionstep.NSObject;
import org.actionstep.NSArray;
import org.actionstep.NSButton;
import org.actionstep.NSEvent;
import org.actionstep.NSWindow;
import org.actionstep.NSApplication;
import org.actionstep.NSRect;
import org.actionstep.ASAlertPanel;
import org.actionstep.constants.NSAlertStyle;
import org.actionstep.constants.NSAlertReturn;

/**
 * NSAlert displays a modal window to the user, and can contain text and icons.
 * The window displays a collection of buttons for the user to press. The alert
 * is dismissed after a button press has occurred.
 *
 * @author Ray Chuan
 */
class org.actionstep.NSAlert extends NSObject {
	private var m_buttons:NSArray;
	private var m_style:NSAlertStyle;
	private var m_msg:String;
	private var m_info:String;
	private var m_showsHelp:Boolean;
	private var m_helpAnchor:String;
	private var m_delegate:Object;
	private var m_app:NSApplication;
	private var m_sheet:ASAlertPanel;
	
	public static function alertWithMessageTextDefaultButtonAlternateButtonOtherButton
	(messageTitle:String, defaultButtonTitle:String, alternateButtonTitle:String, otherButtonTitle:String):NSAlert {
	  var alert:NSAlert = new NSAlert();
	
	  alert.setMessageText(messageTitle);
	
	  if (defaultButtonTitle != null) {
			alert.addButtonWithTitle(defaultButtonTitle);
		} else {
			alert.addButtonWithTitle("OK");
		}
	
	  if (alternateButtonTitle != null) {
			alert.addButtonWithTitle(alternateButtonTitle);
		}
	
	  if (otherButtonTitle != null) {
			alert.addButtonWithTitle(otherButtonTitle);
		}
	
	  return alert;
	}
	
	/**
	 * Initializes the default NSAlert with a style of NSAlertStyle.NSWarning.
	 */
	public function init():NSAlert {
		m_buttons = new NSArray();
		m_app = NSApplication.sharedApplication();
		m_style = NSAlertStyle.NSWarning;
		return this;
	}
	
	/**
	 * Sets the alerts title text.
	 */
	public function setInformativeText(infoText:String):Void {
		m_info = infoText;
	}
	
	/**
	 * Returns the alerts message text.
	 */
	public function informativeText():String {
		return m_info;
	}

	/**
	 * Sets the alerts title text.
	 */	
	public function setMessageText(messageText:String):Void {
		m_msg = messageText;
	}
	
	/**
	 * Returns the alerts title text.
	 */
	public function messageText():String {
		return m_msg;
	}
	
	//- (void)setIcon:(NSImage *)icon
	//- (NSImage *)icon
	
	/**
	 * Adds a button to alert labeled with aTitle, then returns it. The button
	 * is placed to the left side of the existing buttons.
	 *
	 * By default the first button is the default push button.
	 */
	public function addButtonWithTitle(aTitle:String):NSButton {
	  var button:NSButton = new NSButton();
	  button.initWithFrame(NSRect.ZeroRect);
	  var count:Number = m_buttons.count();
	  
	  button.setTitle(aTitle);
	  button.setTarget(this);
	  button.setAction("buttonAction");
	  
	  if (count == 0) {
			button.setTag(NSAlertReturn.NSFirstButton.value);
			button.setKeyEquivalent("\r");
		} else {
			button.setTag(NSAlertReturn.NSFirstButton.value + count);
			if (aTitle == "Cancel") {
				button.setKeyEquivalent("e");
			} else if (aTitle == "Don't Save") {
				button.setKeyEquivalent("D");
				button.setKeyEquivalentModifierMask(NSEvent.NSCommandKeyMask);
			}
		}

	  m_buttons.addObject(button);
	  return button;
	}
	
	/**
	 * Returns the alert's buttons.
	 */
	public function buttons():NSArray {
	  return m_buttons;
	}
	
	/**
	 * Sets whether the alert displays a help button. If TRUE, the help
	 * button is displayed.
	 *
	 * When the button is pressed, an alertShowsHelp method is called in the
	 * delegate. The method signiture is as follows:
	 * 	alertShowsHelp(alert:NSAlert):Boolean
	 *
	 * If the delegate returns FALSE, or delegate is null, the NSHelpManager is
	 * asked to show help, passed a null book and the anchor specified by
	 * setHelpAnchor.
	 */
	public function setShowsHelp(showsHelp:Boolean):Void {
	  m_showsHelp = showsHelp;
	}
	
	/**
	 * Returns TRUE if the alert has a help button, or FALSE if it doesn't.
	 *
	 * @see org.actionstep.NSAlert#setShowsHelp
	 */
	public function showsHelp():Boolean {
	  return m_showsHelp;
	}
	
	/**
	 * Sets the HTML text anchor sent to the NSHelpManager if showsHelp is TRUE
	 * and no delegate has been specified.
	 */
	public function setHelpAnchor(anchor:String):Void {
	  m_helpAnchor = anchor;
	}
	
	/**
	 * Returns the HTML text anchor sent to the NSHelpManager if showsHelp is
	 * TRUE and no delegate has been specified.
	 */

	public function helpAnchor():String {
	  return m_helpAnchor;
	}
	
	/**
	 * Sets the alert style.
	 *
	 * @see org.actionstep.constants.NSAlertStyle
	 */
	public function setAlertStyle(style:NSAlertStyle):Void {
	  m_style = style;
	}
	
	/**
	 * Returns the alert style.
	 *
	 * @see org.actionstep.constants.NSAlertStyle
	 */
	public function alertStyle():NSAlertStyle {
	  return m_style;
	}

	/**
	 * Sets the delegate that displays help for the alert.
	 */	
	public function setDelegate(delegate:Object) {
	  m_delegate = delegate;
	}
	
	/**
	 * Returns the delegate that displays help for the alert.
	 */
	public function delegate():Object {
	  return m_delegate;
	}
	
	/*
	- (int)runModal
	{
	  // FIXME
	  return NSAlertFirstButtonReturn;
	}
	
	- (void)beginSheetModalForWindow:(NSWindow *)window
			   modalDelegate:(id)delegate
			  didEndSelector:(SEL)didEndSelector
			     contextInfo:(void *)contextInfo
	{
	// FIXME
	}*/
	//should be uncasted, if Cocoa-styled
	
	/**
	 * Returns the modal dialog.
	 */
	public function window():ASAlertPanel {
		return m_sheet;
	}
	
	//! remove sheet
	
	/**
	 * Runs the modal alert in window. When the alert recieves user input,
	 * it invokes the didEndSelector in delegate. It's method signature should
	 * be as follows:
	 * 	alertDidEnd(alert:NSAlert, returnCode:constants.NSRunResponse, context:Object):Void
	 *
	 * Please note:
	 *	The delegate must either be a subclass of NSObject or have a method
	 * 	called respondsToSelector who when passed a string selector returns
	 *	TRUE if the object can respond, or FALSE if it can't.
	 */
	public function beginSheetModalForWindowModalDelegateDidEndSelectorContextInfo
	(window:NSWindow, delegate:Object, sel:String, ctxt:Object):Void {
		var list:Array = m_buttons.internalList();
		/*
		m_sheet = ASAlertPanel.NSGetAlert("", m_msg, list[0].title(), list[1].title(), list[2].title());
		
		window.resignKeyWindow();
		m_sheet.display();
		
		//add it to arg array
		arguments.unshift(m_sheet);
		m_app.beginSheetModalForWindowModalDelegateDidEndSelectorContextInfo.apply(m_app, arguments);
		*/
		ASAlertPanel.NSBeginAlertSheet
		("Alert", list[0].title(), list[1].title(), list[2].title(),
		window, delegate, sel, null, ctxt, m_msg, m_info);
	}
}