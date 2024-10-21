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
 * ARE DISCLAIMED. IN false EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE 
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) 
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE 
 * POSSIBILITY OF SUCH DAMAGE.
 */
 
import org.actionstep.NSView;
import org.actionstep.NSPoint;
import org.actionstep.NSArray;
import org.actionstep.NSEvent;
import org.actionstep.NSRect;
import org.actionstep.NSFont;
//import org.actionstep.NSScreen;
import org.actionstep.NSSize;
import org.actionstep.NSWindow;
import org.actionstep.NSException;
import org.actionstep.NSColor;
import org.actionstep.NSNotification;
import org.actionstep.NSNotificationCenter;
import org.actionstep.ASDraw;

import org.actionstep.NSMenu;
import org.actionstep.NSMenuItem;
import org.actionstep.NSMenuItemCell;
import org.actionstep.NSTitleView;
import org.actionstep.constants.NSCellImagePosition;

class org.actionstep.NSMenuView extends NSView {
	private static var g_ht:Number;
	
	private var m_horizontal:Boolean;
	private var m_needsSizing:Boolean;
	
	private var m_highlightedItemIndex:Number;
	private var m_horizontalEdgePad:Number;
	private var m_stateImageOffset:Number;
	private var m_stateImageWidth:Number;
	private var m_imageAndTitleOffset:Number;
	private var m_imageAndTitleWidth:Number;
	private var m_keyEqOffset:Number;
	private var m_keyEqWidth:Number;
	private var m_leftBorderOffset:Number;
	
	private var m_attachedMenu:NSMenu;
	private var m_font:NSFont;
	private var m_itemsLink:NSArray;
	private var m_itemCells:NSArray;
	private var m_cellSize:NSSize;
	private var m_titleView:NSTitleView;
	
	private static function addLeftBorderOffsetToRect(aRect:NSRect) {
		aRect.origin.x--;
		aRect.size.width++;
	}
	
	/*
	 * Class methods.
	 */
	public static function menuBarHeight():Number {
		if(g_ht==null) {
			g_ht = 0;
		}
		if (g_ht == 0) {
			var font:NSFont = NSFont.menuFontOfSize(0);
	
			/* Should make up 23 for the default font */
			g_ht = font.getTextExtent("NSMV").height + 8;
			if (g_ht < 23) {
				g_ht = 23;
			}
		}
	
		return g_ht;
	}
	
	/*
	 * NSView overrides
	 */
	public function acceptsFirstMouse(theEvent:NSEvent):Boolean {
		return true;
	}
	
	// We do not want to popup menus in this menu.
	// overrides NSView
	public function menuForEvent(theEvent:NSEvent):NSMenu {
		trace(asDebug("Query for menu in view"));
		return null;
	}
	
	/*
	 * Init methods.
	 */
	public function initWithFrame(aFrame:NSRect):NSMenuView {
		super.initWithFrame(aFrame);
		
		setFont(NSFont.menuFontOfSize(15));
	
		m_highlightedItemIndex = -1;
		m_horizontalEdgePad = 4.;
	
		/* Set the necessary offset for the menuView. That is, how many pixels 
		 * do we need for our left side border line.
		 */
	 m_leftBorderOffset = 1;
	
		// Create an array to store our menu item cells.
		m_itemCells = new NSArray();
	
		return this;
	}
	
	public function initAsTearOff():NSMenuView {
		initWithFrame(NSRect.ZeroRect);
		
		if (m_attachedMenu) {
			m_attachedMenu.setTornOff(true);
		}
		return this;
	}
	
	public function dealloc():Void {
		// We must remove the menu view from the menu list of observers.
		if (m_attachedMenu != null) {
			NSNotificationCenter.defaultCenter().
			removeObserverNameObject
			(this, null, m_attachedMenu);
		}
	
		/* Clean the pointer to us stored into the m_itemCells.	*/
		m_itemCells.makeObjectsPerformSelectorWithObject
		("setMenuView", null);
	
		//super.dealloc();
	}
	
