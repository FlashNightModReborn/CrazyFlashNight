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

import org.actionstep.NSPanel;
import org.actionstep.NSApplication;
import org.actionstep.NSButton;
import org.actionstep.NSRect;
import org.actionstep.NSView;
import org.actionstep.NSFont;
import org.actionstep.NSImage;
import org.actionstep.NSSize;
import org.actionstep.NSPoint;
import org.actionstep.NSWindow;
import org.actionstep.NSException;

import org.actionstep.ASDraw;

import org.actionstep.constants.NSAlertReturn;

class org.actionstep.ASAlertPanel extends NSPanel {
	private static var g_init:Boolean;

	private static var g_app:NSApplication;
	private static var g_defTitle:String = "Alert";
	private static var g_ico:NSImage;

	private static var g_standardAlertPanel:ASAlertPanel;
	private static var g_informationalAlertPanel:ASAlertPanel;
	private static var g_criticalAlertPanel:ASAlertPanel;

	private var m_def:NSButton;
	private var m_alt:NSButton;
	private var m_oth:NSButton;
	private var m_ico_mc:MovieClip;
	private var m_btns:Array;

	private var m_msgField:TextField;
	private var m_msg:String;
	private var m_infoField:TextField;
	private var m_info:String;

	private var m_result:NSAlertReturn;
	private var m_isSheet:Boolean;

	private var m_callback:Object;
	private var m_selector:String;
	private var m_modalDelegate:Object;
	private var m_didEnd:String;
	private var m_didDismiss:String;

	private static var WinPos:NSPoint;
	private static var WinSize:NSSize;
	private static var MessageFont:NSFont;

	private static var IconLeft:Number = 24;
	private static var IconRight:Number = 16;
	private static var IconTop:Number = 15;

	private static var BtnTop:Number = 10;
	private static var BtnBottom:Number = 20;
	private static var BtnRight:Number = 24;
	private static var BtnMinHeight:Number = 24;
	private static var BtnMinWidth:Number = 72;
	private static var BtnInterspace:Number = 12;

	private static var MsgWidth:Number = 200;
	private static var InfoWidth:Number = 170;
	private static var InfoTop:Number = 8;
	private static var TFDiff:Number = MsgWidth-InfoWidth;

	public function init():ASAlertPanel	{
		var rect:NSRect = NSRect.ZeroRect;
		initWithContentRectStyleMask(rect, NSTitledWindowMask);
		setTitle("");
		// we're an ATTENTION panel, therefore:
		//setHidesOnDeactivate(false);
		setBecomesKeyOnlyIfNeeded(false);
		m_result = NSAlertReturn.NSError;
		m_isSheet = false;

		var content:NSView = contentView();

		if(g_ico==null) {
			g_ico = (new NSImage()).init();
			g_ico.setName("ASAlertIcon");
			g_ico.addRepresentation(new org.actionstep.images.ASAlertIconRep());
		}

		//position will be set later
		rect.reset(0, 0, BtnMinWidth, BtnMinHeight);
		m_def = makeButtonWithRect(rect);
		//m_def.setKeyEquivalent("\r");
		m_alt = makeButtonWithRect(rect);
		m_oth = makeButtonWithRect(rect);
		m_btns = [m_def, m_alt, m_oth];

		if(g_init==null) {	//do it once only
			g_app = NSApplication.sharedApplication();
			WinPos = new NSPoint(100, 100);
			WinSize = new NSSize(MsgWidth+g_ico.size.width+IconLeft+IconRight+BtnRight, 200);
			MessageFont = NSFont.systemFontOfSize(14);
			g_init = true;
		}

		//resize window
		setFrame(rect);
		return this;
	}

