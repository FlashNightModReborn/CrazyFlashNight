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
import org.actionstep.NSImage;
import org.actionstep.NSFormatter;
import org.actionstep.NSFont;
import org.actionstep.NSColor;
import org.actionstep.NSAttributedString;
import org.actionstep.NSRect;
import org.actionstep.NSView;
import org.actionstep.NSEvent;
import org.actionstep.NSPoint;
import org.actionstep.NSSize;
import org.actionstep.NSText;
import org.actionstep.NSTimer;
import org.actionstep.NSNumber;
import org.actionstep.NSControl;
import org.actionstep.NSApplication;

import org.actionstep.constants.NSCellType;
import org.actionstep.constants.NSTextAlignment;
import org.actionstep.constants.NSCellAttribute;
import org.actionstep.constants.NSBorderType;
import org.actionstep.constants.NSControlSize;
import org.actionstep.constants.NSControlTint;

class org.actionstep.NSCell extends NSObject {
  
  public static var NSAnyType:Number = 0; // Any value is allowed.
  public static var NSIntType:Number = 1; // Must be between INT_MIN and INT_MAX.
  public static var NSPositiveIntType:Number = 2; // Must be between 1 and INT_MAX.
  public static var NSFloatType:Number = 3; // Must be between –FLT_MAX and FLT_MAX.
  public static var NSPositiveFloatType:Number = 4; // Must be between FLT_MIN and FLT_MAX.
  public static var NSDoubleType:Number = 5; // Must be between –DBL_MAX and DBL_MAX.
  public static var NSPositiveDoubleType:Number = 6; // Must be between DBL_MAX and DBL_MAX.
  
  public static var NSOffState:Number = 0;
  public static var NSOnState:Number = 1;
  public static var NSMixedState:Number = -1;

  public static var NSNoCellMask:Number = 0;
  public static var NSPushInCellMask:Number = 1;
  public static var NSContentsCellMask:Number = 2;
  public static var NSChangeGrayCellMask:Number = 4;
  public static var NSChangeBackgroundCellMask:Number = 8;
  
  private var m_stringValue:Object;
  private var m_objectValue:Object;
  private var m_hasValidObjectValue:Boolean;
  
  private var m_image:NSImage;
  private var m_type:NSCellType;
  private var m_state:Number;
  private var m_allowsMixedState:Boolean;
  private var m_formatter:NSFormatter;
  private var m_font:NSFont;
  private var m_fontColor:NSColor;
  private var m_editable:Boolean;
  private var m_selectable:Boolean;
  private var m_scrollable:Boolean;
  private var m_alignment:NSTextAlignment;
  private var m_wraps:Boolean;
  private var m_cellAttributes:Array;
  private var m_enabled:Boolean;
  private var m_bezeled:Boolean;
  private var m_bordered:Boolean;
  private var m_actionMask:Number;
  private var m_refusesFirstResponder:Boolean;
  private var m_showsFirstResponder:Boolean;
  private var m_sendsActionOnEndEditing:Boolean;
  private var m_mouseDownFlags:Number;
  private var m_highlighted:Boolean;
  private var m_controlSize:NSControlSize;
  private var m_controlTint:NSControlTint;
  private var m_controlView:NSView;
  private var m_app:NSApplication;
  private var m_periodicInterval:Number;
  private var m_periodicDelay:Number;

  // An AS method cannot block, so a callback is needed for tracking mouse events
  private var m_trackingCallback:Object;
  private var m_trackingCallbackSelector:String;
  private var m_trackingData:Object;
	
	public function NSCell() {
	  m_trackingData = null;
    m_stringValue = null;
    m_objectValue = null;
    m_hasValidObjectValue = false;
    m_type = NSCellType.NSNullCellType;
    m_state = NSOffState;
    m_allowsMixedState = false;
    m_editable = false;
    m_selectable = false;
    m_scrollable = false;
    m_alignment = NSTextAlignment.NSLeftTextAlignment;
    m_wraps = false;
    m_cellAttributes = new Array();
    m_enabled = true;
    m_bezeled = false;
    m_actionMask = 0;
    m_refusesFirstResponder = false;
    m_showsFirstResponder = false;
    m_sendsActionOnEndEditing = false;
    m_mouseDownFlags = 0;
    m_trackingData = null;
    m_controlSize = NSControlSize.NSRegularControlSize;
    m_controlTint = NSControlTint.NSDefaultControlTint;
    m_controlView = null;
    m_app = NSApplication.sharedApplication();
  }
  