	/*
	 * Getting and Setting Menu View Attributes
	 */
	public function setMenu(menu:NSMenu):Void {
		var nc:NSNotificationCenter = NSNotificationCenter.defaultCenter();
	
		if (m_attachedMenu != null) {
			// Remove this menu view from the old menu list of observers.
			nc.removeObserverNameObject(this, null, m_attachedMenu);
		}
	
		/* menu is retaining us, so we should not be retaining menu.	*/
		m_attachedMenu = menu;
		m_itemsLink = m_attachedMenu.itemArray();
	
		if (m_attachedMenu != null) {
			// Add this menu view to the menu's list of observers.
			nc.addObserverSelectorNameObject
			(this, "itemChanged", NSMenu.NSMenuDidChangeItemNotification, m_attachedMenu);
	
			nc.addObserverSelectorNameObject
			(this, "itemAdded", NSMenu.NSMenuDidAddItemNotification, m_attachedMenu);
	
			nc.addObserverSelectorNameObject
			(this, "itemRemoved", NSMenu.NSMenuDidRemoveItemNotification, m_attachedMenu);
		}
	
		// Force menu view's layout to be recalculated.
		setNeedsSizing(true);
	
		update();
	}
	
	public function menu():NSMenu {
		return m_attachedMenu;
	}
	
	public function setHorizontal(flag:Boolean):Void {
		m_horizontal = flag;
	}
	
	public function isHorizontal():Boolean {
		return m_horizontal;
	}
	
	public function setFont(font:NSFont):Void {
		m_font = font;
		if (m_font != null) {
			var r:NSSize = m_font.getTextExtent("Hi");
			/* Should make up 110, 20 for default font */
			m_cellSize = new NSSize(r.width * 10, r.height + 6);
	
			if (m_cellSize.height < 20) {
				m_cellSize.height = 20;
			}
	
			setNeedsSizing(true);
		}
	}
	
	public function font():NSFont {
		return m_font;
	}
	
	public function setHighlightedItemIndex(index:Number):Void {
		var aCell:NSMenuItemCell;
	
		if (index == m_highlightedItemIndex) {
			return;
		}
		// Unhighlight old
		if (m_highlightedItemIndex != -1) {
			aCell	= NSMenuItemCell
			(m_itemCells.objectAtIndex(m_highlightedItemIndex));
			aCell.setHighlighted(false);
			setNeedsDisplayForItemAtIndex(m_highlightedItemIndex);
		}
	
		// Set ivar to new index.
		m_highlightedItemIndex = index;
	
		// Highlight new
		if (m_highlightedItemIndex != -1) {
			aCell	= NSMenuItemCell
			(m_itemCells.objectAtIndex(m_highlightedItemIndex));
			aCell.setHighlighted(true);
			setNeedsDisplayForItemAtIndex(m_highlightedItemIndex);
		} 
	}
	
	public function highlightedItemIndex():Number {
		return m_highlightedItemIndex;
	}
	
	public function setMenuItemCellForItemAtIndex
	(cell:NSMenuItemCell, index:Number):Void {
		var anItem:NSMenuItem = NSMenuItem
		(m_itemsLink.objectAtIndex(index));
		
		m_itemCells.replaceObjectAtIndexWithObject(index, cell);
	
		cell.setMenuItem(anItem);
		cell.setMenuView(this);
	
		if (highlightedItemIndex() == index) {
			cell.setHighlighted(true);
		} else {
			cell.setHighlighted(false);
		}
		// Mark the new cell and the menu view as needing resizing.
		cell.setNeedsSizing(true);
		setNeedsSizing(true);
	}
	
	public function menuItemCellForItemAtIndex(index:Number):NSMenuItemCell {
		return NSMenuItemCell
		(m_itemCells.objectAtIndex(index));
	}
	
	public function attachedMenuView():NSMenuView {
		return m_attachedMenu.attachedMenu().menuRepresentation();
	}
	
	public function attachedMenu():NSMenu {
		return m_attachedMenu.attachedMenu();
	}
	
	public function isAttached():Boolean {
		return m_attachedMenu.isAttached();
	}
	
	public function isTornOff():Boolean {
		return m_attachedMenu.isTornOff();
	}
	
	public function setHorizontalEdgePadding(pad:Number):Void {
		m_horizontalEdgePad = pad;
		setNeedsSizing(true);
	}
	
	public function horizontalEdgePadding():Number {
		return m_horizontalEdgePad;
	}
	
	/*
	 * Notification Methods
	 */
	public function itemChanged(notification:NSNotification):Void {
		var index:Number = notification.userInfo.objectForKey("NSMenuItemIndex");
		var aCell:NSMenuItemCell = NSMenuItemCell
		(m_itemCells.objectAtIndex(index));
	
		// Enabling of the item may have changed
		aCell.setEnabled(aCell.menuItem().isEnabled());
		// Mark the cell associated with the item as needing resizing.
		aCell.setNeedsSizing(true);
		setNeedsDisplayForItemAtIndex(index);
	
		// Mark the menu view as needing to be resized.
		setNeedsSizing(true);
	}
	
