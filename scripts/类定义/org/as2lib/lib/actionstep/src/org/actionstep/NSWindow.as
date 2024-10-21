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

import org.actionstep.ASRootWindowView;
import org.actionstep.ASUtils;
import org.actionstep.ASFieldEditor;

import org.actionstep.NSResponder;
import org.actionstep.NSApplication;
import org.actionstep.NSNotificationCenter;
import org.actionstep.NSRect;
import org.actionstep.NSView;
import org.actionstep.NSPoint;
import org.actionstep.NSSize;
import org.actionstep.NSEvent;

import org.actionstep.constants.NSWindowOrderingMode;
import org.actionstep.constants.NSSelectionDirection;

class org.actionstep.NSWindow extends NSResponder {

  // Styles

  public static var NSBorderlessWindowMask:Number = 0;
  public static var NSTitledWindowMask:Number = 1;
  public static var NSClosableWindowMask:Number = 2;
  public static var NSMiniaturizableWindowMask:Number = 4;
  public static var NSResizableWindowMask:Number = 8;

	// Windows Levels

	public static var	NSDesktopWindowLevel:Number = -1000;	  /* GNUstep addition	*/
	public static var	NSNormalWindowLevel:Number = 0;	      /**The default level for NSWindow objects.*/
	public static var NSFloatingWindowLevel:Number = 3;	    /**Useful for floating palettes.*/
	public static var NSSubmenuWindowLevel:Number = 3;	    /**Reserved for submenus. Synonymous with NSTornOffMenuWindowLevel, which is preferred.*/
	public static var NSTornOffMenuWindowLevel:Number = 3;	/**The level for a torn-off menu. Synonymous with NSSubmenuWindowLevel.*/
	public static var NSMainMenuWindowLevel:Number = 20;	  /**Reserved for the applications main menu.*/
	public static var NSStatusWindowLevel:Number = 21;
	public static var NSModalPanelWindowLevel:Number = 100;
	public static var NSPopUpMenuWindowLevel:Number = 101;
	public static var NSScreenSaverWindowLevel:Number = 1000;

  // Private global variables

  private static var g_instances:Array = new Array();

  public static function instances():Array {
    return g_instances;
  }

  // Notifications
  public static var NSWindowWillCloseNotification:Number = ASUtils.intern("NSWindowWillCloseNotification");
  public static var NSWindowDidBecomeKeyNotification:Number = ASUtils.intern("NSWindowDidBecomeKeyNotification");
  public static var NSWindowDidBecomeMainNotification:Number = ASUtils.intern("NSWindowDidBecomeMainNotification");
  public static var NSWindowDidResignKeyNotification:Number = ASUtils.intern("NSWindowDidResignKeyNotification");
  public static var NSWindowDidResignMainNotification:Number = ASUtils.intern("NSWindowDidResignMainNotification");
  public static var NSWindowWillMoveNotification:Number = ASUtils.intern("NSWindowWillMoveNotification");
  public static var NSWindowDidDisplayNotification:Number = ASUtils.intern("NSWindowDidDisplayNotification");

  // Private variables

  private var m_app:NSApplication;
  private var m_notificationCenter:NSNotificationCenter;
  private var m_windowNumber:Number;
  private var m_delegate:Object;
  private var m_frameRect:NSRect;
  private var m_contentRect:NSRect;
  private var m_firstResponder:NSResponder;
  private var m_initialFirstResponder:NSView;
  private var m_rootView:ASRootWindowView;
  private var m_contentView:NSView;
  private var m_styleMask:Number;
  private var m_viewsNeedDisplay:Boolean;
  private var m_fieldEditor:ASFieldEditor;
  private var m_rootSwfURL:String;
	private var m_title:String;

  private var m_isKey:Boolean;
  private var m_isMain:Boolean;
  private var m_isVisible:Boolean;
  private var m_canHide:Boolean;

  private var m_lastEventView:NSView;

  private var m_level:Number;

  private var m_selectionDirection:NSSelectionDirection;

  private var m_minFrameSize:NSSize;
  private var m_maxFrameSize:NSSize;