  public static function prefersTrackingUntilMouseUp():Boolean {
    return false;
  }
  
  public function init():NSCell {
    return initTextCell("");
  }
  
  public function initImageCell(image:NSImage):NSCell {
    m_type = NSCellType.NSImageCellType;
    m_image = image;
    m_font = NSFont.systemFontOfSize(0);
    m_fontColor = NSColor.systemFontColor();
    m_actionMask = NSEvent.NSLeftMouseUpMask;
    return this;
  }
  
  public function initTextCell(text:String):NSCell {
    m_type = NSCellType.NSTextCellType;
    m_stringValue = text;
    m_font = NSFont.systemFontOfSize(0);
    m_fontColor = NSColor.systemFontColor();
    m_actionMask = NSEvent.NSLeftMouseUpMask;
    return this;
  }

  // Setting and getting cell values
  
  /*
   * Overridden by subclasses to clean up cell resources
   */
  public function release() {
  	
  }

  public function hasValidObjectValue():Boolean {
    return m_hasValidObjectValue;
  }

  public function setObjectValue(value:Object) {
    m_objectValue = value;
    var contents:String = m_formatter.stringForObjectValue(m_objectValue);
    if (contents == null) {
      if ((m_formatter == null) && (value instanceof String)) {
        contents = String(m_objectValue);
        m_hasValidObjectValue = true;
      } else {
        contents = m_objectValue.description();
        m_hasValidObjectValue = false;
      }
    } else {
      m_hasValidObjectValue = true;
    }
    m_stringValue = contents;
  }
  
  public function objectValue():Object {
    if (m_hasValidObjectValue) {
      return m_objectValue;
    } else {
      return null;
    }
  }
  
  public function setIntValue(value:Number) {
    setObjectValue(NSNumber.numberWithInt(value));
  }
  
  public function intValue():Number {
    if (m_objectValue != null && (typeof(m_objectValue["intValue"]) == "function")) {
      return m_objectValue.intValue();
    } else {
      return Number(stringValue());
    }
  }
  
  public function setDoubleValue(value:Number) {
    setObjectValue(NSNumber.numberWithDouble(value));
  }

  public function doubleValue():Number {
    if (m_objectValue != null && (typeof(m_objectValue["doubleValue"]) == "function")) {
      return m_objectValue.doubleValue();
    } else {
      return Number(stringValue());
    }
  }

  public function setFloatValue(value:Number) {
    setObjectValue(NSNumber.numberWithFloat(value));
  }

  public function floatValue():Number {
    if (m_objectValue != null && (typeof(m_objectValue["floatValue"]) == "function")) {
      return m_objectValue.floatValue();
    } else {
      return Number(stringValue());
    }
  }

  public function setStringValue(string:String) {
    if (m_type != NSCellType.NSTextCellType) {
      setType(NSCellType.NSTextCellType);
    }
    if (m_formatter == null) {
      m_stringValue = string;
      m_objectValue = null;
    } else {
      //! Set the value with a formatter
    }
  }

  public function stringValue():String {
    if (m_stringValue instanceof NSAttributedString) {
      return NSAttributedString(m_stringValue).string();
    } else {
      return String(m_stringValue);
    }
  }
  
  // Setting and getting cell attributes
  
  /**
   * Sets a cell attribute identified by aParameter such as the receiver's
   * state and whether it's disabled, editable, or highlighted to value.
   */
  public function setCellAttributeTo(attribute:NSCellAttribute, to:Number) {
    m_cellAttributes[attribute.value] = to;
  }
  
  public function cellAttribute(attribute:NSCellAttribute):Number {
    return m_cellAttributes[attribute.value];
  }

  public function type():NSCellType {
    return m_type;
  }

  public function setType(value:NSCellType) {
    m_type = value;
  }
  