	public function itemAdded(notification:NSNotification):Void {
		var index:Number = notification.userInfo.objectForKey("NSMenuItemIndex");
		var anItem:NSMenuItem = NSMenuItem
		(m_itemsLink.objectAtIndex(index));
		var aCell:NSMenuItemCell = new NSMenuItemCell();
		var wasHighlighted:Number = m_highlightedItemIndex;
	
		aCell.setMenuItem(anItem);
		aCell.setMenuView(this);
		aCell.setFont(m_font);
	
		/* Unlight the previous highlighted cell if the index of the highlighted
		 * cell will be ruined up by the insertion of the new cell.	*/
		if (wasHighlighted >= index) {
			setHighlightedItemIndex(-1);
		}
		
		m_itemCells.insertObjectAtIndex(aCell, index);
		
		/* Restore the highlighted cell, with the new index for it.	*/
		if (wasHighlighted >= index) {
			/* Please note that if wasHighlighted == -1, it shouldn't be possible
			 * to be here.	*/
			setHighlightedItemIndex(++wasHighlighted);
		}
	
		aCell.setNeedsSizing(true);
		//RELEASE(aCell);
	
		// Mark the menu view as needing to be resized.
		setNeedsSizing(true);
	}
	
	public function itemRemoved(notification:NSNotification):Void {
		var wasHighlighted:Number = highlightedItemIndex();
		var index:Number = notification.userInfo.objectForKey("NSMenuItemIndex");
	
		if (index <= wasHighlighted) {
			setHighlightedItemIndex(-1);
		}
		m_itemCells.removeObjectAtIndex(index);
	
		if (wasHighlighted > index) {
			setHighlightedItemIndex(--wasHighlighted);
		}
		// Mark the menu view as needing to be resized.
		setNeedsSizing(true);
	}
	
	/*
	 * Working with Submenus.
	 */
	
	public function detachSubmenu():Void {
		var attachedMenu:NSMenu = m_attachedMenu.attachedMenu();
		var attachedMenuView:NSMenuView;
	
		if (!attachedMenu) {
			return;
		}
		attachedMenuView = attachedMenu.menuRepresentation();
	
		attachedMenuView.detachSubmenu();
	
		trace(asDebug("detach submenu: "+attachedMenu+" from: "+m_attachedMenu));
		
		if (attachedMenu.isTransient()) {
			attachedMenu.closeTransient();
		} else {
			attachedMenu.close();
		}
	}
	
	public function attachSubmenuForItemAtIndex(index:Number):Void {
		/*
		 * Transient menus are used for torn-off menus, which are already on the
		 * screen and for sons of transient menus.	As transients disappear as
		 * soon as we release the mouse the user will be able to leave submenus
		 * open on the screen and interact with other menus at the same time.
		 */
		var attachableMenu:NSMenu;
	
		if (index < 0) {
			return;
		}
	
		attachableMenu = m_itemsLink.objectAtIndex(index).submenu();
	
		if (attachableMenu.isTornOff() || m_attachedMenu.isTransient()) {
			trace(asDebug("Will open transient: "+attachableMenu));
			attachableMenu.displayTransient();
			attachableMenu.menuRepresentation().setHighlightedItemIndex(-1); 
		} else {
			trace(asDebug("Will open normal: "+attachableMenu));
			attachableMenu.display();
		}
	}
	
	/*
	 * Calculating Menu Geometry
	 */
	public function update():Void {
		trace(asDebug("update called on menu view"));
		
		if (!m_attachedMenu.ownedByPopUp() && !m_titleView) {
			// Add title view. If this menu not owned by popup
			//!
			//m_titleView = [GSTitleView alloc].initWithOwner:_attachedMenu();
			//addSubview(m_titleView);
			//RELEASE(m_titleView);
		} else if (m_attachedMenu.ownedByPopUp() && m_titleView) {
			// Remove title view if this menu owned by popup
			m_titleView.removeFromSuperview();
			m_titleView = null;
		}
	
		// Resize it anyway.
		sizeToFit();
	
		// Just quit here if we are a popup.
		if (m_attachedMenu.ownedByPopUp()) {
			return;
		}
		if (m_attachedMenu.isTornOff() && !m_attachedMenu.isTransient()) {
			m_titleView.addCloseButtonWithAction("_performMenuClose");
		} else {
			m_titleView.removeCloseButton();
		}
	}
	
