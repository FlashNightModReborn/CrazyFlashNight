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

import org.actionstep.NSTextFieldCell;
import org.actionstep.NSSize;
import org.actionstep.NSArray;
import org.actionstep.NSObject;
import org.actionstep.NSWindow;
import org.actionstep.ASList;
import org.actionstep.ASListItem;
import org.actionstep.NSRect;
import org.actionstep.NSControl;
import org.actionstep.NSPoint;
import org.actionstep.NSView;
import org.actionstep.NSImage;
import org.actionstep.NSButtonCell;
import org.actionstep.constants.NSBezelStyle;
import org.actionstep.constants.NSCellImagePosition;
import org.actionstep.ASTheme;

class org.actionstep.NSComboBoxCell extends NSTextFieldCell {
  
  private var m_hasVerticalScroller:Boolean;
  private var m_intercellSpacing:NSSize;
  private var m_isButtonBordered:Boolean;
  private var m_itemHeight:Number;
  private var m_numberOfVisibleItems:Number;
  private var m_dataSource:Object;
  private var m_usesDataSource:Boolean;
  private var m_internalList:NSArray;
  
  private var m_indexToMakeTop:Number;
  private var m_indexToMakeVisible:Number;
  private var m_completes:Boolean;
  
  public var m_popupWindow:NSWindow;
  
  private var m_buttonCell:NSButtonCell;
  
  public function NSComboBoxCell() {
    m_hasVerticalScroller = true;
    m_intercellSpacing = new NSSize(2,3);
    m_isButtonBordered = true;
    m_itemHeight = 14;
    m_numberOfVisibleItems = 5;
    m_usesDataSource = false;
    m_internalList = new NSArray();
    m_indexToMakeTop = -1;
    m_indexToMakeVisible = -1;
    m_completes = false;
    
    makeButtonCell();
  }
  
  private function makeButtonCell() {
    m_buttonCell = new NSButtonCell();
    m_buttonCell.setHighlightsBy(NSPushInCellMask | NSChangeGrayCellMask);
    m_buttonCell.setShowsStateBy(NSChangeBackgroundCellMask);
    m_buttonCell.setImageDimsWhenDisabled(true);
    
    
    //m_buttonCell.setHighlightsBy(NSChangeBackgroundCellMask | NSContentsCellMask);
    m_buttonCell.setImage(NSImage.imageNamed("NSScrollerDownArrow"));
    m_buttonCell.setAlternateImage(NSImage.imageNamed("NSHightlightedScrollerDownArrow"));
    m_buttonCell.setImagePosition(NSCellImagePosition.NSImageOnly);
    m_buttonCell.setBezelStyle(NSBezelStyle.NSShadowlessSquareBezelStyle);
    m_buttonCell.setBezeled(true);
  }
  
  // Setting display attributes

  public function hasVerticalScroller():Boolean {
    return m_hasVerticalScroller;
  }

  public function intercellSpacing():NSSize {
    return m_intercellSpacing;
  }

  public function isButtonBordered():Boolean {
    return m_isButtonBordered;
  }

  public function itemHeight():Number {
    return m_itemHeight;
  }

  public function numberOfVisibleItems():Number {
    return m_numberOfVisibleItems;
  }

  public function setButtonBordered(value:Boolean) {
    m_isButtonBordered = value;
    if (m_isButtonBordered) {
      m_buttonCell.setBezeled(true);
    } else {
      m_buttonCell.setBezeled(false);
    }
  }

  public function setHasVerticalScroller(value:Boolean) {
    m_hasVerticalScroller = value;
  }

  public function setIntercellSpacing(spacing:NSSize) {
    m_intercellSpacing = spacing;
  }

  public function setItemHeight(height:Number) {
    m_itemHeight = height;
  }

  public function setNumberOfVisibleItems(value:Number) {
    m_numberOfVisibleItems = value;
  }

  // Setting a data source

  public function dataSource():Object {
    return m_dataSource;
  } 

  public function setDataSource(object:Object) {
    m_dataSource = object;
  }

  public function setUsesDataSource(value:Boolean) {
    m_usesDataSource = value;
  }

  public function usesDataSource():Boolean {
    return m_usesDataSource;
  }

  // Working with an internal list

  public function addItemsWithObjectValues(objects:Array) {
    var size:Number = objects.length;
    for(var i:Number = 0;i < size; i++) {
      m_internalList.addObject(objects[i]);
    }
  }

  public function addItemWithObjectValue(object:Object) {
    m_internalList.addObject(object);
  }

  public function insertItemWithObjectValueAtIndex(object:Object, index:Number) {
    m_internalList.insertObjectAtIndex(object, index);
  }

  public function objectValues():NSArray {
    return NSArray.arrayWithNSArray(m_internalList);
  }

  public function removeAllItems() {
    m_internalList.removeAllObjects();
  }

  public function removeItemAtIndex(index:Number) {
    m_internalList.removeObjectAtIndex(index);
  }

  public function removeItemWithObjectValue(object:Object) {
    m_internalList.removeObject(object);
  }

  public function numberOfItems():Number {
    return m_internalList.count();
  }

  // Manipulating the displayed list

  public function indexOfItemWithObjectValue(object:Object):Number {
    return m_internalList.indexOfObject(object);
  }

  public function itemObjectValueAtIndex(index:Number):Object {
    return m_internalList.objectAtIndex(index);
  }