  public function setEnabled(value:Boolean) {
    m_enabled = value;
  }
  
  public function isEnabled():Boolean {
    return m_enabled;
  }
  
  /**
   * Sets whether the receiver draws itself with a bezeled border, depending
   * on the Boolean value flag. The setBezeled: and setBordered: methods are
   * mutually exclusive (that is, a border can be only plain or bezeled).
   * Invoking this method results in setBordered: being sent with a value of FALSE.
   */  
  public function setBezeled(value:Boolean) {
    m_bezeled = value;
    if (m_bezeled) {
      m_bordered = false;
    }
  }
  
  /**
   * Returns whether the receiver has a bezeled border.
   */
  public function isBezeled():Boolean {
    return m_bezeled;
  }

  /**
   * Sets whether the receiver draws itself outlined with a plain border,
   * depending on the Boolean value flag. The setBezeled: and setBordered:
   * methods are mutually exclusive (that is, a border can be only plain or
   * bezeled). Invoking this method results in setBezeled: being sent with a
   * value of FALSE.
   */
  public function setBordered(flag:Boolean) {
    m_bordered = flag;
    if (m_bordered) {
      m_bezeled = false;
    }
  }
  
  /**
   * Returns whether the receiver has a plain border.
   */
  public function isBordered():Boolean {
    return m_bordered;
  }
  
  /**
   * Returns whether the receiver is opaque (nontransparent).
   */
  public function isOpaque():Boolean {
    return false;
  }

  // Setting the state
  
  public function allowsMixedState():Boolean {
    return m_allowsMixedState;
  }
  
  public function nextState():Number {
    switch(m_state) {
      case NSOnState:
        return NSOffState;
        break;
      case NSOffState:
        if(m_allowsMixedState) {
          return NSMixedState;
        } else {
          return NSOnState;
        }
        break;
      case NSMixedState:
        return NSOnState;
        break;
      default:
        return NSOnState;
        break;
    }
  }

  public function setAllowsMixedState(value:Boolean) {
    m_allowsMixedState = value;
  }
  
  public function setNextState() {
    setState(nextState());
  }

  public function state():Number {
    return m_state;
  }

  public function setState(value:Number) {
    m_state = value;
  }
  
  // Modifying textual attributes of cells
  
  public function setEditable(value:Boolean) {
    m_editable = value;
  }
  
  public function isEditable():Boolean {
    return m_editable;
  }

  public function setSelectable(value:Boolean) {
    m_selectable = value;
    if (!m_selectable) {
      m_editable = false;
    }
  }
  
  public function isSelectable():Boolean {
    return m_selectable || m_editable;
  }
  
  public function setScrollable(value:Boolean) {
    m_scrollable = value;
  }
  
  public function isScrollable():Boolean {
    return m_scrollable;
  }
  
  public function setAlignment(value:NSTextAlignment) {
    m_alignment = value;
  }
  
  public function alignment():NSTextAlignment {
    return m_alignment;
  }
  
  public function font():NSFont {
    return m_font;
  }
  
  public function setFont(value:NSFont) {
    m_font = value;
  }
  
  public function setFontColor(color:NSColor) {
    m_fontColor = color;
  }
  
  public function fontColor():NSColor {
    return m_fontColor;
  }
  
  public function setWraps(value:Boolean) {
    m_wraps = value;
    if (m_wraps) {
      m_scrollable = false;
    }
  }
  
  public function wraps():Boolean {
    return m_wraps;
  }
  
  public function setAttributedStringValue(value:NSAttributedString) {
    if (m_formatter != null) {
      //! What do we do with the attributed string values and the formatter?
    }
    m_stringValue = value;
  }
  
  public function attributedStringValue():NSAttributedString {
    if (m_stringValue instanceof NSAttributedString) {
      return NSAttributedString(m_stringValue);
    }
    if (m_formatter != null) {
      //! generate NSAttributedString?
    }
    return (new NSAttributedString()).initWithString(String(m_stringValue));
  }
  
  /**
   * Returns the receiver's title. By default it returns the cell's string
   * value. Subclasses, such as NSButtonCell, may override this method to
   * return a different value.
   */
  public function title():String {
    return stringValue();
  }
  