	public function setNeedsSizing(flag:Boolean):Void {
		m_needsSizing = flag;
	}
	
	public function needsSizing():Boolean {
		return m_needsSizing;
	}
	
	public function sizeToFit():Void {
		var i:Number;
		var howMany:Number = m_itemCells.count();
		var wideTitleView:Number = 1;
		var neededImageAndTitleWidth:Number = 0;
		var neededKeyEquivalentWidth:Number = 0;
		var neededStateImageWidth:Number = 0;
		var accumulatedOffset:Number = 0;
		var popupImageWidth:Number = 0;
		var menuBarHeight:Number = 0;
	
		// Popup menu doesn't need title bar
		if (!m_attachedMenu.ownedByPopUp() && m_titleView) {
			menuBarHeight = menuBarHeight;
			neededImageAndTitleWidth = m_titleView.titleSize().width;
		} else {
			menuBarHeight += m_leftBorderOffset;
		}
		
		for (i = 0; i < howMany; i++) {
				var aStateImageWidth:Number;
				var aTitleWidth:Number;
				var anImageWidth:Number;
				var anImageAndTitleWidth:Number;
				var aKeyEquivalentWidth:Number;
				var aCell:NSMenuItemCell = NSMenuItemCell
				(m_itemCells.objectAtIndex(i));
				
				// State image area.
				aStateImageWidth = aCell.stateImageWidth();
				
				// Title and Image area.
				aTitleWidth = aCell.titleWidth();
				anImageWidth = aCell.imageWidth();
				
				// Key equivalent area.
				aKeyEquivalentWidth = aCell.keyEquivalentWidth();
				
				switch (aCell.imagePosition()) {
					case NSCellImagePosition.NSNoImage: 
						anImageAndTitleWidth = aTitleWidth;
						break;
						
					case NSCellImagePosition.NSImageOnly: 
						anImageAndTitleWidth = anImageWidth;
						break;
						
					case NSCellImagePosition.NSImageLeft: 
					case NSCellImagePosition.NSImageRight: 
					//! what is GSCellTextImageXDist?
						anImageAndTitleWidth = anImageWidth + aTitleWidth/* + GSCellTextImageXDist*/;
						break;
						
					case NSCellImagePosition.NSImageBelow: 
					case NSCellImagePosition.NSImageAbove: 
					case NSCellImagePosition.NSImageOverlaps: 
					default: 
						if (aTitleWidth > anImageWidth) {
							anImageAndTitleWidth = aTitleWidth;
						} else {
							anImageAndTitleWidth = anImageWidth;
						}
						break;
					}
				
				if (aStateImageWidth > neededStateImageWidth) {
					neededStateImageWidth = aStateImageWidth;
				}
				if (anImageAndTitleWidth > neededImageAndTitleWidth) {
					neededImageAndTitleWidth = anImageAndTitleWidth;
				}
				if (aKeyEquivalentWidth > neededKeyEquivalentWidth) {
					neededKeyEquivalentWidth = aKeyEquivalentWidth;
				}
				// Title view width less than item's left part width
				if ((anImageAndTitleWidth + aStateImageWidth)
				> neededImageAndTitleWidth) {
					wideTitleView = 0;
				}
				// Popup menu has only one item with nibble or arrow image
				if (anImageWidth) {
					popupImageWidth = anImageWidth;
				}
			}
		
		// Cache the needed widths.
		m_stateImageWidth = neededStateImageWidth;
		m_imageAndTitleWidth = neededImageAndTitleWidth;
		m_keyEqWidth = neededKeyEquivalentWidth;
		
		accumulatedOffset = m_horizontalEdgePad;
		if (howMany) {
			// Calculate the offsets and cache them.
			if (neededStateImageWidth) {
				m_stateImageOffset = accumulatedOffset;
				accumulatedOffset += neededStateImageWidth += m_horizontalEdgePad;
			}
				
			if (neededImageAndTitleWidth) {
				m_imageAndTitleOffset = accumulatedOffset;
				accumulatedOffset += neededImageAndTitleWidth;
			}
				
			if (wideTitleView) {
				m_keyEqOffset = accumulatedOffset = neededImageAndTitleWidth
				+ (3 * m_horizontalEdgePad);
			} else {
				m_keyEqOffset = accumulatedOffset += (2 * m_horizontalEdgePad);
			}
			accumulatedOffset += neededKeyEquivalentWidth + m_horizontalEdgePad; 
				
			if (m_attachedMenu.superMenu() != null && neededKeyEquivalentWidth < 8) {
				accumulatedOffset += 8 - neededKeyEquivalentWidth;
			}
		} else {
			accumulatedOffset += neededImageAndTitleWidth + 3 + 2;
			if (m_attachedMenu.superMenu() != null) {
				accumulatedOffset += 15;
			}
		}
		
		// Calculate frame size.
		if (!m_attachedMenu.ownedByPopUp()) {
			// Add the border width: 1 for left, 2 for right sides
			m_cellSize.width = accumulatedOffset + 3;
		} else {
			m_keyEqOffset = m_cellSize.width - m_keyEqWidth - popupImageWidth;
		}
	
		if (m_horizontal == false) {
			setFrameSize(new NSSize(m_cellSize.width + m_leftBorderOffset, 
			(howMany * m_cellSize.height) 
			+ menuBarHeight));
			m_titleView.setFrame(new NSRect (0, howMany * m_cellSize.height,
			m_bounds.size.width, menuBarHeight));
		} else {
			setFrameSize(new NSSize(((howMany + 1) * m_cellSize.width), 
			m_cellSize.height + m_leftBorderOffset));
			m_titleView.setFrame(new NSRect (0, 0),
			m_cellSize.width, m_cellSize.height + 1);
		}
		
		m_needsSizing = false;
	}
	