  public function noteNumberOfItemsChanged() {
    // update ?
  }

  public function reloadData() {
    // reload ?
  }

  public function scrollItemAtIndexToTop(index:Number) {
    m_indexToMakeTop = index;
  }

  public function scrollItemAtIndexToVisible(index:Number) {
    m_indexToMakeVisible = index;
  }
  
  // Manipulating the selection

  public function deselectItemAtIndex(index:Number) {
    setStringValue("");
  }

  public function indexOfSelectedItem():Number {
    var index:Number = indexOfItemWithStringValue(stringValue());
    return index;
  }

  public function objectValueOfSelectedItem():Object {
    return m_internalList.objectAtIndex(indexOfItemWithStringValue(stringValue()));
  }

  public function selectItemAtIndex(index:Number) {
    setStringValue(String(m_internalList.objectAtIndex(index)));
  }

  public function selectItemWithObjectValue(object:Object) {
    var index:Number = m_internalList.indexOfObject(object);
    if (index == NSNotFound) {
      return;
    }
    setStringValue(String(object));
  }
  
  public function indexOfItemWithStringValue():Number {
    var value:String = stringValue();
    var array:Array = m_internalList.internalList();
    for(var i:Number = 0;i<array.length;i++) {
      if (array[i] == value) {
        return i;
      }
    }
    return NSNotFound;
  }
  // Completing the text field

  public function completes():Boolean {
    return m_completes;
  }

  public function setCompletes(value:Boolean) {
    m_completes = value;
  }
  
  // Drawing
  
  private var m_buttonCellFrame:NSRect;
  
  public function drawWithFrameInView(cellFrame:NSRect, inView:NSView) {
    if (m_controlView != inView) {
      m_controlView = inView;
    }
    if (m_drawsBackground) {
      ASTheme.current().drawTextFieldWithRectInView(cellFrame, inView);
    }
    validateTextField(cellFrame);
    m_textField._y = cellFrame.origin.y + (cellFrame.size.height - m_font.getTextExtent("Why").height)/2;
    m_textField._width = cellFrame.size.width - cellFrame.size.height + 4 - m_textField._x;
    m_buttonCellFrame = new NSRect(m_textField._width, 1, cellFrame.size.height-2, cellFrame.size.height-2);
    m_buttonCell.drawWithFrameInView(m_buttonCellFrame, inView);
    if (m_showsFirstResponder || (m_popupWindow != null)) {
      ASTheme.current().drawFirstResponderWithRectInView(cellFrame, inView);
    }
  }
  
  // Event handling
  
  public function isPointInDropDownButton(point:NSPoint):Boolean {
    return m_buttonCellFrame.pointInRect(point);
  }
  
  public function showListWindow() {
    m_popupWindow = new NSWindow();
    var window:NSWindow = m_popupWindow;
    var cbFrame:NSRect = m_controlView.frame();
    var origin:NSPoint = m_controlView.superview().convertPointToView(cbFrame.origin, null);
    origin = origin.translate(0, cbFrame.size.height);
    window.initWithContentRectSwf(new NSRect(origin.x, origin.y, cbFrame.size.width, 200), m_controlView.window().swf());
    var list:ASList = new ASList();
    list.initWithFrame(new NSRect(0,0,cbFrame.size.width, 200));
    list.setHasVerticalScroller(m_hasVerticalScroller);
    var array:Array = m_internalList.internalList();
    var items:Array = new Array();
    for(var i:Number = 0;i<array.length;i++) {
      items.push((new ASListItem()).initWithLabelData(array[i].toString(), array[i]));
    }
    list.addItems(items);
    list.setSendsActionOnEnterOnly(true);
    window.setContentView(list);
    window.setInitialFirstResponder(list);
    var control:NSControl = NSControl(m_controlView);
    var self:NSComboBoxCell = this;
    var delegate:Object = new Object();
    delegate.windowDidDisplay = function(notification) {
      window.setContentSize(new NSSize(cbFrame.size.width, list.itemHeight()*self.numberOfVisibleItems()+3));
      window.setLevel(NSWindow.NSModalPanelWindowLevel);
      window.makeKeyWindow();
      window.makeMainWindow();
      list.setShowsFirstResponder(false);
      var index:Number = self.indexOfItemWithStringValue();
      if (index != NSObject.NSNotFound) {
        list.selectItem(list.visibleItems()[index]);
        list.scrollItemAtIndexToVisible(index);
      }
    };
    delegate.windowDidResignKey = function(notification) {
      if (self.m_popupWindow != undefined) {
        self.m_popupWindow = null;
        control.window().makeFirstResponder(control);
        window.close();
      }
    };
    delegate.windowDidResignMain = function(notification) {
      if (self.m_popupWindow != undefined) {
        self.m_popupWindow = null;
        control.window().makeFirstResponder(control);
        window.close();
      }
    };
    window.setDelegate(delegate);
    window.display();
    var listTarget:Object = new Object();
    listTarget.selected = function() {
      var item:ASListItem = list.selectedItem();
      if (item != null) {
        control.setStringValue(String(item.data()));
        control.sendActionTo(control.action(), control.target());
      }
      self.m_popupWindow = null;
      control.setNeedsDisplay(true);
      control.window().makeKeyWindow();
      control.window().makeMainWindow();
      control.window().makeFirstResponder(control);
      window.close();
    };
    list.setTarget(listTarget);
    list.setAction("selected");
  }
} 