  /**
   * Sets the title of the receiver to aString.
   */
  public function setTitle(aString:String) {
    setStringValue(aString);
  }
  
  // Setting the target and action
  public function setAction(selector:String) {
    throw new Error("NSInternalInconsistencyException");
  }
  
  public function action():String {
    return null;
  }
  
  public function setTarget(object:Object) {
    throw new Error("NSInternalInconsistencyException");
  }
  
  public function target():Object {
    return null;
  }
  
  /**
   * Sets whether the receiver continuously sends its action message to its
   * target while it tracks the mouse, depending on the Boolean value flag. In
   * practice, the continuous setting has meaning only for instances of
   * NSActionCell and its subclasses, which implement the target/action mechanism.
   * Some NSControl subclasses, notably NSMatrix, send a default action to a
   * default target when a cell doesn't provide a target or action.
   */
  public function setContinuous(value:Boolean) {
    if(value) {
      m_actionMask |= NSEvent.NSPeriodicMask;
    } else {
      m_actionMask &= ~NSEvent.NSPeriodicMask;
    }
  }
  
  /**
   * Returns whether the receiver sends its action message continuously on mouse down.
   */
  public function isContinuous():Boolean {
    return (m_actionMask & NSEvent.NSPeriodicMask)!=0;
  }
  
  public function sendActionOn(mask:Number):Number {
    var oldMask:Number = m_actionMask;
    m_actionMask = mask;
    return oldMask;
  }
  
  // Setting and getting an image
  
  public function setImage(value:NSImage) {
    if (type()!=NSCellType.NSImageCellType) {
      setType(NSCellType.NSImageCellType);
    }
    m_image = value;
  }
  
  public function image():NSImage {
    if (type()!=NSCellType.NSImageCellType) {
      return null;
    }
    return m_image;
  }
  
  
  // Assigning a tag
  
  public function setTag(value:Number) {
    throw new Error("NSInternalInconsistencyException");
  }
  
  public function tag():Number {
    return -1;
  }

  // Formatting and validating data

  public function formatter():NSFormatter {
    return m_formatter;
  }

  public function setFormatter(value:NSFormatter) {
    m_formatter = value;
  }

  /* DEPRECATED
    – setEntryType:

    – entryType

    – isEntryAcceptable:

    – setFloatingPointFormat:left:right:
  */
  
  // Making cells respond to keyboard events
  
  public function acceptsFirstResponder():Boolean {
    return m_enabled && !m_refusesFirstResponder;
  }
  
  public function setRefusesFirstResponder(value:Boolean) {
    m_refusesFirstResponder = value;
  }
  
  public function refusesFirstResponder():Boolean {
    return m_refusesFirstResponder;
  }
  
  public function setShowsFirstResponder(value:Boolean) {
    m_showsFirstResponder = value;
  }
  
  public function showsFirstResponder():Boolean {
    return m_showsFirstResponder;
  }
  
  public function performClick() {
    var cview:NSView = controlView();
    if (cview != null) {
      performClickWithFrameInView(cview.bounds(), cview);
    }
  }
  
  public function performClickWithFrameInView(frame:NSRect, view:NSView) {
    if (!m_enabled) {
      return;
    }
    if(view != null) {
      setHighlighted(true);
      drawWithFrameInView(frame, view);
      NSTimer.scheduledTimerWithTimeIntervalTargetSelectorUserInfoRepeats(.1, this, "__performClickCallback", {frame:frame, view:view}, false);
    } else {
      setNextState();
      NSApplication.sharedApplication().sendActionToFrom(action(), target(), this);
    }
  }
  
  private function __performClickCallback(timer:NSTimer) {
    var info:Object = timer.userInfo();
    setHighlighted(false);
    drawWithFrameInView(info.frame, info.view);
    setNextState();
    NSControl(info.view).sendActionTo(action(), target());
  }
  
  // Deriving values from other cells
  
  public function takeObjectValueFrom(sender:Object) {
    setObjectValue(sender.objectValue());
  }
  
  public function takeIntValueFrom(sender:Object) {
    setIntValue(sender.intValue());
  }