	public function stateImageOffset():Number {
		if (m_needsSizing) {
			sizeToFit();
		}
		return m_stateImageOffset;
	}
	
	public function stateImageWidth():Number {
		if (m_needsSizing) {
			sizeToFit();
		}
		return m_stateImageWidth;
	}
	
	public function imageAndTitleOffset():Number {
		if (m_needsSizing) {
			sizeToFit();
		}
		return m_imageAndTitleOffset;
	}
	
	public function imageAndTitleWidth():Number {
		if (m_needsSizing) {
			sizeToFit();
		}
		return m_imageAndTitleWidth;
	}
	
	public function keyEquivalentOffset():Number {
		if (m_needsSizing) {
			sizeToFit();
		}
		return m_keyEqOffset;
	}
	
	public function keyEquivalentWidth():Number {
		if (m_needsSizing) {
			sizeToFit();
		}
		return m_keyEqWidth;
	}
	
	public function innerRect():NSRect {
		if (m_horizontal == false) {
			return new NSRect(m_bounds.origin.x + m_leftBorderOffset, 
			m_bounds.origin.y,
			m_bounds.size.width - m_leftBorderOffset, 
			m_bounds.size.height);
		} else {
			return new NSRect (m_bounds.origin.x, 
			m_bounds.origin.y + m_leftBorderOffset,
			m_bounds.size.width, 
			m_bounds.size.height - m_leftBorderOffset);
		}
	}
	
	public function rectOfItemAtIndex(index:Number):NSRect {
		var theRect:NSRect = NSRect.ZeroRect;
	
		if (m_needsSizing == true) {
			sizeToFit();
		}
	
		/* Fiddle with the origin so that the item rect is shifted 1 pixel over 
		 * so we do not draw on the heavy line at origin.x = 0.
		 */
		if (m_horizontal == false) {
			theRect.origin.y = m_cellSize.height * (m_itemCells.count() - index - 1);
			theRect.origin.x = m_leftBorderOffset;
		} else {
			theRect.origin.x = m_cellSize.width * (index + 1);
			theRect.origin.y = 0;
		}
		theRect.size = m_cellSize;
	
		/* NOTE: This returns the correct NSRect for drawing cells, but nothing 
		 * else (unless we are a popup). This rect will have to be modified for 
		 * event calculation, etc..
		 */
		
		return theRect;
	}
	
	public function indexOfItemAtPoint(point:NSPoint):Number {
		var howMany:Number = m_itemCells.count();
		var i:Number;
		var aRect:NSRect;
	
		for (i = 0; i < howMany; i++) {
			aRect = rectOfItemAtIndex(i);
				
			addLeftBorderOffsetToRect(aRect);
	
			if (aRect.pointInRect(point)) {
				return i;
			}
		}
	
		return -1;
	}
	
