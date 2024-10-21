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
import org.actionstep.NSView;
import org.actionstep.NSRect;
import org.actionstep.NSEvent;
import org.actionstep.NSPoint;
import org.actionstep.NSSize;
import org.actionstep.NSFont;
import org.actionstep.NSColor;
import org.actionstep.ASTheme;
import org.actionstep.NSArray;
import org.actionstep.NSScrollView;

import org.actionstep.ASListView;
import org.actionstep.ASListItem;

import org.actionstep.constants.NSBorderType;

class org.actionstep.ASList extends NSControl {
  
  private var m_borderType:NSBorderType;
  private var m_internalList:NSArray;
  private var m_scrollView:NSScrollView;
  private var m_multisel:Boolean;
  private var m_listView:ASListView;
  private var m_target:Object;
  private var m_action:String;
  private var m_showsFirstResponder:Boolean;
  private var m_firstResponderClip:MovieClip;
  
  public function initWithFrame(rect:NSRect):ASList {
    super.initWithFrame(rect);
    m_internalList = new NSArray();
    m_scrollView = new NSScrollView();
    m_scrollView.initWithFrame(new NSRect(0,0,rect.size.width, rect.size.height));
    m_scrollView.setHasVerticalScroller(true);
    addSubview(m_scrollView);
    m_listView = new ASListView();
    m_listView.initWithList(this);
    m_scrollView.setDocumentView(m_listView);
    m_showsFirstResponder = false;
    return this;
  }
  
  // Responder chain
  
  public function becomeFirstResponder():Boolean {
    m_showsFirstResponder = true;
    setNeedsDisplay(true);
    return true;
  }

  public function acceptsFirstResponder():Boolean {
    return true;
  }

  public function resignFirstResponder():Boolean {
    m_showsFirstResponder = false;
    setNeedsDisplay(true);
    return true;
  }

  public function becomeKeyWindow() {
    m_showsFirstResponder = true;
    setNeedsDisplay(true);
  }

  public function resignKeyWindow() {
    m_showsFirstResponder = false;
    setNeedsDisplay(true);
  }
  
  // configure display
  
  public function setShowsFirstResponder(value:Boolean) {
    m_showsFirstResponder = value;
  }
  
  public function setShowListItemImages(value:Boolean) {
    m_listView.setShowListItemImages(value);
  }
  
  public function showListItemImages():Boolean {
    return m_listView.showListItemImages();
  }
  
  public function setHasVerticalScroller(value:Boolean) {
    m_scrollView.setHasVerticalScroller(value);
  }
  
  public function hasVericalScroller():Boolean {
    return m_scrollView.hasVerticalScroller();
  }
  
  public function setBorderType(value:NSBorderType) {
    m_scrollView.setBorderType(value);
  }

  public function borderType():NSBorderType {
  	return m_scrollView.borderType();
  }
  
  public function setFont(font:NSFont) {
    m_listView.setFont(font);
  }
  
  public function font():NSFont {
    return m_listView.font();
  }

  public function setFontColor(color:NSColor) {
    m_listView.setFontColor(color);
  }

  public function fontColor():NSColor {
    return m_listView.fontColor();
  }
  
  public function setIndent(value:Number) {
    m_listView.setIndent(value);
  }
  
  public function indent():Number {
    return m_listView.indent();
  }

  /**
   * @see org.actionstep.NSView#setFrame
   */	
  public function setFrame(rect:NSRect) {
  	super.setFrame(rect);
  	m_scrollView.setFrameSize(new NSSize(rect.size.width, rect.size.height));
  	setNeedsDisplay(true);
  }

  /**
   * @see org.actionstep.NSView#setFrameSize
   */
  public function setFrameSize(size:NSSize) {
  	super.setFrameSize(size);
  	m_scrollView.setFrameSize(new NSSize(size.width, size.height));
  	setNeedsDisplay(true);
  }
  
  /** 
   * Returns whether multiple selection is supported by the list. TRUE is
   * multiple selection, FALSE is single selection.
   *
   * The default value is FALSE.
   */
  public function multipleSelection():Boolean {
    return m_listView.multipleSelection();
  }
  
  public function setNextKeyView(view:NSView) {
    m_listView.setNextKeyView(view);
    super.setNextKeyView(view);
  }

  /**
   * Sets whether multiple selection is supported by the list. TRUE allows
   * multiple selection, FALSE is single selection only.
   *
   * The default value is FALSE.
   */
  public function setMultipleSelection(flag:Boolean):Void {
    m_listView.setMultipleSelection(flag);
  }
  
  public function description():String {
		return "ASList()";
	}
	
	// Managing Items