  public function NSWindow() {
		m_app = NSApplication.sharedApplication();
		g_instances.push(this);
    m_viewsNeedDisplay = true;
    m_fieldEditor= ASFieldEditor.instance();
    m_title = "";
    m_isKey = false;
    m_isMain = false;
    m_isVisible = true;
    m_canHide = true;
    m_level = NSNormalWindowLevel;
		m_windowNumber = g_instances.length;
		m_selectionDirection = NSSelectionDirection.NSDirectSelection;
		m_minFrameSize = new NSSize(1,1);
		m_maxFrameSize = new NSSize(10000, 10000);
  }

  public function description():String {
    return "NSWindow(number="+m_windowNumber+", view="+m_rootView+")";
  }

  public function windowNumber():Number {
    return m_windowNumber;
  }

  public function init():NSWindow {
    return initWithContentRectStyleMaskSwf(NSRect.ZeroRect, NSBorderlessWindowMask, null);
  }

  public function initWithSwf(swf:String):NSWindow {
    return  initWithContentRectStyleMaskSwf(NSRect.ZeroRect, NSBorderlessWindowMask, swf);
  }

  public function initWithContentRect(contentRect:NSRect):NSWindow {
    return initWithContentRectStyleMaskSwf(contentRect, NSBorderlessWindowMask, null);
  }

  public function initWithContentRectSwf(contentRect:NSRect, swf:String):NSWindow {
    return initWithContentRectStyleMaskSwf(contentRect, NSBorderlessWindowMask, swf);
  }

  public function initWithContentRectStyleMask(contentRect:NSRect, styleMask:Number):NSWindow {
    return initWithContentRectStyleMaskSwf(contentRect, styleMask, null);
  }

  public function initWithContentRectStyleMaskSwf(contentRect:NSRect, styleMask:Number, swf:String):NSWindow {
    super.init();
    m_notificationCenter = NSNotificationCenter.defaultCenter();
    m_styleMask = styleMask;
    m_contentRect = contentRect.clone();
    m_frameRect = frameRectForContentRect();
    m_rootSwfURL = swf;
    m_rootView = (new ASRootWindowView()).initWithFrameWindow(m_frameRect, this);
    setContentView((new NSView()).initWithFrame(NSRect.withOriginSize(convertScreenToBase(m_contentRect.origin), m_contentRect.size)));
    return this;
  }

  // Calculating layout

  public static function contentRectForFrameRectStyleMask(frameRect:NSRect, styleMask:Number):NSRect {
    var rect:NSRect = frameRect.clone();
    if (styleMask == NSBorderlessWindowMask) {
      return rect;
    }
    if (styleMask & NSTitledWindowMask) {
      rect.origin.y += 23;
      rect.size.height -= 24;
      rect.origin.x += 1;
      rect.size.width -= 2;
    }
    return rect;
  }

  public static function frameRectForContentRectStyleMask(contentRect:NSRect, styleMask:Number):NSRect {
    var rect:NSRect = contentRect.clone();
    if (styleMask == NSBorderlessWindowMask) {
      return rect;
    }
    /*
    public static var NSBorderlessWindowMask = 0
    public static var NSTitledWindowMask = 1
    public static var NSClosableWindowMask = 2
    public static var NSMiniaturizableWindowMask = 4
    public static var NSResizableWindowMask = 8
    */
    //! Based on style masks reshape?
    if (styleMask & NSTitledWindowMask) {
      rect.origin.y -= 23;
      rect.size.height += 24;
      rect.origin.x -= 1;
      rect.size.width += 2;
    }
    return rect;
  }

  public function contentRectForFrameRect():NSRect {
    return NSWindow.contentRectForFrameRectStyleMask(m_frameRect, m_styleMask);
  }

  public function frameRectForContentRect():NSRect {
    return NSWindow.frameRectForContentRectStyleMask(m_contentRect, m_styleMask);
  }

  // Converting coordinates

  public function convertScreenToBase(point:NSPoint):NSPoint {
    return new NSPoint(point.x - m_frameRect.origin.x, point.y - m_frameRect.origin.y);
  }

  public function convertBaseToScreen(point:NSPoint):NSPoint {
    return new NSPoint(m_frameRect.origin.x +point.x, m_frameRect.origin.y + point.y);
  }

  // Moving and resizing

  public function frame():NSRect {
    return m_frameRect.clone();
  }