  public function takeStringValueFrom(sender:Object) {
    setStringValue(sender.stringValue());
  }
  
  public function takeDoubleValueFrom(sender:Object) {
    setDoubleValue(sender.doubleValue());
  }
  
  public function takeFloatValueFrom(sender:Object) {
    setFloatValue(sender.floatValue());
  }
  
  // Tracking the mouse
  
  public function setTrackingCallbackSelector(callback:Object, selector:String) {
    m_trackingCallback = callback;
    m_trackingCallbackSelector = selector;
  }
  
  private function trackingEventMask():Number {
    return NSEvent.NSLeftMouseDownMask | NSEvent.NSLeftMouseUpMask | NSEvent.NSLeftMouseDraggedMask
          | NSEvent.NSMouseMovedMask  | NSEvent.NSOtherMouseDraggedMask | NSEvent.NSRightMouseDraggedMask;
  }
  
  /*
   * This method normally returns a boolean, but we have to support a callback
   * mechanism
   *
   * @see setTrackingCallbackSelector
   */
  public function trackMouseInRectOfViewUntilMouseUp(event:NSEvent, rect:NSRect, 
    view:NSView, untilMouseUp:Boolean) { 
    var location:NSPoint = event.mouseLocation;
    var point:NSPoint = location.clone();
		var periodic:Boolean = false;
			
    view.mcBounds().globalToLocal(point);
    if(!startTrackingAtInView(point, view)) {
      m_trackingCallback[m_trackingCallbackSelector].call(m_trackingCallback, false);
      return;
    }
		if((m_actionMask & NSEvent.NSLeftMouseDownMask) && event.type == NSEvent.NSLeftMouseDown) {
      NSControl(controlView()).sendActionTo(action(), target());
    }
		
    m_trackingData = { 
      location: location,
      untilMouseUp: untilMouseUp,
      action: action(),
      target: target(),
      view: view,
      lastPoint: point,
      eventMask: trackingEventMask()
    };
		
    if(m_actionMask & NSEvent.NSPeriodicMask) {
      var times:Object = getPeriodicDelayInterval();			
      NSEvent.startPeriodicEventsAfterDelayWithPeriod(times.delay, times.interval);
      m_trackingData.eventMask |= NSEvent.NSPeriodicMask;
			periodic = true;
    }
		
		//don't track if modal loop has started
		if(m_app.runningModal() && m_controlView.window()!=m_app.modalWindow()) {
			m_trackingCallback[m_trackingCallbackSelector].call(m_trackingCallback, true, periodic);
			return;
		}
		
		m_app.callObjectSelectorWithNextEventMatchingMaskDequeue(this, "mouseTrackingCallback", m_trackingData.eventMask, true);
  }
  
  public function mouseTrackingCallback(event:NSEvent) {
    var point:NSPoint = event.mouseLocation.clone();
		//optional cast -- apparently, mtasc's && returns last value
		var periodic:Boolean = Boolean((event.type == NSEvent.NSPeriodic) && (m_actionMask & NSEvent.NSPeriodicMask));
    m_trackingData.view.mcBounds().globalToLocal(point);
		if(event.view != m_trackingData.view) { //moved out of view
			stopTrackingAtInViewMouseIsUp(m_trackingData.lastPoint, point, controlView(), false);
			
			//stimulate mouseUp
      m_trackingCallback[m_trackingCallbackSelector].call(m_trackingCallback, false, periodic);
			
			if (m_actionMask & NSEvent.NSPeriodicMask) {	//stop sending periodic when mouse up **very impt**
				NSEvent.stopPeriodicEvents();
			}
    } else { // still in view
      if (event.type == NSEvent.NSLeftMouseUp) { // mouse up?
        stopTrackingAtInViewMouseIsUp(m_trackingData.lastPoint, point, controlView(), true);
				m_trackingCallback[m_trackingCallbackSelector].call(m_trackingCallback, true, periodic);
				
        setNextState();
				if(m_actionMask & NSEvent.NSLeftMouseUpMask) {
					m_trackingData.view.sendActionTo(m_trackingData.action, m_trackingData.target);
				}
				
        if (m_actionMask & NSEvent.NSPeriodicMask) {	//stop sending periodic when mouse up **very impt**
          NSEvent.stopPeriodicEvents();
        }
			} else { // no mouse up
        if (periodic) { //! Dragged too?
          m_trackingData.view.sendActionTo(m_trackingData.action, m_trackingData.target);
				}
				
        if (continueTrackingAtInView(m_trackingData.lastPoint, point, controlView())) {
          m_trackingData.lastPoint = point;
					m_trackingCallback[m_trackingCallbackSelector].call(m_trackingCallback, false, periodic);
					
          m_app.callObjectSelectorWithNextEventMatchingMaskDequeue(this, "mouseTrackingCallback", m_trackingData.eventMask, true);
        } else { // don't continue...no mouse up
					stopTrackingAtInViewMouseIsUp(m_trackingData.lastPoint, point, controlView(), false);
					m_trackingCallback[m_trackingCallbackSelector].call(m_trackingCallback, false, periodic);
					
          if (m_actionMask & NSEvent.NSPeriodicMask) {
            NSEvent.stopPeriodicEvents();
          }
        }
      }
    }
  }

