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

import org.actionstep.NSTextField;
import org.actionstep.NSComboBoxCell;
import org.actionstep.NSSize;
import org.actionstep.NSArray;
import org.actionstep.NSRect;
import org.actionstep.NSPoint;
import org.actionstep.NSEvent;

class org.actionstep.NSComboBox extends NSTextField {
  private static var g_cellClass:Function = NSComboBoxCell;

  public static function cellClass():Function {
    return g_cellClass;
  }

  public static function setCellClass(cellClass:Function) {
    if (cellClass == null) {
      g_cellClass = NSComboBoxCell;
    } else {
      g_cellClass = cellClass;
    }
  }
  
  public function NSComboBox() {
  }
  
  public function initWithFrame(rect:NSRect) {
    super.initWithFrame(rect);
  }
  
  // Setting display attributes
  
  public function hasVerticalScroller():Boolean {
    return NSComboBoxCell(m_cell).hasVerticalScroller();
  }
  
  public function intercellSpacing():NSSize {
    return NSComboBoxCell(m_cell).intercellSpacing();
  }
  
  public function isButtonBordered():Boolean {
    return NSComboBoxCell(m_cell).isButtonBordered();
  }
  
  public function itemHeight():Number {
    return NSComboBoxCell(m_cell).itemHeight();
  }
  
  public function numberOfVisibleItems():Number {
    return NSComboBoxCell(m_cell).numberOfVisibleItems();
  }
  
  public function setButtonBordered(value:Boolean) {
    NSComboBoxCell(m_cell).setButtonBordered(value);
    setNeedsDisplay(true);
  }
  
  public function setHasVerticalScroller(value:Boolean) {
    NSComboBoxCell(m_cell).setHasVerticalScroller(value);
  }
  
  public function setIntercellSpacing(spacing:NSSize) {
    NSComboBoxCell(m_cell).setIntercellSpacing(spacing);
  }
  
  public function setItemHeight(height:Number) {
    NSComboBoxCell(m_cell).setItemHeight(height);
  }
  
  public function setNumberOfVisibleItems(value:Number) {
    NSComboBoxCell(m_cell).setNumberOfVisibleItems(value);
  }
  
  // Setting a data source
  
  public function dataSource():Object {
    return NSComboBoxCell(m_cell).dataSource();
  } 
  
  public function setDataSource(object:Object) {
    NSComboBoxCell(m_cell).setDataSource(object);
  }
  
  public function setUsesDataSource(value:Boolean) {
    NSComboBoxCell(m_cell).setUsesDataSource(value);
  }
  
  public function usesDataSource():Boolean {
    return NSComboBoxCell(m_cell).usesDataSource();
  }
  
  // Working with an internal list
  
  public function addItemsWithObjectValues(objects:Array) {
    NSComboBoxCell(m_cell).addItemsWithObjectValues(objects);
  }
  
  public function addItemWithObjectValue(object:Object) {
    NSComboBoxCell(m_cell).addItemWithObjectValue(object);
  }
  
  public function insertItemWithObjectValueAtIndex(object:Object, index:Number) {
    NSComboBoxCell(m_cell).insertItemWithObjectValueAtIndex(object, index);
  }
  
  public function objectValues():NSArray {
    return NSComboBoxCell(m_cell).objectValues();
  }
  
  public function removeAllItems() {
    NSComboBoxCell(m_cell).removeAllItems();
  }
  
  public function removeItemAtIndex(index:Number) {
    NSComboBoxCell(m_cell).removeItemAtIndex(index);
  }
  
  public function removeItemWithObjectValue(object:Object) {
    NSComboBoxCell(m_cell).removeItemWithObjectValue(object);
  }
  
  public function numberOfItems():Number {
    return NSComboBoxCell(m_cell).numberOfItems();
  }
  
  // Manipulating the displayed list
  
  public function indexOfItemWithObjectValue(object:Object):Number {
    return NSComboBoxCell(m_cell).indexOfItemWithObjectValue(object);
  }
  
  public function itemObjectValueAtIndex(index:Number):Object {
    return NSComboBoxCell(m_cell).itemObjectValueAtIndex(index);
  }
  
  public function noteNumberOfItemsChanged() {
    NSComboBoxCell(m_cell).noteNumberOfItemsChanged();
  }
  
  public function reloadData() {
    NSComboBoxCell(m_cell).reloadData();
  }
  
  public function scrollItemAtIndexToTop(index:Number) {
    NSComboBoxCell(m_cell).scrollItemAtIndexToTop(index);
  }
  
  public function scrollItemAtIndexToVisible(index:Number) {
    NSComboBoxCell(m_cell).scrollItemAtIndexToVisible(index);
  }
  
  // Manipulating the selection
  
  public function deselectItemAtIndex(index:Number) {
    NSComboBoxCell(m_cell).deselectItemAtIndex(index);
  }
  
  public function indexOfSelectedItem():Number {
    return NSComboBoxCell(m_cell).indexOfSelectedItem();
  }
  
  public function objectValueOfSelectedItem():Object {
    return NSComboBoxCell(m_cell).objectValueOfSelectedItem();
  }
  
  public function selectItemAtIndex(index:Number) {
    NSComboBoxCell(m_cell).selectItemAtIndex(index);
  }
  
  public function selectItemWithObjectValue(object:Object) {
    NSComboBoxCell(m_cell).selectItemWithObjectValue(object);
  }
  
  // Completing the text field
  
  public function completes():Boolean {
    return NSComboBoxCell(m_cell).completes();
  }
  
  public function setCompletes(value:Boolean) {
    NSComboBoxCell(m_cell).setCompletes(value);
  }

  // Handle events

  public function mouseDown(event:NSEvent) {
    if (!isSelectable()) {
      super.mouseDown(event);
      return;
    }
    m_window.makeFirstResponder(this);
    var location:NSPoint = event.mouseLocation;
    location = convertPointFromView(location, null);
    if (NSComboBoxCell(m_cell).isPointInDropDownButton(location)) {
      NSComboBoxCell(m_cell).showListWindow();
    }
  }

  public function keyDown(event:NSEvent) {
    var mods:Number = event.modifierFlags;
    var char:Number = event.keyCode;

    switch (char) {
      case NSUpArrowFunctionKey:
      case NSDownArrowFunctionKey:
        NSComboBoxCell(m_cell).showListWindow();
        return;
    }
    super.keyDown(event);
  }


}