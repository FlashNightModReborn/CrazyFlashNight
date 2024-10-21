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
 
import org.actionstep.NSView;
import org.actionstep.NSCell;
import org.actionstep.NSFont;
import org.actionstep.NSFormatter;
import org.actionstep.NSRect;
import org.actionstep.NSText;
import org.actionstep.NSAttributedString;
import org.actionstep.NSEvent;
import org.actionstep.ASUtils;
import org.actionstep.NSApplication;

import org.actionstep.constants.NSTextAlignment;

class org.actionstep.NSControl extends NSView {

  // Notifications
  public static var NSControlTextDidBeginEditingNotification:Number = ASUtils.intern("NSControlTextDidBeginEditingNotification");
  public static var NSControlTextDidChangeNotification:Number = ASUtils.intern("NSControlTextDidChangeNotification");
  public static var NSControlTextDidEndEditingNotification:Number = ASUtils.intern("NSControlTextDidEndEditingNotification");
  
  private static var g_cellClass:Function;
  private static var g_actionCellClass:Function;

  private var m_trackingData:Object;
	private var m_app:NSApplication;

  /**
   * Sets the cell class.
   *
   * NOTE: Must be overridden in subclasses.
   */
  public static function setCellClass(klass:Function) {
    g_cellClass = klass;
  }

  /**
   * Returns the cell class.
   *
   * NOTE: Must be overridden in subclasses.
   */  
  public static function cellClass():Function {
    if (g_cellClass == undefined) {
      g_cellClass = org.actionstep.NSCell;
    }
    return g_cellClass;
  }

  public static function setActionCellClass(klass:Function) {
    g_actionCellClass = klass;
  }

  public static function actionCellClass():Function {
    if (g_actionCellClass == undefined) {
      g_actionCellClass = org.actionstep.NSActionCell;
    }
    return g_actionCellClass;
  }
  
  private var m_cell:NSCell;
  private var m_tag:Number;
  private var m_ignoresMultiClick:Boolean;
  
  public function initWithFrame(theFrame:NSRect):NSControl {
    super.initWithFrame(theFrame);
		//doesn't work if in declaration
		m_app = NSApplication.sharedApplication();
    m_cell = new (this.getClass().cellClass())();
    m_cell.init();
    return this;
  }
  
  public function cell():NSCell {
    return m_cell;
  }
  
  public function setCell(newCell:NSCell) {
    if (!(newCell instanceof org.actionstep.NSCell)) {
      throw new Error("Provided cell is not an instance of the cell class");
    }
    m_cell = newCell;
  }
  
  // Enabling and disabling the control
  
  public function setEnabled(value:Boolean) {
    selectedCell().setEnabled(value);
    if (!value) {
      abortEditing();
    }
    setNeedsDisplay(true);
  }
  
  public function isEnabled():Boolean {
    return selectedCell().isEnabled();
  }
  
  // Identifying the selected cell
  
  public function selectedCell():NSCell {
    return m_cell;
  }
  
  public function selectedTag():Number {
    var cell:NSCell = selectedCell();
    if (cell == null) {
      return -1;
    }
    return cell.tag();
  }
  
  // Setting the control’s value
  
  public function doubleValue():Number {
    return selectedCell().doubleValue();
  }

  public function setDoubleValue(value:Number) {
    abortEditing();
    selectedCell().setDoubleValue(value);
    if(!(selectedCell() instanceof actionCellClass())) {
      setNeedsDisplay(true);
    }
  }

  public function floatValue():Number {
    return selectedCell().floatValue();
  }

  public function setFloatValue(value:Number) {
    abortEditing();
    selectedCell().setFloatValue(value);
    if(!(selectedCell() instanceof actionCellClass())) {
      setNeedsDisplay(true);
    }
  }

  public function intValue():Number {
    return selectedCell().intValue();
  }

  public function setIntValue(value:Number) {
    abortEditing();
    selectedCell().setIntValue(value);
    if(!(selectedCell() instanceof actionCellClass())) {
      setNeedsDisplay(true);
    }
  }

  public function stringValue():String {
    return selectedCell().stringValue();
  }

  public function setStringValue(value:String) {
    abortEditing();
    selectedCell().setStringValue(value);
    if(!(selectedCell() instanceof actionCellClass())) {
      setNeedsDisplay(true);
    }
  }
  