	public function addItem(item:ASListItem):Void {
		m_internalList.addObject(item);
		m_listView.computeHeight();
	}

	public function addItemWithLabelData(label:String, data:Object):ASListItem {
	  var item:ASListItem = ASListItem.listItemWithLabelData(label, data);
	  addItem(item);
	  return item;
	}
	
	public function addItems(items:Array):Void {
	  for (var i:Number = 0;i < items.length;i++) {
	    m_internalList.addObject(items[i]);
	  }
	  m_listView.computeHeight();
	}
	
	public function addItemsFromNSArray(items:NSArray) {
	  addItems(items.internalList());
	}

	public function addItemsWithLabelsData(labels:Array, data:Array):Void {
	  var item:ASListItem;
	  for (var i:Number = 0;i < labels.length;i++) {
	    m_internalList.addObject(ASListItem.listItemWithLabelData(labels[i], data[i]));
	  }
	  m_listView.computeHeight();
	}
	
	/**
	 * Inserts an item into the list.
	 *
	 * A warning is logged if usesDataSource is TRUE.
	 */
	public function insertItemAtIndex(item:ASListItem, index:Number):Void {
		m_internalList.insertObjectAtIndex(item, index);
		m_listView.computeHeight();
	}

	public function insertItemWithLabelDataAtIndex(label:String, data:Object, index:Number):ASListItem {
	  var item:ASListItem = ASListItem.listItemWithLabelData(label, data);
		insertItemAtIndex(item, index);
		return item;
	}
	
	public function itemAtIndex(index:Number):ASListItem {
	  return ASListItem(m_internalList.objectAtIndex(index));
	}
	
	public function indexOfItem(item:ASListItem):Number {
	  return m_internalList.indexOfObject(item);
	}
	
	public function itemWithData(data:Object):ASListItem {
	  var items:Array = m_internalList.internalList();
	  var length:Number = items.length;
	  for(var i:Number = 0;i < length;i++) {
	    if (items[i].data() == data) {
	      return items[i];
	    }
	  }
	  return null;
	}

	/**
	 * Returns the internal data structure used by the list.
	 *
	 */
	public function items():NSArray {
		return m_internalList;
	}
	

	
	public function setSendsActionOnEnterOnly(value:Boolean) {
	  m_listView.setSendsActionOnEnterOnly(value);
	}
	
	public function sendsActionOnEnterOnly():Boolean {
	  return m_listView.sendsActionOnEnterOnly();
	}

	/**
	 * Removes all the items from the list.
	 *
	 */
	public function removeAllItems():Void {
		var items:Array = m_internalList.internalList();
		var length:Number = items.length;
		for(var i:Number = 0;i < length;i++) {
		  if (items[i].isSelected()) {
		    items[i].setSelected(false);
		  }
		}
		m_internalList.clear();
		m_listView.computeHeight();
	}
	
	/**
	 * Removes the object at position index from the list.
	 *
	 */	
	public function removeItemAtIndex(index:Number):Void {
		m_internalList.removeObjectAtIndex(index);
		m_listView.computeHeight();
	}

	public function removeItem(item:ASListItem):Void {
		m_internalList.removeObject(item);
	  if (item.isSelected()) {
	    item.setSelected(false);
	  }
		m_listView.computeHeight();
	}
	
	public function refresh():Void {
	  m_listView.computeHeight();
	  m_listView.setNeedsDisplay(true);
	}

	/**
	 * Returns the number of items in the list.
	 */
	public function numberOfItems():Number {
		return m_internalList.count();
	}

	public function numberOfVisibleItems():Number {
		return visibleItems().length;
	}
	
	public function itemHeight():Number {
	  return m_listView.itemHeight();
	}
	
	public function scrollItemAtIndexToVisible(index:Number) {
	  if (index == NSNotFound) {
	    return;
	  }
	  var bounds:NSRect = m_scrollView.contentView().bounds();
	  var minY:Number = bounds.minY();
	  var maxY:Number = bounds.maxY();
	  var itemHeight:Number = m_listView.itemHeight();
	  var y:Number = m_listView.indexToLocation(index);
	  if (y < minY) {
	    m_scrollView.contentView().scrollToPoint(new NSPoint(0, y));
	    m_scrollView.reflectScrolledClipView(m_scrollView.contentView());
	  } else if ((y+itemHeight) > maxY) {
	    m_scrollView.contentView().scrollToPoint(new NSPoint(0, minY + (y+itemHeight-maxY)+3));
	    m_scrollView.reflectScrolledClipView(m_scrollView.contentView());
	  }
	}

