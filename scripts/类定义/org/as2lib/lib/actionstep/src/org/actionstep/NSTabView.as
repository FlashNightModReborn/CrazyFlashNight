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
import org.actionstep.NSArray;
import org.actionstep.NSPoint;
import org.actionstep.NSRect;
import org.actionstep.NSSize;
import org.actionstep.NSEvent;
import org.actionstep.NSFont;
import org.actionstep.NSTabViewItem;

import org.actionstep.constants.NSTabViewType;
import org.actionstep.constants.NSTabState;
import org.actionstep.constants.NSControlTint;
import org.actionstep.constants.NSControlSize;

class org.actionstep.NSTabView extends NSView {

  public static var TAB_HEIGHT:Number = 20;

  private var m_delegate:Object;
  private var m_selected:NSTabViewItem;
  private var m_selectedItem:Number;
  private var m_items:NSArray;
  private var m_font:NSFont;
  private var m_tabViewType:NSTabViewType;
  private var m_controlTint:NSControlTint;
  private var m_drawsBackground:Boolean;
  private var m_controlSize:NSControlSize;
  private var m_allowsTruncatedLabels:Boolean;
  
  public function NSTabView() {
    m_items = new NSArray();
    m_font = NSFont.systemFontOfSize(-1);
    m_drawsBackground = true;
    m_controlSize = NSControlSize.NSRegularControlSize;
    m_tabViewType = NSTabViewType.NSTopTabsBezelBorder;
    m_allowsTruncatedLabels = false;
  }
  
  // Adding and removing tabs
  
  public function addTabViewItem(item:NSTabViewItem) {
    insertTabViewItemAtIndex(item, m_items.count());
  }
  
  public function insertTabViewItemAtIndex(item:NSTabViewItem, index:Number) {
    item.setTabView(this);
    m_items.insertObjectAtIndex(item, index);
    if (m_delegate != null) {
      if(typeof(m_delegate["tabViewDidChangeNumberOfTabViewItems"]) == "function") {
        m_delegate["tabViewDidChangeNumberOfTabViewItems"].call(m_delegate, this);
      }
    }
  }
  
  public function removeTabViewItem(item:NSTabViewItem) {
    var loc:Number = m_items.indexOfObject(item);
    
    if (loc == NSNotFound) {
      return;
    }
    if (item == m_selected) {
      if (m_selectedItem > 0) {
        selectTabViewItemAtIndex(m_selectedItem - 1);
      } else if (m_selectedItem < (m_items.count() -1)) {
        selectTabViewItemAtIndex(m_selectedItem + 1);
      } else {
        m_selected.setTabState(NSTabState.NSBackgroundTab);
        m_selected.view().removeFromSuperview();
        m_selected = null;
        m_selectedItem = -1;
      }
    }
    m_items.removeObjectAtIndex(loc);
    if (m_delegate != null) {
      if(typeof(m_delegate["tabViewDidChangeNumberOfTabViewItems"]) == "function") {
        m_delegate["tabViewDidChangeNumberOfTabViewItems"].call(m_delegate, this);
      }
    }    
  }
  
  // Accessing tabs
  
  public function indexOfTabViewItem(item:NSTabViewItem):Number {
    return m_items.indexOfObject(item);
  }
  
  public function indexOfTabViewItemWithIdentifier(id:Object):Number {
    var element:NSTabViewItem;
    var i:Number = 0;
    while ((element = NSTabViewItem(m_items.objectAtIndex(i)))!= null) {
      if (element.identifier() == id) {
        return i;
      }
      i++;
    }
    return NSNotFound;
  }
  
  public function numberOfTabViewItems():Number {
    return m_items.count();
  }
  
  public function tabViewItemAtIndex(index:Number):NSTabViewItem {
    return NSTabViewItem(m_items.objectAtIndex(index));
  }
  
  public function selectFirstTabViewItem(sender:Object) {
    selectTabViewItemAtIndex(0);
  }
  
  public function selectLastTabViewItem(sender:Object) {
    selectTabViewItem(NSTabViewItem(m_items.lastObject()));
  }
  
  public function selectNextTabViewItem(sender:Object) {
    if ((m_selectedItem+1) < m_items.count()) {
      selectTabViewItemAtIndex(m_selectedItem + 1);
    }
  }

  public function selectPreviousTabViewItem(sender:Object) {
    if (m_selectedItem > 0) {
      selectTabViewItemAtIndex(m_selectedItem - 1);
    }
  }
  