	private function positionElements() {
		var rect:NSRect = NSRect.ZeroRect;
		var content:NSView = contentView();

		if(m_ico_mc==null) {	//create the icon
			var mc:MovieClip = content.mcBounds();
			m_ico_mc = mc.createEmptyMovieClip("m_ico_mc", mc.getNextHighestDepth());
			g_ico.lockFocus(m_ico_mc);
			g_ico.drawAtPoint(NSPoint.ZeroPoint);
			g_ico.unlockFocus();
			m_ico_mc._x = IconLeft;
			m_ico_mc._y = IconTop;
			m_ico_mc._width = g_ico.size().width;
			m_ico_mc._height = g_ico.size().height;
		}

		if(m_msgField==null) { //assume that m_infoField is also null
			var fmt:TextFormat = MessageFont.textFormat();
			//position will be set later
			rect.origin.x = m_ico_mc._width + m_ico_mc._x + IconRight;
			rect.origin.y = IconTop;
			rect.size.width = MsgWidth;
			m_msgField = makeTF(rect, "m_msgField");
			fmt.bold = true;
			m_msgField.setNewTextFormat(fmt);

			rect.size.width = InfoWidth;
			m_infoField = makeTF(rect, "m_infoField");
			fmt.bold = false;
			m_infoField.setNewTextFormat(fmt);
		}
		m_msgField.text = m_msg;
		m_infoField.text = m_info;
		if(m_info==null || m_info=="") {
			m_infoField._visible = false;
		}

		var w:Number=0, i:String, btn:NSButton;
		for(i in m_btns) {
			btn = m_btns[i];
			w+=btn.frame().size.width;
		}

		//w is now width of window
		w+= BtnInterspace * (m_btns.length-1) + IconLeft + BtnRight;

		//resize fields if needed
		if(w>m_msgField._width+m_msgField._x+BtnRight) {
			m_msgField._width = w-m_msgField._x-BtnRight;
			m_infoField._width = m_msgField._width-TFDiff;
		}

		//position info tf
		m_infoField._y = m_msgField._height+m_msgField._y+InfoTop;

		//pt is temp var for btn-pos setting
		var pt:NSPoint = new NSPoint(0, m_infoField._y+m_infoField._height+BtnTop);

		//see if icoy is bigger than info's max-y (see pt.y)
		var icoy:Number = m_ico_mc._height + m_ico_mc._y + BtnTop;
		if(pt.y<icoy)
			pt.y = icoy;

		//offset first, then loop to set pos
		w-=IconLeft-m_ico_mc._width+BtnRight;
		for(var j:Number=0;j<3;j++) {
			btn = m_btns[j];
			w-=btn.frame().size.width;
			pt.x = w;
			btn.setFrameOrigin(pt);
			w-=BtnInterspace;
		}

		//resize window -- unfortunately, no setFrameSize
		rect.origin = NSPoint(WinPos.copy());
		rect.size.width = m_msgField._width + m_msgField._x + BtnRight;
		rect.size.height = m_def.frame().maxY() + BtnBottom + rootView().titleRect().size.height;
		setFrame(rect);

		//fill content with white
		ASDraw.solidRectWithRect(content.mcBounds(), content.bounds(), 0xFFFFFF);
	}

	 private function makeButtonWithRect (rect:NSRect):NSButton {
		var button:NSButton = new NSButton();
		button.initWithFrame(rect);

		//button.setButtonType(NSButtonType.NSMomentaryPushButton);
		button.setTarget(this);
		button.setAction("buttonAction");
		button["m_alert"] = this;
		contentView().addSubview(button);

		return button;
	}

	private function makeTF(rect:NSRect, title:String):TextField {
		var content:NSView = contentView();
		var mc:MovieClip = content.mcBounds();

		//location is not impt
		//non-editable, selectable, fixed-width
		mc.createTextField(title, mc.getNextHighestDepth(), rect.origin.x, rect.origin.y, rect.size.width, rect.size.height);
		var txt:TextField = mc[title];
		txt.type = "dynamic";
		txt.selectable = true;
		txt.wordWrap = true;
		txt.autoSize = true;

		return txt;
	}

	public function buttonAction(sender:Object):Void {
		if (!isActivePanel()) {
			var e:NSException = NSException.exceptionWithNameReasonUserInfo
      		("ASAlertPanelInvalidCondition",
      		"not in modal loop", null);
			trace(e);
			e.raise();
		} else if (sender == m_def) {
			m_result = NSAlertReturn.NSDefault;
		} else if (sender == m_alt) {
			m_result = NSAlertReturn.NSAlternate;
		} else if (sender == m_oth) {
			m_result = NSAlertReturn.NSOther;
		} else {
			var e:NSException = NSException.exceptionWithNameReasonUserInfo
      		("ASAlertPanelInvalidCondition",
      		"not in modal loop", null);
			trace(e);
			e.raise();
		}
		//m_alert property is set in makeButton
		if(!sender.hasOwnProperty("m_alert")) {
			var e:NSException = NSException.exceptionWithNameReasonUserInfo
      		("ASAlertPanelInvalidCondition",
      		"button is not part of an ASAlertPanel instance", null);
			trace(e);
			e.raise();
		}
		if(sender.m_alert.isSheet()) {
			g_app.endSheetReturnCode(this, m_result);
		} else {
			g_app.stopModalWithCode(m_result);
		}
		g_app.modalSession().docWin.makeKeyWindow();
	}

	public function result():NSAlertReturn {
		return m_result;
	}

	public function isActivePanel():Boolean {
		return g_app.modalWindow() == this;
	}

	public function runModal(call:Object, sel:String):Void {
		m_callback = call;
		m_selector = sel;

		g_app.runModalForWindow(this, this, "__modal");
		display();
		//orderOut(this);
	}