	public function scrollItemAtIndexToTop(index:Number) {
	  if (index == NSNotFound) {
	    return;
	  }
	  var bounds:NSRect = m_scrollView.contentView().bounds();
	  var minY:Number = bounds.minY();
	  var maxY:Number = bounds.maxY();
	  var y:Number = m_listView.indexToLocation(index);
	  m_scrollView.contentView().scrollToPoint(new NSPoint(0, y));
	  m_scrollView.reflectScrolledClipView(m_scrollView.contentView());
	}
	
	public function selectItem(item:ASListItem) {
	  var items:Array = visibleItems();
	  var length:Number = items.length;
	  var index:Number = NSNotFound;
	  for(var i:Number = 0;i < length;i++) {
	    if (items[i] == item) {
	      index = i;
	      break;
	    }
	  }
	  if (index != NSNotFound) {
	    m_listView.selectItemAtIndex(index);
	  }
	}

	public function selectedItem():ASListItem {
	  if (m_listView.multipleSelection()) {
	    trace(asWarning("ASList allows mutliple selections but single item selection requested."));
	  }
	  var items:Array = m_internalList.internalList();
	  var length:Number = items.length;
	  for(var i:Number = 0;i < length;i++) {
      if (items[i].isSelected()) {
        return ASListItem(items[i]);
      }
    }
    return null;
	}

	public function selectedItems():Array {
	  if (!m_listView.multipleSelection()) {
	    trace(asWarning("ASList does not allow mutliple selections but multiple item selections requested."));
	  }
	  var result:Array = new Array();
	  var items:Array = m_internalList.internalList();
	  var length:Number = items.length;
	  for(var i:Number = 0;i < length;i++) {
	    if (items[i].isSelected()) {
	      result.push(items[i]);
	    }
	  }
	  return result;
	}
	
	public function visibleItems():Array {
	  var result:Array = new Array();
	  var items:Array = m_internalList.internalList();
	  var length:Number = items.length;
	  for(var i:Number = 0;i < length;i++) {
	    if (items[i].isVisible()) {
	      result.push(items[i]);
	    }
	  }
	  return result;
	}

	public function invisibleItems():Array {
	  var result:Array = new Array();
	  var items:Array = m_internalList.internalList();
	  var length:Number = items.length;
	  for(var i:Number = 0;i < length;i++) {
	    if (!items[i].isVisible()) {
	      result.push(items[i]);
	    }
	  }
	  return result;
	}
	
	public function deselectAllItems() {
	  var updated:Boolean = false;
	  var items:Array = m_internalList.internalList();
	  var length:Number = items.length;
	  for(var i:Number = 0;i < length;i++) {
	    if (items[i].isSelected()) {
        items[i].setSelected(false);
        updated = true;
      }
	  }
	  if (updated) {
  	  m_listView.computeHeight();
  	  m_listView.setNeedsDisplay(true);
  	}
	}
	
	public function mouseUp(event:NSEvent) {
	  var location:NSPoint = event.mouseLocation;
	  location = convertPointFromView(location);
	  m_window.makeFirstResponder(this);
	  if (selectedItem() != null) {
	    deselectAllItems();
  	  sendActionTo(action(), target());
  	}
	}

	public function keyDown(event:NSEvent) {
	  var char:Number = event.keyCode;
	  switch (char) {
	    case NSUpArrowFunctionKey:
	    case NSDownArrowFunctionKey:
	    case NSEnterCharacter:
	    case NSEscapeCharacter:
	      m_listView.keyDown(event);
	      return;
	  }
	  super.keyDown(event);
	}
	
	// Drawing
	
	public function drawRect(rect:NSRect) {
	  mcBounds().clear();
	  ASTheme.current().drawListWithRectInView(rect, this);
	  if (m_showsFirstResponder) {
	    if (m_firstResponderClip == null || m_firstResponderClip._parent == undefined) {
	      m_firstResponderClip = m_mcBounds.createEmptyMovieClip("m_firstResponderClip", MaxClipDepth - 10);
	      m_firstResponderClip._x = 0;
	      m_firstResponderClip._y = 0;
	    }
	    m_firstResponderClip.clear();
      ASTheme.current().drawFirstResponderWithRectInClip(rect, m_firstResponderClip);
	  } else {
	    if (m_firstResponderClip != null) {
	      m_firstResponderClip.removeMovieClip();
	      m_firstResponderClip = null;
	    }
	  }
	}
	
	// Target/Action
	
	// Implementing the target/action mechanism

	public function action():String {
	  return m_action;
	}

	public function setAction(action:String) {
	  m_action = action;
	}

	public function target():Object {
	  return m_target;
	}

	public function setTarget(target:Object) {
	  m_target = target;
	}
}