  /**
   * Returns an object with delay and interval properties
   */
  public function getPeriodicDelayInterval():Object {
    return {delay:.1, interval:.1};
  }
  
  public function startTrackingAtInView(startPoint:NSPoint, 
    controlView:NSView):Boolean {
    return true;
  }
  
  public function continueTrackingAtInView(lastPoint:NSPoint, currentPoint:NSPoint, 
    controlView:NSView):Boolean {
    return true;
  }
  
  public function stopTrackingAtInViewMouseIsUp(lastPoint:NSPoint, stopPoint:NSPoint,
    controlView:NSView, mouseIsUp:Boolean) {
		//if mouseUp, this would have been done by control
		if(!mouseIsUp)	setHighlighted(false);
  }
  
  public function mouseDownFlags():Number {
    return m_mouseDownFlags;
  }
  
  // Determining cell sizes
  
  public function cellSize():NSSize {
    var borderSize:NSSize;
    var csize:NSSize;
    if (m_bordered) {
      borderSize = NSBorderType.NSLineBorder.size;
    } else if(m_bezeled) {
      borderSize = NSBorderType.NSBezelBorder.size;;
    } else {
      borderSize = NSSize.ZeroSize;
    }
    switch(m_type.value) {
      case NSCellType.NSTextCellType.value:
        var text:NSAttributedString = attributedStringValue();
        if (text.string() == null || text.string().length == 0) {
          csize = font().getTextExtent("M");
        } else {
          csize = font().getTextExtent(String(text));
        }
        break;
      case NSCellType.NSImageCellType.value:
        if (m_image == null) {
          csize = NSSize.ZeroSize;
        } else {
          csize = m_image.size();
        }
        break;
      case NSCellType.NSNullCellType.value:
        csize = NSSize.ZeroSize;
        break;
    }
    
    csize.width += (borderSize.width * 2);
    csize.height += (borderSize.height * 2);
    return csize;
  }
  
  public function cellSizeForBounds(rect:NSRect):NSSize {
    if (m_type == NSCellType.NSTextCellType) {
      //! Resize text to fit into supplied rect
    }
    return cellSize();
  }
  
  public function drawingRectForBounds(rect:NSRect):NSRect {
    var borderSize:NSSize;
    if (m_bordered) {
      borderSize = NSBorderType.NSLineBorder.size;
    } else if(m_bezeled) {
      borderSize = NSBorderType.NSBezelBorder.size;;
    } else {
      borderSize = NSSize.ZeroSize;
    }
    return rect.insetRect(borderSize.width, borderSize.height);
  }
  
  public function imageRectForBounds(rect:NSRect):NSRect {
    return drawingRectForBounds(rect);
  }
  
  public function titleRectForBounds(rect:NSRect):NSRect {
    if (m_type == NSCellType.NSTextCellType) {
      var frame:NSRect = drawingRectForBounds(rect);
      if (m_bordered || m_bezeled) {
        return frame.insetRect(3,1);
      }
    } else {
      return rect.clone();
    }
  }
  