  public function setFrame(frame:NSRect) {
    frame = frame.clone();
    if (frame.size.width < m_minFrameSize.width) {
      frame.size.width = m_minFrameSize.width;
    }
    if (frame.size.height < m_minFrameSize.height) {
      frame.size.height = m_minFrameSize.height;
    }
    if (frame.size.width > m_maxFrameSize.width) {
      frame.size.width = m_maxFrameSize.width;
    }
    if (frame.size.height > m_maxFrameSize.height) {
      frame.size.height = m_maxFrameSize.height;
    }

    if (!frame.size.isEqual(m_frameRect.size)) { // Resize
      if (m_styleMask & NSTitledWindowMask) {
        frame = constrainFrameRect(frame);
      }
      if (m_delegate != null && typeof(m_delegate["windowWillResizeToSize"]) == "function") {
        frame.size = m_delegate["windowWillResizeToSize"].call(m_delegate, this, frame.size);
      }
    }
    if (frame.isEqual(m_frameRect)) {
      return; // Same shape;
    }
    if (!frame.origin.isEqual(m_frameRect.origin)) {
      m_notificationCenter.postNotificationWithNameObject(NSWindowWillMoveNotification, this);
      m_rootView.setFrameOrigin(frame.origin);
    }
    m_frameRect = frame;

    var cRect:NSRect = contentRectForFrameRect();
    if (!m_contentRect.size.isEqual(cRect.size)) {
      m_contentView.setFrameSize(cRect.size);
      m_contentView.setNeedsDisplay(true);
      m_rootView.setFrameSize(frame.size);
      m_rootView.setNeedsDisplay(true);
      m_contentRect = cRect;
    }
  }

  public function constrainFrameRect(rect:NSRect):NSRect {
    if (rect.size.width < 100) {
      rect.size.width = 100;
    }
    if (rect.size.height < 24) {
      rect.size.height = 24;
    }
    return rect;
  }

  public function setFrameOrigin(point:NSPoint) {
    var f:NSRect = m_frameRect.clone();
    f.origin = point;
    setFrame(f);
  }

  public function setContentSize(size:NSSize) {
    m_contentRect.size.width = size.width;
    m_contentRect.size.height = size.height;
    m_frameRect = frameRectForContentRect();
    m_rootView.setFrame(m_frameRect);
    m_contentView.setFrame(NSRect.withOriginSize(convertScreenToBase(m_contentRect.origin), m_contentRect.size));
  }

  public function showsResizeIndicator():Boolean {
    return m_rootView.showsResizeIndicator();
  }

  public function setShowsResizeIndicator(value:Boolean) {
    m_rootView.setShowsResizeIndicator(value);
  }

  // Constraining window size

  public function maxSize():NSSize {
    return m_maxFrameSize;
  }

  public function minSize():NSSize {
    return m_minFrameSize;
  }

  public function setMaxSize(size:NSSize) {
    if (size.width > 10000) {
      size.width = 10000;
    }
    if (size.height > 10000) {
      size.height = 10000;
    }
    m_maxFrameSize = size;
  }

  public function setMinSize(size:NSSize) {
    if (size.width < 1) {
      size.width = 1;
    }
    if (size.height < 1) {
      size.height = 1;
    }
    m_minFrameSize = size;
  }

  // Ordering Windows

  public function rootView():ASRootWindowView {
    return m_rootView;
  }

  public function orderBack(sender:Object) {
    m_rootView.extractView();
    m_rootView.lowestViewOfLevel().setLowerView(m_rootView);
    m_rootView.matchDepth();
  }

  public function orderFront(sender:Object) {
    m_rootView.extractView();
    m_rootView.setLowerView(m_rootView.highestViewOfLevel());
    m_rootView.matchDepth();
  }

  public function orderFrontRegardless(sender:Object) {
    orderFront();
  }

  public function orderOut(sender:Object) {
    //! How to handle this?
  }

  public function orderWindowRelativeTo(positioned:NSWindowOrderingMode, windowNumber:Number) {
    var windowRoot:ASRootWindowView = g_instances[windowNumber].rootView();
    switch(positioned) {
    case NSWindowOrderingMode.NSWindowAbove:
      m_rootView.extractView();
      m_rootView.setLowerView(windowRoot);
      m_rootView.matchDepth();
      break;
    case NSWindowOrderingMode.NSWindowBelow:
      m_rootView.extractView();
      windowRoot.setLowerView(m_rootView);
      m_rootView.matchDepth();
      break;
    case NSWindowOrderingMode.NSWindowOut:
      //! How to handle this?
      break;
    }
  }