	private function __modal(res:Object) {
		var x:Object = m_callback, y:String=m_selector;
		x[y].call(x, this, res);
	}

	//macro from gnustep
	private static function useControl(control:NSView):Boolean	{
		return (control.superview()!=null);
	}

	private function setTitleMessageDefAltOther
	(title:String, message:String,
	defaultButton:String, alternateButton:String, otherButton:String,
	isSheet:Boolean, info:String):Void {
		setTitle(title);
		m_isSheet = isSheet;
		m_msg = message;
		if(info!=null && info!="") {
			m_info=info;
		}
		//m_info = "Not supported yet.";
		for(var i:Object in m_btns) {
			m_btns[i].setTitle(arguments[parseInt(i)+2]);
		}

		if (useControl(m_def)) {
			makeFirstResponder(m_def);
		} else {
			makeFirstResponder(this);
		}

		/* a *working* nextKeyView chain:
			 the trick is that the 3 buttons are falset always used (displayed)
			 so we have to set the nextKeyView *each* time.
			 Maybe some optimisation in the logic of this block will be good,
			 however it seems too risky for a (so) small reward
		*/
		var ud:Boolean = useControl(m_def),
			ua:Boolean = useControl(m_alt),
			uo:Boolean = useControl(m_oth);
			/*
		if (ud) {
			if (uo)	m_def.setNextKeyView(m_oth);
			else if (ua)	m_def.setNextKeyView(m_alt);
			else {
				m_def.setPreviousKeyView(null);
				m_def.setNextKeyView(null);
			}
		}

		if (uo) {
			if (ua)	m_oth.setNextKeyView(m_alt);
			else if (ud)	m_oth.setNextKeyView(m_def);
			else {
				m_oth.setPreviousKeyView(null);
				m_oth.setNextKeyView(null);
			}
		}

		if (ua) {
			if (ud)	m_alt.setNextKeyView(m_def);
			else if (uo)	m_alt.setNextKeyView(m_oth);
			else {
				m_alt.setPreviousKeyView(null);
				m_alt.setNextKeyView(null);
			}
		}*/

		m_result = NSAlertReturn.NSError;	 /* If false button was pressed	*/
	}

	private static function getSomePanel(
		instance:ASAlertPanel,
		defTitle:String,
		title:String,
		message:String,
		defaultButton:String,
		alternateButton:String,
		otherButton:String,
		sheet:Boolean,
		info:String):ASAlertPanel {
		var panel:ASAlertPanel;

		if (instance != null) {
			if (instance.isActivePanel()) {
				panel = (new ASAlertPanel()).init();
			} else {
				panel = instance;
			}
		} else {
			panel = (new ASAlertPanel()).init();
			instance = panel;
		}
		if (title == "" || title ==null) {
			title = defTitle;
		}
		if (title != null) {
			panel.setTitle(title);
		}
		if(sheet==null) {
			sheet = false;
		}
		panel.setTitleMessageDefAltOther
		(title, message, defaultButton, alternateButton, otherButton, sheet, info);

		return panel;
	}

	public function display() {
		super.display();
		positionElements();
	}

	public static function NSGetAlert(
		title:String,
		msg:String,
		defaultButton:String,
		alternateButton:String,
		otherButton:String):ASAlertPanel {

		//var message:String = "";
		//message = NSString.stringWithFormatArguments(msg, rest);

		return getSomePanel(g_standardAlertPanel, g_defTitle, title, msg,
			defaultButton, alternateButton, otherButton);
	}

	public static function NSRunAlert(
		title:String,
		message:String,
		defaultButton:String,
		alternateButton:String,
		otherButton:String,
		call:Object,
		sel:String):Void {

		if (defaultButton == null) {
			defaultButton = "OK";
		}

		var panel:ASAlertPanel = getSomePanel(g_standardAlertPanel, g_defTitle, title, message,
			defaultButton, alternateButton, otherButton);

		panel.runModal(call, sel);
	}

	//NSRunLocalizedAlertPanel

	public static function NSGetCriticalAlert(
		title:String,
		message:String,
		defaultButton:String,
		alternateButton:String,
		otherButton:String):ASAlertPanel {

		return getSomePanel(g_criticalAlertPanel, "Critical", title, message,
			defaultButton, alternateButton, otherButton);
	}

	public static function NSRunCriticalAlert(
		title:String,
		message:String,
		defaultButton:String,
		alternateButton:String,
		otherButton:String,
		call:Object,
		sel:String):Void {

		var panel:ASAlertPanel = getSomePanel(g_criticalAlertPanel, "Critical", title, message,
			defaultButton, alternateButton, otherButton);

		panel.runModal(call, sel);
	}