  // Changing the cell’s control size does not change the font of the cell. 
  // Use the NSFont class method systemFontSizeForControlSize: to obtain the 
  // system font based on the new control size and set it.
  public function setControlSize(csize:NSControlSize) {
    //! Change font?
    m_controlSize = csize;
  }
  
  public function controlSize():NSControlSize {
    return m_controlSize;
  }

  // Drawing and highlighting cells
  
  /**
   * Draws the border of the cell, then draws the "inside" of the cell, then
   * draws the inside of the cell by calling drawInteriorWithFrameInView.
   */
  public function drawWithFrameInView(cellFrame:NSRect, inView:NSView) {
    if (cellFrame.isEmptyRect() || inView.window()==null) {
      return;
    }
    var x:Number = cellFrame.origin.x;
    var y:Number = cellFrame.origin.y;
    var width:Number = cellFrame.size.width;
    var height:Number = cellFrame.size.height;
    var mc:MovieClip = inView.mcBounds();
    if(m_bordered) {
      mc.lineStyle(1, 0x696E79, 100);
      mc.moveTo(x, y);
      mc.lineTo(x + width, y);
      mc.lineTo(x + width, y + height);
      mc.lineTo(x, y + height);
      mc.lineTo(x, y);
    } else if (m_bezeled) {
      mc.lineStyle(1, 0xF6F8F9, 100);
      mc.moveTo(x, y);
      mc.lineTo(x + width, y);
      mc.lineStyle(1, 0x696E79, 100);
      mc.lineTo(x + width, y + height);
      mc.lineTo(x, y + height);
      mc.lineStyle(1, 0xF6F8F9, 100);
      mc.lineTo(x, y);
    }
    drawInteriorWithFrameInView(cellFrame, inView);
  }

  /**
   * Draws the "inside" of the cell. No border is drawn.
   */
  public function drawInteriorWithFrameInView(cellFrame:NSRect, inView:NSView) {
    if (inView.window() == null) {
      return;
    }
    cellFrame = drawingRectForBounds(cellFrame);
    if (m_bordered || m_bezeled) { // inset a bit more
      cellFrame = cellFrame.insetRect(3,1);
    }
    if(m_type == NSCellType.NSTextCellType) {
      //! draw attributedStringValue();
    } else if (m_type == NSCellType.NSImageCellType) {
      var size:NSSize = m_image.size();
      var position:NSPoint = new NSPoint(cellFrame.midX() - (size.width/2), cellFrame.midY() - (size.height/2));
      if (position.x < 0) {
        position.x = 0;
      }
      if (position.y < 0) {
        position.y = 0;
      }
      m_image.lockFocus(inView.mcBounds());
      m_image.drawAtPoint(position);
      m_image.unlockFocus();
    }
  }
  
  public function setControlView(view:NSView) {
    m_controlView = view;
  }

  public function controlView():NSView {
    return m_controlView;
  }
  
  public function highlightWithFrameInView(value:Boolean, frame:NSRect, inView:NSView) {
    if (m_highlighted != value) {
      m_highlighted = value;
    }
    drawWithFrameInView(frame, inView);
  }
  
  public function setHighlighted(value:Boolean) {
    m_highlighted = value;
  }
  
  public function isHighlighted():Boolean {
    return m_highlighted;
  }

  public function setControlTint(tint:NSControlTint) {
    m_controlTint = tint;
  }

  public function controlTint():NSControlTint {
    return m_controlTint;
  }
  
  //Editing and selecting cell text
  
  public function editWithFrameInViewEditorDelegateEvent(frame:NSRect, controlView:NSView, editor:NSText, delegate:Object, event:NSEvent) {
    
  }
  
  public function selectWithFrameInViewEditorDelegateStartLength(frame:NSRect, controlView:NSView, editor:NSText, delegate:Object, start:Number, length:Number) {
  }
  
  public function endEditing(editor:NSText) {
  }
  
  public function setsendsActionOnEndEditing(value:Boolean) {
    m_sendsActionOnEndEditing = value;
  }
  
  public function sendsActionOnEndEditing():Boolean {
    return m_sendsActionOnEndEditing;
  }
  
  public function description():String {
    return "NSCell()";
  }
}
  