  public function objectValue():String {
    return String(selectedCell().objectValue());
  }

  public function setObjectValue(value:String) {
    abortEditing();
    selectedCell().setObjectValue(value);
    if(!(selectedCell() instanceof actionCellClass())) {
      setNeedsDisplay(true);
    }
  }
  
  // Interacting with other controls
  
  public function takeDoubleValueFrom(sender:Object) {
    selectedCell().takeDoubleValueFrom(sender);
    setNeedsDisplay(true);
  }

  public function takeFloatValueFrom(sender:Object) {
    selectedCell().takeFloatValueFrom(sender);
    setNeedsDisplay(true);
  }

  public function takeIntValueFrom(sender:Object) {
    selectedCell().takeIntValueFrom(sender);
    setNeedsDisplay(true);
  }

  public function takeObjectValueFrom(sender:Object) {
    selectedCell().takeObjectValueFrom(sender);
    setNeedsDisplay(true);
  }
  
  public function takeStringValueFrom(sender:Object) {
    selectedCell().takeStringValueFrom(sender);
    setNeedsDisplay(true);
  }
  
  // Formatting text
  
  public function alignment():NSTextAlignment {
    if (m_cell != null) {
      return m_cell.alignment();
    } else {
      return NSTextAlignment.NSNaturalTextAlignment;
    }
  }
  
  public function setAlignment(value:NSTextAlignment) {
    if (m_cell != null) {
      abortEditing();
      m_cell.setAlignment(value);
      if(!(m_cell instanceof actionCellClass())) {
        setNeedsDisplay(true);
      }
    }

  }
  
  public function font():NSFont {
    if (m_cell != null) {
      return m_cell.font();
    } else {
      return null;
    }
  }
  
  public function setFont(value:NSFont) {
    var currentEditor:NSText = currentEditor();
    if (m_cell != null) {
      if (currentEditor != null) { 
        currentEditor.setFont(value); 
      }
      m_cell.setFont(value);
    }
  }
  
  public function formatter():NSFormatter {
    return m_cell.formatter();
  }
  
  public function setFormatter(value:NSFormatter) {
    if (m_cell != null) {
      m_cell.setFormatter(value);
      if (!(m_cell instanceof g_actionCellClass)) {
        setNeedsDisplay(true);
      }
    }
  }
  
  // Managing the field editor
  
  public function abortEditing():Boolean {
    return false;
  }

  public function currentEditor():NSText {
    return null;
  }
  
  public function validateEditing() { 
  }
  
  // Resizing the control
  
  public function calcSize() { 
  }

  public function sizeToFit() { 
    setFrameSize(m_cell.cellSize());
  }
  
  // Displaying a cell
  
  public function selectCell(cell:NSCell) {
    if (cell == m_cell) {
      m_cell.setState(NSCell.NSOnState);
      setNeedsDisplay(true);
    }
  }
  
  public function drawRect(rect:NSRect) {
    drawCell(m_cell);
  }
  
  public function drawCell(cell:NSCell) {
    if (cell == m_cell) {
      mcBounds().clear();
      m_cell.drawWithFrameInView(m_bounds, this);
    }
  }
  
  public function drawCellInside(cell:NSCell) {
    if (cell == m_cell) {
      m_cell.drawInteriorWithFrameInView(m_bounds, this);
    }
  }

  public function updateCell(cell:NSCell) {
    setNeedsDisplay(true);
  }

  public function updateCellInside(cell:NSCell) {
    setNeedsDisplay(true);
  }
  
  // Implementing the target/action mechanism
  
  public function action():String {
    return m_cell.action();
  }
  
  public function setAction(value:String) {
    m_cell.setAction(value);
  }
  
  public function target():Object {
    return m_cell.target();
  }
  
  public function setTarget(target:Object) {
    m_cell.setTarget(target);
  }
  
  /**
   * Tells the NSApplication to trigger theAction in theTarget.
   *
   * If theAction is null, the call to sendActionTo is ignored. If theTarget
   * is null, NSApplication searches the responder chain for an object that 
   * can respond to the message.
   *
   * This method returns TRUE if a target responds to the message, and FALSE
   * otherwise.
   */
  public function sendActionTo(theAction:String, theTarget:Object):Boolean {
    if (theAction == null) {
      return false;
    }
    return m_app.sendActionToFrom(theAction, theTarget, this);
  }
  