  public function setFrame(rect:NSRect) {
    super.setFrame(rect);
    m_selected.view().setFrame(contentRect());
  }

  public function setFrameSize(size:NSSize) {
    super.setFrameSize(size);
    m_selected.view().setFrame(contentRect());
  }
  
  public function selectTabViewItem(item:NSTabViewItem) {
    if (m_delegate != null) {
      if(typeof(m_delegate["tabViewShouldSelectTabViewItem"]) == "function") {
        if (!m_delegate["tabViewShouldSelectTabViewItem"].call(m_delegate, this, item)) {
          return;
        }
      }
    }
    if (m_selected != null) {
      m_selected.setTabState(NSTabState.NSBackgroundTab);
      m_selected.view().removeFromSuperview();
    }
    
    m_selected = item;
    
    if(typeof(m_delegate["tabViewWillSelectTabViewItem"]) == "function") {
      m_delegate["tabViewWillSelectTabViewItem"].call(m_delegate, this, m_selected);
    }
    if (m_selected != null) {
      m_selectedItem = m_items.indexOfObject(m_selected);
      m_selected.setTabState(NSTabState.NSSelectedTab);
      var selectedView:NSView = m_selected.view();
      if (selectedView != null) {
        addSubview(selectedView);
        selectedView.setFrame(contentRect());
        m_window.makeFirstResponder(m_selected.initialFirstResponder());
      }
    }
    setNeedsDisplay(true);
    
    if(typeof(m_delegate["tabViewDidSelectTabViewItem"]) == "function") {
      m_delegate["tabViewDidSelectTabViewItem"].call(m_delegate, this, m_selected);
    }
  }
  
  public function selectTabViewItemAtIndex(index:Number) {
    if (index < 0) {
      selectTabViewItem(null);
    } else {
      selectTabViewItem(NSTabViewItem(m_items.objectAtIndex(index)));
    }
  }
  
  public function selectedTabViewItem():NSTabViewItem {
    return m_selected;
  }
  
  // Setting the font
  
  public function setFont(font:NSFont) {
    m_font = font;
  }
  
  public function font():NSFont {
    return m_font;
  }
  
  // Modifying the tab type
  
  public function setTabViewType(type:NSTabViewType) {
    m_tabViewType = type;
    setNeedsDisplay(true);
  }
  
  public function tabViewType():NSTabViewType {
    return m_tabViewType;
  }
  
  // Modifying controls tint
  
  public function controlTint():NSControlTint {
    return m_controlTint;
  }
  
  public function setControlTint(tint:NSControlTint) {
    m_controlTint = tint;
  }
  
  // Manipulating the background
  
  public function drawsBackground():Boolean {
    return m_drawsBackground;
  }
  
  public function setDrawsBackground(value:Boolean) {
    m_drawsBackground = value;
  }
  
  // Determining the size
  
  public function minimumSize():NSSize {
    return NSSize.ZeroSize;
  }
  
  public function contentRect():NSRect {
    var rect:NSRect = bounds();
    switch(m_tabViewType) {
    case NSTabViewType.NSBottomTabsBezelBorder:
    case NSTabViewType.NSTopTabsBezelBorder:
      rect.origin.y+=TAB_HEIGHT+5;
      rect.size.height-=(TAB_HEIGHT+10);
      rect.origin.x+=5;
      rect.size.width-=10;
      break;
    case NSTabViewType.NSNoTabsBezelBorder:
      rect.origin.y+=5;
      rect.size.height-=10;
      rect.origin.x+=5;
      rect.size.width-=10;
      break;
    case NSTabViewType.NSNoTabsLineBorder:
      rect.origin.y+=1;
      rect.size.height-=2;
      rect.origin.x+=1;
      rect.size.width-=2;
      break;
    case NSTabViewType.NSNoTabsNoBorder:
      break;
    }
    return rect;
  }
  
  public function controlSize():NSControlSize {
    return m_controlSize;
  }

  public function setControlSize(controlSize:NSControlSize) {
    m_controlSize = controlSize;
  }
  
  // Truncating tab labels
  
  public function allowsTruncatedLabels():Boolean {
    return m_allowsTruncatedLabels;
  }
  
  public function setAllowsTruncatedLabels(value:Boolean) {
    m_allowsTruncatedLabels = value;
  }
  
  public function isOpaque():Boolean {
    return false;
  }
  
  // Assigning a delegate
  
  public function setDelegate(delegate:Object) {
    m_delegate = delegate;
  }
  
  public function delegate():Object {
    return m_delegate;
  }
  
  // Event handling
  