	public function setNeedsDisplayForItemAtIndex(index:Number):Void {
		var aRect:NSRect ;
	
		aRect = rectOfItemAtIndex(index);
		addLeftBorderOffsetToRect(aRect);
		//! NSView.setNeedsDisplayInRect(aRect);
		setNeedsDisplay(true);
	}
	
	public function locationForSubmenu(aSubmenu:NSMenu ):NSPoint {
		var frame:NSRect = m_window.frame();
		var submenuFrame:NSRect ;
	
		if (m_needsSizing) {
			sizeToFit();
		}
		if (aSubmenu) {
			submenuFrame = aSubmenu.menuRepresentation().window().frame();
		} else {
			submenuFrame = NSRect.ZeroRect;
		}
		if (m_horizontal == false) {
			//! todo: interface styles
			/*
			if (NSInterfaceStyleForKey("NSMenuInterfaceStyle", 
			aSubmenu.menuRepresentation())
			== GSWindowMakerInterfaceStyle) {
				var aRect:NSRect = rectOfItemAtIndex
				(m_attachedMenu.indexOfItemWithSubmenu(aSubmenu));
				var subOrigin:NSPoint = m_window.convertBaseToScreen
				(NSPoint(aRect.origin.copy()));
	
				return new NSPoint
				(frame.maxX(),
				subOrigin.y - submenuFrame.height - 3 +
				2*menuBarHeight());
			} else {*/
				return new NSPoint(frame.maxX(),
				frame.maxY() - submenuFrame.size.height);
			//}
		} else {
			var aRect:NSRect = rectOfItemAtIndex
			(m_attachedMenu.indexOfItemWithSubmenu(aSubmenu));
			var subOrigin:NSPoint = m_window.convertBaseToScreen
			(NSPoint(aRect.origin.copy()));
	
			return new NSPoint(subOrigin.x, subOrigin.y - submenuFrame.size.height);
		}
	}
	
	public function resizeWindowWithMaxHeight(maxHeight:Number):Void {
		//! FIXME set the menuview's window to max height in order to keep on screen?
	}
	
	//no onScreen, preferredEdge: name unchanged for compatibility
	public function setWindowFrameForAttachingToRectOnScreenPreferredEdgePopUpSelectedItem
	(screenRect:NSRect, /*screen:NSScreen, */selectedItemIndex:Number):Void {
		var r:NSRect;
		var cellFrame:NSRect;
		var screenFrame:NSRect;
		var items:Number = m_itemCells.count();
		
		// Convert the screen rect to our view
		cellFrame.size = screenRect.size;
		cellFrame.origin = m_window.convertScreenToBase(screenRect.origin);
		cellFrame = convertRectFromView(cellFrame, null);
	 
		// Only call update if needed.
		if ((m_cellSize.isEqual(cellFrame.size) == false) || m_needsSizing) {
			m_cellSize = cellFrame.size;
			update();
		}
		
		/*
		 * Compute the frame
		 */
		screenFrame = screenRect;
		if (items > 0) {
			var f:Number;
	
			if (m_horizontal == false) {
				f = screenRect.size.height * (items - 1);
				screenFrame.size.height += f + m_leftBorderOffset;
				screenFrame.origin.y -= f;
				screenFrame.size.width += m_leftBorderOffset;
				screenFrame.origin.x -= m_leftBorderOffset;
				// Compute position for popups, if needed
				if (selectedItemIndex != -1) {
					screenFrame.origin.y += screenRect.size.height * selectedItemIndex;
				}
			} else {
				f = screenRect.size.width * (items - 1);
				screenFrame.size.width += f;
				// Compute position for popups, if needed
				if (selectedItemIndex != -1) {
					screenFrame.origin.x -= screenRect.size.width * selectedItemIndex;
				}
			}
		}	
		
		// Get the frameRect
		r = NSWindow.frameRectForContentRectStyleMask
		(screenFrame, m_window.styleMask());
		
		// Update position,if needed, using the preferredEdge;
		//! unsused?
		
		// Set the window frame
		m_window.setFrame(r); 
	}
	
	/*
	 * Drawing.
	 */
	public function isOpaque():Boolean {
		return true;
	}
	