  public function setLevel(newLevel:Number) {
    m_level = newLevel;
    orderFront();
  }

  public function level():Number {
    return m_level;
  }

  public function isVisible():Boolean {
    return m_isVisible;
  }

  public function swf():String {
    return m_rootSwfURL;
  }

  // Making key and main windows

  public function becomeKeyWindow() {
    if (!m_isKey) {
      m_isKey = true;
      m_rootView.setNeedsDisplay(true);
      if (m_firstResponder == null || m_firstResponder == this) {
        if (m_initialFirstResponder != null) {
          makeFirstResponder(m_initialFirstResponder);
        }
      }
      m_firstResponder.becomeFirstResponder();
      if (m_firstResponder != this) {
        Object(m_firstResponder).becomeKeyWindow();
      }
      m_notificationCenter.postNotificationWithNameObject(NSWindowDidBecomeKeyNotification, this);
    }
  }

  public function canBecomeKeyWindow():Boolean {
    return true;
  }

  public function isKeyWindow():Boolean {
    return m_isKey;
  }

  public function makeKeyAndOrderFront() {
    makeKeyWindow();
    orderFront(this);
  }

  public function makeKeyWindow() {
    if (!m_isKey && m_isVisible && canBecomeKeyWindow()) {
      m_app.keyWindow().resignKeyWindow();
      becomeKeyWindow();
    }
  }

  public function resignKeyWindow() {
    if (m_isKey) {
      if (m_firstResponder != this) {
        Object(m_firstResponder).resignKeyWindow();
      }
      m_isKey = false;
      m_rootView.setNeedsDisplay(true);
      m_notificationCenter.postNotificationWithNameObject(NSWindowDidResignKeyNotification, this);
    }
  }

  public function makeMainWindow() {
    if (m_isVisible && !m_isMain && canBecomeMainWindow()) {
      m_app.mainWindow().resignMainWindow();
      becomeMainWindow();
    }
  }

  public function becomeMainWindow() {
    if (!m_isMain) {
      m_isMain = true;
      m_notificationCenter.postNotificationWithNameObject(NSWindowDidBecomeMainNotification, this);
    }
  }

  public function canBecomeMainWindow():Boolean {
    return m_isVisible;
  }

  public function resignMainWindow() {
    if (m_isMain) {
      m_isMain = false;
      m_notificationCenter.postNotificationWithNameObject(NSWindowDidResignMainNotification, this);
    }
  }

  public function isMainWindow():Boolean {
    return m_isMain;
  }

  public function canHide():Boolean {
    return m_canHide;
  }

  public function setCanHide(value:Boolean) {
    m_canHide = value;
  }


  // Working with the responder chain

  public function firstResponder():NSResponder {
    return m_firstResponder;
  }

  public function makeFirstResponder(responder:NSResponder):Boolean {
    
    if (m_firstResponder == responder) {
      return true;
    }
    if (!(responder instanceof NSResponder) || !responder.acceptsFirstResponder()) {
      return false;
    }
    if (m_firstResponder != null && !m_firstResponder.resignFirstResponder()) {
      return false;
    }
    m_firstResponder = responder;
    if (!m_firstResponder.becomeFirstResponder()) {
      m_firstResponder = this;
      m_firstResponder.becomeFirstResponder();
      return false;
    }
    return true;
  }

  public function acceptsFirstResponder():Boolean {
    return true;
  }

  // Event handling

  public function currentEvent():NSEvent {
    return m_app.currentEvent();
  }

  public function postEventAtStart(event:NSEvent, atStart:Boolean) {
    m_app.postEventAtStart(event, atStart);
  }

  public function sendEvent(event:NSEvent) {
    __sendEventBecomesKeyOnlyIfNeeded(event, false);
  }