  public function tabViewItemAtPoint(point:NSPoint):NSTabViewItem {
    var i:Number = 0;
    var tabViewItem:NSTabViewItem;
    while ( (tabViewItem=tabViewItemAtIndex(i)) != null) {
      if (tabViewItem.pointInTabItem(point)) {
        return tabViewItem;
      }
      i++;
    }
    return null;
  }

  public function mouseDown(event:NSEvent) {
    var location:NSPoint = event.mouseLocation.clone();
    mcBounds().globalToLocal(location);
    var item:NSTabViewItem = tabViewItemAtPoint(location);
    if (item != null && item != m_selected) {
      selectTabViewItem(item);
    }
  }

  // Drawing
  
  public function drawRect(rect:NSRect) {
    
    var i:Number = 0;
    var tabViewItem:NSTabViewItem;
    var tx:Number = 5;
    var labelSize:NSSize;
    var selectedRect:NSRect;
    var tabRect:NSRect = null;
    var fillColor:Number = 0xC6C6C6;
    var x:Number = rect.origin.x;
    var y:Number = rect.origin.y;
    var width:Number = rect.size.width-1;
    var height:Number = rect.size.height-1;
    
    m_mcBounds.clear();
    if (m_tabViewType == NSTabViewType.NSNoTabsNoBorder) {
      return;
    } else if (m_tabViewType == NSTabViewType.NSNoTabsLineBorder) {
      with (m_mcBounds) {
        lineStyle(1, 0, 100); 
        moveTo(x, y);
        lineTo(x+width, y);
        lineTo(x+width, y+height);
        lineTo(x, y+height);
        lineTo(x,y);
        endFill();
      }
      return;
    }
    
    while ( (tabViewItem=tabViewItemAtIndex(i)) != null) {
      labelSize = tabViewItem.sizeOfLabel();
      tabRect = new NSRect(x + tx, y, labelSize.width+14, TAB_HEIGHT);
      if (tabViewItem.tabState() == NSTabState.NSSelectedTab) {
        selectedRect = tabRect;
      }
      drawTabViewItemInRect(tabViewItem, tabRect);
      tx += labelSize.width+17;
      i++;
    }
    with (m_mcBounds) {
      beginFill(fillColor, 100);
      lineStyle(1, 0x8E8E8E, 100); 
      moveTo(x, y+TAB_HEIGHT);
      if (selectedRect != null) {
        lineTo(selectedRect.origin.x, y+TAB_HEIGHT);
        lineStyle(undefined, 0, 100); 
        lineTo(selectedRect.origin.x+selectedRect.size.width, y+TAB_HEIGHT);
        lineStyle(1, 0x8E8E8E, 100); 
      }
      lineTo(x+width, y+TAB_HEIGHT);
      lineTo(x+width, y+height);
      lineTo(x, y+height);
      lineTo(x,y+TAB_HEIGHT);
      endFill();
    }
  }

  // PRIVATE FUNCTIONS
  
  private function drawTabViewItemInRect(item:NSTabViewItem, rect:NSRect) {
    //function roundedRectangle(target_mc:MovieClip, boxWidth:Number, boxHeight:Number, cornerRadius:Number, fillColor:Number, fillAlpha:Number):Void {
    var fillColors:Array;
    var fillAlpha:Number = 100;
    var cornerRadius:Number = 3;
    if (item.tabState() == NSTabState.NSBackgroundTab) {
      fillColors = [0xBEBEBE, 0xA6A6A6];
    } else {
      fillColors = [0xDEDEDE, 0xC6C6C6];
    }
    var x:Number = rect.origin.x;
    var y:Number = rect.origin.y;
    var width:Number = rect.size.width;
    var height:Number = rect.size.height;
    with (m_mcBounds) {
      lineStyle(1.5, 0x8E8E8E, 100);
      beginGradientFill("linear", fillColors, [100,100], [0, 0xff], 
                        {matrixType:"box", x:x,y:y,w:width,h:height,r:(.5*Math.PI)});
      moveTo(x+cornerRadius, y);
      lineTo(x+width-cornerRadius, y);
      lineTo(x+width, y+cornerRadius); //Angle
      lineTo(x+width, y+height);
      lineStyle(undefined, 0, 100);
      lineTo(x, y+height);
      lineStyle(1.5, 0x8E8E8E, 100); 
      lineTo(x, y+cornerRadius);
      lineTo(x+cornerRadius, y); //Angle
      endFill();
    }
    item.drawLabelInRect(m_allowsTruncatedLabels, rect);
  }
}