	public function drawRect(rect:NSRect):Void {
		var i:Number;
		var howMany:Number = m_itemCells.count();
		var aRect:NSRect;
		var aCell:NSMenuItemCell;
	
		// Draw the dark gray upper and left lines.
		var mc:MovieClip;
		try {
			mc = mcBounds();
		} catch(e:NSException) {
			trace(e);
			trace(asFatal(e.message));
			return;
		}
		mc.clear();
		//top, then left
		//! try using outlineRectWithAlpha
		ASDraw.drawHLine(mc, NSColor.NSDarkGray.value, rect.minX(), rect.maxX(), rect.minY());
		ASDraw.drawVLine(mc, NSColor.NSDarkGray.value, rect.minY(), rect.maxY(), rect.minX());
		
		// Draw the menu cells
		for (i = 0; i < howMany; i++) {
			aRect = rectOfItemAtIndex(i);
			if (rect.intersectsRect(aRect) == true) {
				aCell = NSMenuItemCell(m_itemCells.objectAtIndex(i));
				aCell.drawWithFrameInView(aRect, this);
			}
		}
	}
	
	/*
	 * Event Handling
	 */
	public function performActionWithHighlightingForItemAtIndex(index:Number):Void {
		var candidateMenu:NSMenu = m_attachedMenu;
		var targetMenuView:NSMenuView;
		var indexToHighlight:Number = index;
		var oldHighlightedIndex:Number;
		var superMenu:NSMenu;
	
		for (;;) {
			superMenu = candidateMenu.superMenu();
	
			if (superMenu == null
			|| candidateMenu.isAttached()
			|| candidateMenu.isTornOff()) {
				targetMenuView = candidateMenu.menuRepresentation();
				
				break;
			} else {
				indexToHighlight = superMenu.indexOfItemWithSubmenu(candidateMenu);
				candidateMenu = superMenu;
			}
		}
		
		oldHighlightedIndex = targetMenuView.highlightedItemIndex();
		targetMenuView.setHighlightedItemIndex(indexToHighlight);
	
		/* We need to let the run loop run a little so that the fact that
		 * the item is highlighted gets displayed on screen.
		 *
		[NSRunLoop.currentRunLoop() 
			runUntilDate: NSDate.dateWithTimeIntervalSinceNow(0.1]);
		*/
		m_attachedMenu.performActionForItemAtIndex(index);
	
		if (!m_attachedMenu.ownedByPopUp()) {
			targetMenuView.setHighlightedItemIndex(oldHighlightedIndex);
		}
	}
	
	private static var MOVE_THRESHOLD_DELTA:Number = 2.0;
	private static var DELAY_MULTIPLIER:Number = 10;
	
	
	
	/**
		 This method is called when the user clicks on a button in the menu.
		 Or, if a right click happens and the app menu is brought up.
	
		 The original position is stored, so we can restore the position of menu.
		 The position of the menu can change during the event tracking because
		 the menu will automatillay move when parts are outside the screen and 
		 the user move the mouse pointer to the edge of the screen.
	*/
	
	//! FIXME
	public function mouseDown(theEvent:NSEvent):Void {
		var currentFrame:NSRect;
		var originalFrame:NSRect;
		var currentTopLeft:NSPoint;
		var originalTopLeft:NSPoint;
		var restorePosition:Boolean;
		/*
		 * Only for non transient menus do we want
		 * to remember the position.
		 */ 
		restorePosition = !m_attachedMenu.isTransient();
	
		if (restorePosition) { // store old position;
			originalFrame = m_window.frame();
			originalTopLeft = originalFrame.origin;
			originalTopLeft.y += originalFrame.size.height;
		}
		//! FIXME
		/*
		NSEvent.startPeriodicEventsAfterDelayWithPeriodTrackWithEvent
		(0.1, 0.01, theEvent);
		NSEvent.stopPeriodicEvents();
		*/
		if (restorePosition) {
			currentFrame = m_window.frame();
			currentTopLeft = currentFrame.origin;
			currentTopLeft.y += currentFrame.size.height;
	
			if (currentTopLeft.isEqual(originalTopLeft) == false) {
				var origin:NSPoint = currentFrame.origin;
				origin.x += (originalTopLeft.x - currentTopLeft.x);
				origin.y += (originalTopLeft.y - currentTopLeft.y);
				m_attachedMenu.nestedSetFrameOrigin(origin);
			}
		}
	}
	
	public function rightMouseDown(theEvent:NSEvent):Void {
		mouseDown(theEvent);
	}
	
	public function performKeyEquivalent(theEvent:NSEvent ):Boolean {
		return m_attachedMenu.performKeyEquivalent(theEvent);
	}
}
	