	public static function NSGetInformationalAlert(
		title:String,
		message:String,
		defaultButton:String,
		alternateButton:String,
		otherButton:String):ASAlertPanel {

		return getSomePanel(g_informationalAlertPanel, "Information", title, message,
			defaultButton, alternateButton, otherButton);
	}

	public static function NSRunInformationalAlert(
		title:String,
		message:String,
		defaultButton:String,
		alternateButton:String,
		otherButton:String,
		call:Object,
		sel:String):Void {

		var panel:ASAlertPanel = getSomePanel(g_informationalAlertPanel, "Information", title, message,
			defaultButton, alternateButton, otherButton);

		panel.runModal(call, sel);
	}

	public static function NSBeginAlertSheet
	(title:String, defaultButton:String, alternateButton:String, otherButton:String,
	docWindow:NSWindow,
	modalDelegate:Object, didEndSelector:String, didDismissSelector:String,
	contextInfo:Object, msg:String, info:String) {
		if (defaultButton == null || defaultButton == "") {
			defaultButton = "OK";
		}

		var panel:ASAlertPanel = getSomePanel(g_standardAlertPanel, g_defTitle, title, msg,
			defaultButton, alternateButton, otherButton, true, info);
		panel["m_modalDelegate"] = modalDelegate;
		panel["m_didEnd"] = didEndSelector;
		panel["m_didDismiss"] = didDismissSelector;
		panel.display();

		// FIXME: We should also change the button action to call endSheet:
		NSApplication.sharedApplication().beginSheetModalForWindowModalDelegateDidEndSelectorContextInfo
		(panel, docWindow, panel, "alertCallback", contextInfo);
	}

	private function alertCallback(panel:ASAlertPanel, ret:Object, ctxt:Object) {
		var o:Object = m_modalDelegate;
		var end:Object = m_didEnd;
		var diss:Object = m_didDismiss;
		o[end].call(o, this, ret, ctxt);
		ASAlertPanel.NSRelease(this);
		o[diss].call(o, this, ret, ctxt);
	}

	/*
	void NSBeginCriticalAlertSheet(String *title,
							 String *defaultButton,
							 String *alternateButton,
							 String *otherButton,
							 NSWindow *docWindow,
							 id modalDelegate,
							 SEL willEndSelector,
							 SEL didEndSelector,
							 void *contextInfo,
							 String *msg, ...)
	{
		va_list	ap;
		String	*message;
		GSAlertPanel	*panel;

		va_start(ap, msg);
		message = [String stringWithFormat: msg arguments: ap];
		va_end(ap);

		panel = getSomePanel(&criticalAlertPanel, @"Critical", title, message,
			defaultButton, alternateButton, otherButton);

		// FIXME: We should also change the button action to call endSheet:
		[NSApp beginSheet: panel
		 modalForWindow: docWindow
		 modalDelegate: modalDelegate
		 didEndSelector: didEndSelector
		 contextInfo: contextInfo];
		[panel close];
		NSReleaseAlertPanel(panel);
	}

	void NSBeginInformationalAlertSheet(String *title,
							String *defaultButton,
							String *alternateButton,
							String *otherButton,
							NSWindow *docWindow,
							id modalDelegate,
							SEL willEndSelector,
							SEL didEndSelector,
							void *contextInfo,
							String *msg, ...)
	{
		va_list			 ap;
		String	*message;
		GSAlertPanel	*panel;

		va_start(ap, msg);
		message = [String stringWithFormat: msg arguments: ap];
		va_end(ap);

		panel = getSomePanel(&informationalAlertPanel,
						@"Information",
						title, message,
						defaultButton, alternateButton, otherButton);

		// FIXME: We should also change the button action to call endSheet:
		[NSApp beginSheet: panel
		 modalForWindow: docWindow
		 modalDelegate: modalDelegate
		 didEndSelector: didEndSelector
		 contextInfo: contextInfo];
		[panel close];
		NSReleaseAlertPanel(panel);
	}*/

	public static function NSRelease(panel:ASAlertPanel):Void {
		if ((panel != g_standardAlertPanel)
			 && (panel != g_informationalAlertPanel)
			 && (panel != g_criticalAlertPanel))
		{
			panel.close();
		}
	}

	public function isSheet():Boolean {
		return m_isSheet;
	}

	public function setSelectors(end:String, dismiss:String) {
		m_didEnd = end;
		m_didDismiss = dismiss;
	}

	public function didEnd():String {
		return m_didEnd;
	}

	public function didDismiss():String {
		return m_didDismiss;
	}

	public function description():String {
		return "ASAlertPanel()";
	}
}