  private function __sendEventBecomesKeyOnlyIfNeeded(event:NSEvent, becomesKeyOnlyIfNeeded:Boolean) {
    var wasKey:Boolean = m_isKey;
    switch(event.type) {
    case NSEvent.NSLeftMouseDown:
      if (!wasKey && m_level != NSDesktopWindowLevel) {
        if (!becomesKeyOnlyIfNeeded || event.view.needsPanelToBecomeKey()) {
          makeKeyAndOrderFront();
        }
      }
      //if (m_firstResponder != event.view) {
      //  makeFirstResponder(event.view);
      //}
      if (wasKey || event.view.acceptsFirstMouse(event)) {
        m_lastEventView = event.view;
        event.view.mouseDown(event);
      }
      break;
    case NSEvent.NSLeftMouseUp:
      // send mouse up to the view that got mouse down
      m_lastEventView.mouseUp(event);
      break;
    case NSEvent.NSMouseExited:
      event.view.mouseExited(event);
      break;
    case NSEvent.NSMouseEntered:
      event.view.mouseEntered(event);
      break;
    case NSEvent.NSKeyDown:
      m_firstResponder.keyDown(event);
      break;
    case NSEvent.NSKeyUp:
      m_firstResponder.keyUp(event);
      break;
    }
  }

  public function keyDown(event:NSEvent) {
    if (event.keyCode == NSTabCharacter) {
      if (event.modifierFlags & NSEvent.NSShiftKeyMask) {
        selectPreviousKeyView(this);
      } else {
        selectNextKeyView(this);
      }
      return;
    }
    if (event.keyCode == Key.ESCAPE) {
      if (m_app.modalWindow() == this) {
        m_app.stopModal(); //! Should be abortModal()?
      }
      return;
    }
    //! performKeyEquivalent
  }

  // Keyboard interface control

  public function setInitialFirstResponder(view:NSView) {
    if (view instanceof NSView) {
      m_initialFirstResponder = view;
    }
  }

  public function initialFirstResponder():NSView {
    return m_initialFirstResponder;
  }

  public function selectKeyViewFollowingView(view:NSView) {
    var fView:NSView;
    if (view instanceof NSView) {
      fView = view.nextValidKeyView();
      if (fView != null) {
        makeFirstResponder(fView);
        if (fView.respondsToSelector("selectText")) {
          m_selectionDirection = NSSelectionDirection.NSSelectingNext;
          Object(fView).selectText(this);
          m_selectionDirection = NSSelectionDirection.NSDirectSelection;
        }
      }
    }
  }

  public function selectKeyViewPrecedingView(view:NSView) {
    var pView:NSView;
    if (view instanceof NSView) {
      pView = view.previousValidKeyView();
      if (pView != null) {
        makeFirstResponder(pView);
        if (pView.respondsToSelector("selectText")) {
          m_selectionDirection = NSSelectionDirection.NSSelectingPrevious;
          Object(pView).selectText(this);
          m_selectionDirection = NSSelectionDirection.NSDirectSelection;
        }
      }
    }
  }

  public function selectNextKeyView(sender:Object) {
    var result:NSView = null;
    if (m_firstResponder instanceof NSView) {
      result = NSView(m_firstResponder).nextValidKeyView();
    }
    if (result == null && m_initialFirstResponder != null) {
      if (m_initialFirstResponder.acceptsFirstResponder()) {
        result = m_initialFirstResponder;
      } else {
        result = m_initialFirstResponder.nextValidKeyView();
      }
    }
    if (result != null) {
      makeFirstResponder(result);
      if (result.respondsToSelector("selectText")) {
        m_selectionDirection = NSSelectionDirection.NSSelectingNext;
        Object(result).selectText(this);
        m_selectionDirection = NSSelectionDirection.NSDirectSelection;
      }
    }
  }

  public function selectPreviousKeyView(sender:Object) {
    var result:NSView = null;
    if (m_firstResponder instanceof NSView) {
      result = NSView(m_firstResponder).previousValidKeyView();
    }
    if (result == null && m_initialFirstResponder != null) {
      if (m_initialFirstResponder.acceptsFirstResponder()) {
        result = m_initialFirstResponder;
      } else {
        result = m_initialFirstResponder.previousValidKeyView();
      }
    }
    if (result != null) {
      makeFirstResponder(result);
      if (result.respondsToSelector("selectText")) {
        m_selectionDirection = NSSelectionDirection.NSSelectingPrevious;
        Object(result).selectText(this);
        m_selectionDirection = NSSelectionDirection.NSDirectSelection;
      }
    }
  }