  public function isContinuous():Boolean {
    return m_cell.isContinuous();
  }

  public function setContinuous(c:Boolean) {
    m_cell.setContinuous(c);
  }
  
  public function sendActionOn(mask:Number):Number {
    return m_cell.sendActionOn(mask);
  }
  
  // Getting and setting attributed string values
  
  public function setAttributedStringValue(attributedStringValue:NSAttributedString) {
    var sel:NSCell = selectedCell();
    abortEditing();
    sel.setAttributedStringValue(attributedStringValue);
    if (!(m_cell instanceof g_actionCellClass)) {
      setNeedsDisplay(true);
    }    
  }
  
  public function attributedString():NSAttributedString {
    var sel:NSCell = selectedCell();
    if (sel != null) {
      validateEditing();
      return sel.attributedStringValue();
    } else {
      return new NSAttributedString();
    }
  }

  // Setting and getting cell attributes

  public function setTag(value:Number) {
    m_tag = value;
  }

  public function tag():Number {
    return m_tag;
  }
  
  // Activating from the keyboard
  
  public function performClick() {
    m_cell.performClickWithFrameInView(bounds(), this);
  }
  
  public function refusesFirstResponder():Boolean {
    return selectedCell().refusesFirstResponder();
  }
  
  public function setRefusesFirstResponder(value:Boolean) {
    selectedCell().setRefusesFirstResponder(value);
  }
  
  public function acceptsFirstResponder():Boolean {
    return selectedCell().acceptsFirstResponder();
  }
  
  // Tracking the mouse
  
  private function cellTrackingRect():NSRect {
    return m_bounds;
  }
  
  public function mouseDown(event:NSEvent) {
    if (!isEnabled()) {
      return;
    }
    if (m_ignoresMultiClick && event.clickCount > 1) {
      super.mouseDown(event);
      return;
    }
    // This is necessary because of the async requirements of Flash
    m_cell.setTrackingCallbackSelector(this, "cellTrackingCallback");
    m_trackingData = { 
      mouseDown: true, 
      //actionMask: (m_cell.isContinuous() ? m_cell.sendActionOn(NSEvent.NSPeriodicMask) : m_cell.sendActionOn(0)),
      eventMask: NSEvent.NSLeftMouseDownMask | NSEvent.NSLeftMouseUpMask | NSEvent.NSLeftMouseDraggedMask
        | NSEvent.NSMouseMovedMask  | NSEvent.NSOtherMouseDraggedMask | NSEvent.NSRightMouseDraggedMask,
      mouseUp: false, 
      complete: false,
      bounds: cellTrackingRect()
    };
    mouseTrackingCallback(event);
  }
  
  public function cellTrackingCallback(mouseUp:Boolean) {
		//change--set highlight iff mouseUp
		setNeedsDisplay(true);
    if(mouseUp) {
			m_cell.setHighlighted(false);
      //m_cell.sendActionOn(m_trackingData.actionMask);	
      m_cell.setTrackingCallbackSelector(null, null);
    } else {
      m_app.callObjectSelectorWithNextEventMatchingMaskDequeue(this, "mouseTrackingCallback", m_trackingData.eventMask, true);
    }
  }
  
  public function mouseTrackingCallback(event:NSEvent) {
    if (event.type == NSEvent.NSLeftMouseUp) {
      m_cell.setHighlighted(false);
      setNeedsDisplay(true);
      //m_cell.sendActionOn(m_trackingData.actionMask);
      m_cell.setTrackingCallbackSelector(null, null);
			m_cell.mouseTrackingCallback(event);
      return;
    }
    if(event.view == this && cellTrackingRect().pointInRect(convertPointFromView(event.mouseLocation, null))) {
      m_cell.setHighlighted(true);
      setNeedsDisplay(true);
      m_cell.trackMouseInRectOfViewUntilMouseUp(event, m_trackingData.bounds, this, m_cell.getClass().prefersTrackingUntilMouseUp());
      return;
    }
    m_app.callObjectSelectorWithNextEventMatchingMaskDequeue(this, "mouseTrackingCallback", m_trackingData.eventMask, true);
  }
  
  public function setIgnoresMultiClick(value:Boolean) {
    m_ignoresMultiClick = value;
  }
  
  public function ignoresMultiClick():Boolean {
    return m_ignoresMultiClick;
  }
 
}