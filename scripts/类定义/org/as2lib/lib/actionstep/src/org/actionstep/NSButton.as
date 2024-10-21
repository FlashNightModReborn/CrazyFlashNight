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
 
import org.actionstep.NSControl;
import org.actionstep.NSRect;
import org.actionstep.NSButtonCell;
import org.actionstep.NSAttributedString;
import org.actionstep.NSImage;
import org.actionstep.NSEvent;
import org.actionstep.NSSound;

import org.actionstep.constants.NSButtonType;
import org.actionstep.constants.NSCellImagePosition;
import org.actionstep.constants.NSBezelStyle;

class org.actionstep.NSButton extends NSControl {
  
  private static var g_cellClass:Function = org.actionstep.NSButtonCell;
  
  public static function cellClass():Function {
    return g_cellClass;
  }
  
  public static function setCellClass(cellClass:Function) {
    if (cellClass == null) {
      g_cellClass = org.actionstep.NSButtonCell;
    } else {
      g_cellClass = cellClass;
    }
  }
  
  public function setButtonType(type:NSButtonType) {
    NSButtonCell(m_cell).setButtonType(type);
    setNeedsDisplay(true);
  }
  
  public function initWithFrame(rect:NSRect):NSButton {
    super.initWithFrame(rect);
    return this;
  }
  
  // Setting the state
  
  public function allowsMixedState():Boolean {
    return m_cell.allowsMixedState();
  }
  
  public function setAllowsMixedState(value:Boolean) {
    m_cell.setAllowsMixedState(value);
  }
  
  public function setNextState() {
    m_cell.setNextState();
    setNeedsDisplay(true);
  }
  
  public function setState(state:Number) {
    m_cell.setState(state);
  }
  
  public function state():Number {
    return m_cell.state();
  }
  
  // Setting the repeat interval

  public function getPeriodicDelayInterval():Object {
    return NSButtonCell(m_cell).getPeriodicDelayInterval();
  }

  public function setPeriodicDelayInterval(delay:Number, interval:Number) {
    NSButtonCell(m_cell).setPeriodicDelayInterval(delay, interval);
  }

  
  // Setting the titles
  
  public function setAlternateTitle(value:String) {
    NSButtonCell(m_cell).setAlternateTitle(value);
    setNeedsDisplay(true);
  }
  
  public function alternateTitle():String {
    return NSButtonCell(m_cell).alternateTitle();
  }

  public function setTitle(value:String) {
    NSButtonCell(m_cell).setTitle(value);
    setNeedsDisplay(true);
  }

  public function title():String {
    return NSButtonCell(m_cell).title();
  }
  
  public function setAttributedTitle(value:NSAttributedString) {
    NSButtonCell(m_cell).setAttributedTitle(value);
    setNeedsDisplay(true);
  }

  public function attributedTitle():NSAttributedString {
    return NSButtonCell(m_cell).attributedTitle();
  }

  public function setAttributedAlternateTitle(value:NSAttributedString) {
    NSButtonCell(m_cell).setAttributedAlternateTitle(value);
    setNeedsDisplay(true);
  }

  public function attributedAlternateTitle():NSAttributedString {
    return NSButtonCell(m_cell).attributedAlternateTitle();
  }
  
  // Setting the images
  
  public function alternateImage():NSImage {
    return NSButtonCell(m_cell).alternateImage();
  }
  
  public function image():NSImage {
    return NSButtonCell(m_cell).image();
  }
  
  public function imagePosition():NSCellImagePosition {
    return NSButtonCell(m_cell).imagePosition();
  }
  
  public function setAlternateImage(image:NSImage) {
    NSButtonCell(m_cell).setAlternateImage(image);
    setNeedsDisplay(true);
  }
  
  public function setImage(image:NSImage) {
    NSButtonCell(m_cell).setImage(image);
    setNeedsDisplay(true);
  }
  
  public function setImagePosition(position:NSCellImagePosition) {
    NSButtonCell(m_cell).setImagePosition(position);
    setNeedsDisplay(true);
  }
  
  // Modifying graphics attributes
  
  public function bezelStyle():NSBezelStyle {
    return NSButtonCell(m_cell).bezelStyle();
  }
  
  public function isBordered():Boolean {
    return NSButtonCell(m_cell).isBordered();
  }

  public function isTransparent():Boolean {
    return NSButtonCell(m_cell).isTransparent();
  }
  
  public function setBordered(value:Boolean) {
    NSButtonCell(m_cell).setBordered(value);
    setNeedsDisplay(true);
  }

  public function setBezelStyle(style:NSBezelStyle) {
    NSButtonCell(m_cell).setBezelStyle(style);
    setNeedsDisplay(true);
  }
  
  public function setShowsBorderOnlyWhileMouseInside(value:Boolean) {
    NSButtonCell(m_cell).setShowsBorderOnlyWhileMouseInside(value);
    setNeedsDisplay(true);
  }
  
  public function setTransparent(value:Boolean) {
    NSButtonCell(m_cell).setTransparent(value);
    setNeedsDisplay(true);
  }

  public function showsBorderOnlyWhileMouseInside():Boolean {
    return NSButtonCell(m_cell).showsBorderOnlyWhileMouseInside();
  }
  
  // Displaying
  
  public function highlight(value:Boolean) {
    m_cell.highlightWithFrameInView(value, m_bounds, this);
  }
  
  //Setting the key equivalent
  
  public function keyEquivalent():String {
    return NSButtonCell(m_cell).keyEquivalent();
  }

  public function keyEquivalentModifierMask():Number {
    return NSButtonCell(m_cell).keyEquivalentModifierMask();
  }  
  
  public function setKeyEquivalent(value:String) {
    NSButtonCell(m_cell).setKeyEquivalent(value);
  }  
  
  public function setKeyEquivalentModifierMask(value:Number) {
    NSButtonCell(m_cell).setKeyEquivalentModifierMask(value);
  }
  
  // Handling events and action messages
  
  public function performKeyEquivalent(event:NSEvent) {
    //!
  }
  
  // Playing sound
  
  public function setSound(sound:NSSound) {
    NSButtonCell(m_cell).setSound(sound);
  }
  
  public function sound():NSSound {
    return NSButtonCell(m_cell).sound();
  }
  
  // First responder
  
  public function becomeFirstResponder():Boolean {
    m_cell.setShowsFirstResponder(true);
    setNeedsDisplay(true);
    return true;
  }
  
  public function resignFirstResponder():Boolean {
    m_cell.setShowsFirstResponder(false);
    setNeedsDisplay(true);
    return true;
  }

  public function becomeKeyWindow() {
    m_cell.setShowsFirstResponder(true);
    setNeedsDisplay(true);
  }

  public function resignKeyWindow() {
    m_cell.setShowsFirstResponder(false);
    setNeedsDisplay(true);
  }
  
  public function keyDown(event:NSEvent) {
    var character:Number = event.keyCode;
    if ( (character ==  NSNewlineCharacter)
      	  || (character == NSEnterCharacter) 
      	  || (character == NSCarriageReturnCharacter)
      	  || (character == 32)) {
      performClick(this);
    } else {
      super.keyDown(event);
    }
  }

  public function acceptsFirstMouse(event:NSEvent):Boolean {
    return true;
  }
}