  public function keyViewSelectionDirection():NSSelectionDirection {
    return m_selectionDirection;
  }

  /*
   selectPreviousKeyView:
   keyViewSelectionDirection
  */

  // Working with display characteristics
  
  public function windowDidDisplay() {
    m_notificationCenter.postNotificationWithNameObject(NSWindowDidDisplayNotification, this);
  }

  public function display() {
    m_viewsNeedDisplay = false;
    m_rootView.display();
  }

  public function displayIfNeeded() {
    if (m_viewsNeedDisplay) {
      m_viewsNeedDisplay = false;
      m_rootView.displayIfNeeded();
    }
  }

  public function contentView():NSView {
    return m_contentView;
  }

  public function setViewsNeedDisplay(value:Boolean) {
    m_viewsNeedDisplay = value;
  }

  public function viewsNeedDisplay():Boolean {
    return m_viewsNeedDisplay;
  }

  public function setContentView(view:NSView) {
    if (view == null) {
      view = (new NSView()).initWithFrame(NSRect.withOriginSize(convertScreenToBase(m_contentRect.origin), m_contentRect.size));
    }
    if (m_contentView != null) {
      m_contentView.removeFromSuperview();
    }
    m_contentView = view;
    m_rootView.setContentView(m_contentView);
    m_contentView.setFrame(NSRect.withOriginSize(convertScreenToBase(m_contentRect.origin), m_contentRect.size));
    m_contentView.setNextResponder(this);
  }

	public function styleMask():Number {
		return m_styleMask;
	}

	public function worksWhenModal():Boolean {
		return false;
	}

	public function center() {
	  setFrameOrigin(new NSPoint((Stage.width - m_frameRect.size.width)/2, (Stage.height - m_frameRect.size.height)/2 - 10));
	}

	public function close() {
	  release();
	  m_notificationCenter.postNotificationWithNameObject(NSWindowWillCloseNotification, this);
	  // m_nsapp.removeWindowsItem(); ???
	  // order out ???
	}

	public function setTitle(s:String) {
		m_title = s;
		//!display
	}

	public function title():String {
		return m_title;
	}

	private function release():Boolean {
	  m_rootView.removeFromSuperview();
	  return true;
	}

	/**
	 * Returns YES if the receiver has ever run as a modal sheet.
	 * Sheets are created using the NSPanel subclass.
	 */
	public function isSheet():Boolean {
		return false;
	}
	
	public function mouseLocationOutsideOfEventStream():NSPoint {
		return null;
	}

  // Field editor
/*
  public function fieldEditorCreateFlagForObject(createFlag:Boolean, object):NSText {
    //! should delegate
    if (m_fieldEditor == null && createFlag) {
      m_fieldEditor = new NSTextView();
      m_fieldEditor.setFieldEditor(true);
    }
    return m_fieldEditor;
  }

  public function endEditingForAnObject(object) {
    var editor:NSText = fieldEditorCreateFlagForObject(false, object);
    if (editor != null  && (editor == m_firstResponder)) {
      m_notificationCenter.postNotificationWithNameObject(NSTextView.NSTextDidEndEditingNotification, editor);
      editor.setString("");
      editor.setDelegate(null);
      editor.removeFromSuperview();
      m_firstResponder = this;
      m_firstResponder.becomeFirstResponder();
    }
  }
*/
  // Setting the delegate

  public function delegate():Object {
    return m_delegate;
  }

  public function setDelegate(value:Object) {
    if(m_delegate != null) {
      m_notificationCenter.removeObserverNameObject(m_delegate, null, this);
    }
    m_delegate = value;
    if (value == null) {
      return;
    }

    mapDelegateNotification("DidBecomeKey");
    mapDelegateNotification("DidBecomeMain");
    mapDelegateNotification("DidResignKey");
    mapDelegateNotification("DidResignMain");
    mapDelegateNotification("WillMove");
    mapDelegateNotification("DidDisplay");
  }

  private function mapDelegateNotification(name:String) {
    if(typeof(m_delegate["window"+name]) == "function") {
      m_notificationCenter.addObserverSelectorNameObject(m_delegate, "window"+name, ASUtils.intern("NSWindow"+name+"Notification"), this);
    }
  }


}
