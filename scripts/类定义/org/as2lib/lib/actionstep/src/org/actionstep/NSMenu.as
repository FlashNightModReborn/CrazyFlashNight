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

import org.actionstep.NSObject;
import org.actionstep.NSWindow;
import org.actionstep.NSException;
import org.actionstep.NSApplication;
import org.actionstep.NSNotification;
import org.actionstep.NSNotificationCenter;
import org.actionstep.NSEvent;
import org.actionstep.NSArray;
import org.actionstep.NSDictionary;
import org.actionstep.NSEnumerator;
import org.actionstep.NSRect;
import org.actionstep.NSSize;
import org.actionstep.NSPoint;
import org.actionstep.NSView;
import org.actionstep.NSUserDefaults;
import org.actionstep.NSPopUpButtonCell;
import org.actionstep.ASUtils;

import org.actionstep.NSMenuPanel;
import org.actionstep.NSMenuItem;
import org.actionstep.NSMenuView;

class org.actionstep.NSMenu extends NSObject{
	private var m_app:NSApplication;
	private var m_notifications:NSArray;
	private var m_title:String;
	private var m_items:NSArray;
	private var m_oldHiglightedIndex:Number;
	
	private var m_superMenu:NSMenu;
	private var m_attachedMenu:NSMenu;
	private var m_oldAttachedMenu:NSMenu;
	private var m_view:NSMenuView;
	private var m_popUpButtonCell:NSPopUpButtonCell;
	
	//Flags
	private var m_needsSizing:Boolean;
	private var m_changedMessagesEnabled:Boolean;
	private var m_autoenable:Boolean;
	private var m_transient:Boolean;
	private var m_isTornOff:Boolean;
	
	private var m_aWindow:NSWindow;
	private var m_bWindow:NSWindow;
	
	//User default key
	public static var NSMenuLocationsKey:String = "NSMenuLocations";
	
	//Notifications
	public static var NSEnqueuedMenuMove:Number = ASUtils.intern("NSEnqueuedMoveNotification");
	public static var NSMenuDidAddItemNotification:Number = ASUtils.intern("NSMenuDidAddItemNotification");
	public static var NSMenuDidChangeItemNotification:Number = ASUtils.intern("NSMenuDidChangeItemNotification");
	public static var NSMenuDidEndTrackingNotification:Number = ASUtils.intern("NSMenuDidEndTrackingNotification");
	public static var NSMenuDidRemoveItemNotification:Number = ASUtils.intern("NSMenuDidRemoveItemNotification");
	public static var NSMenuDidSendActionNotification:Number = ASUtils.intern("NSMenuDidSendActionNotification");
	public static var NSMenuWillSendActionNotification:Number = ASUtils.intern("NSMenuWillSendActionNotification");
	
	private static var g_nc:NSNotificationCenter;
	
	private function locationKey():String {
		if (m_superMenu == null) {
			if (m_app.mainMenu() == this) {
				return "033";	/* Root menu.	*/
			} else {
				return null;		/* Unused menu.	*/
			}
		} else if (m_superMenu.superMenu() == null) {
			return "033"+title();
		} else {
			return ((m_superMenu.locationKey())+"033"+title());
		}
	}
	
	/* Create a non autorelease window for this menu.	*/
	private function createWindow():NSMenuPanel {
		var win:NSMenuPanel = NSMenuPanel((new NSMenuPanel()).
		initWithContentRectStyleMask
		(NSRect.ZeroRect, NSWindow.NSBorderlessWindowMask));
		win.setLevel(NSWindow.NSSubmenuWindowLevel);
		win.setWorksWhenModal(false);
		win.setBecomesKeyOnlyIfNeeded(true);
	
		return win;
	}
	
	/**
		 Will track the mouse movement.	It will trigger the updating of the user
		 defaults in due time.
	*/
	private function menuMoved(notification:NSNotification):Void {
		var resend:NSNotification;
	
		resend = NSNotification.withNameObject
		(NSEnqueuedMenuMove, this);
		/*
		[NSNotificationQueue.defaultQueue()
			enqueueNotification: resend
			postingStyle: NSPostASAP
			coalesceMask: NSNotificationCoalescingOnSender
			forModes:	NSArray.arrayWithObject(NSDefaultRunLoopMode]);*/
	}
	
	/**
		 Save the current menu position in the standard user defaults
	*/
	private function updateUserDefaults(notification:NSNotification):Void {
		var key:String;
	
		trace(asDebug("Synchronizing user defaults"));
		key = locationKey();
		
		if (key != null) {
			var defaults:NSUserDefaults;
			var menuLocations:NSDictionary;
			var loc:NSRect;

			defaults	= NSUserDefaults.standardUserDefaults();
			menuLocations = defaults.dictionaryForKey(NSMenuLocationsKey);

			if (NSDictionary(menuLocations)==null) {
				menuLocations = null;
			}
			if (m_aWindow.isVisible() && 
			(isTornOff() || (m_app.mainMenu() == this))) {
				if (menuLocations == null) {
					menuLocations = new NSDictionary();
				}
				loc = window().frame();
				menuLocations.setObjectForKey(loc, key);
			} else {
				menuLocations.removeObjectForKey(key);
			}
	
			if (menuLocations.count() > 0) {
				defaults.setObjectForKey(menuLocations, NSMenuLocationsKey);
			} else {
				defaults.removeObjectForKey(NSMenuLocationsKey);
			}
			defaults.synchronize();
		}
	}
	
	private function rightMouseDisplay(theEvent:NSEvent):Void {
		displayTransient();
		m_view.mouseDown(theEvent);
		closeTransient();
	}
	
	/*
	 *
	 */
	public function init():NSMenu {
		return initWithTitle("NSMenu");
	}
	
	public function dealloc():Void {
		g_nc.removeObserver(this);
	
		// Now clean the pointer to us stored each m_items element
		m_items.makeObjectsPerformSelectorWithObject("setMenu", null);
	}
	
	/*
		 
	*/
	public function initWithTitle(aTitle:String):NSMenu {
		var contentView:NSView;
	
		super.init();
		m_app = NSApplication.sharedApplication();
		g_nc = NSNotificationCenter.defaultCenter();
		// Keep the title.
		m_title = aTitle;
	
		// Create an array to store out menu items.
		m_items = new NSArray();
	
		m_changedMessagesEnabled = true;
		m_notifications = new NSArray();
		m_needsSizing = true;
		// According to the spec, menus do autoenable by default.
		m_autoenable = true;
	
		// Create the windows that will display the menu.
		m_aWindow = createWindow();
		m_bWindow = createWindow();
		m_bWindow.setLevel(NSWindow.NSPopUpMenuWindowLevel);
	
		// Create a NSMenuView to draw our menu items.
		m_view = NSMenuView((new NSMenuView()).initWithFrame(NSRect.ZeroRect));
		m_view.setMenu(this);
	
		contentView = m_aWindow.contentView();
		contentView.addSubview(m_view);
	
		/* Set up the notification to start the process of redisplaying
			 the menus where the user left them the last time.	
			 
			 Use NSApplicationDidFinishLaunching, and not
			 NSApplicationWillFinishLaunching, so that the programmer can set
			 up menus in NSApplicationWillFinishLaunching.
		*/
		g_nc.addObserverSelectorNameObject
		(this, "showTornOffMenuIfAny", NSApplication.NSApplicationDidFinishLaunchingNotification, m_app);
	
		g_nc.addObserverSelectorNameObject
		(this, "showOnActivateApp", NSApplication.NSApplicationWillBecomeActiveNotification, m_app);
		
		g_nc.addObserverSelectorNameObject
		//(this, "m_menuMoved", NSWindow.NSWindowDidMoveNotification, m_aWindow);
		(this, "m_menuMoved", NSView.NSViewFrameDidChangeNotification, m_aWindow.contentView());
		
		g_nc.addObserverSelectorNameObject
		(this, "m_updateUserDefaults", NSEnqueuedMenuMove, this);
		
		return this;
	}
	
	/*
	 * Setting Up the Menu Commands
	 */
	public function insertItemAtIndex(newItem:NSMenuItem, index:Number):Void {
		var inserted:NSNotification;
		var d:NSDictionary;
	
		/*
		 * If the item is already attached to another menu it
		 * isn't added.
		 */
		if (newItem.menu() != null) {
			trace(asFatal("The object "+newItem+" is already attached to a menu; it isn't possible to add it."));
			return;
		}
		
		m_items.insertObjectAtIndex(newItem, index);
		m_needsSizing = true;
		
		// Create the notification for the menu representation.
		d = NSDictionary.dictionaryWithObjectForKey
		(index, "NSMenuItemIndex");
		
		inserted = NSNotification.withNameObjectUserInfo
		(NSMenuDidAddItemNotification, this, d);
		
		if (m_changedMessagesEnabled) {
			g_nc.postNotification(inserted);
		} else {
			m_notifications.addObject(inserted);
		}
	
		// Set this after the insert notification has been send.
		newItem.setMenu(this);
	}
	
	public function insertItemWithTitleActionKeyEquivalentAtIndex
	(aString:String, aSelector:String, charCode:String, index:Number):NSMenuItem {
		var anItem:NSMenuItem = (new NSMenuItem()).initWithTitleActionKeyEquivalent
		(aString, aSelector, charCode);
	
		// Insert the new item into the menu.
		insertItemAtIndex(anItem, index);
	
		// For returns sake.
		return anItem;
	}
	
	public function addItem(newItem:NSMenuItem):Void {
		insertItemAtIndex(newItem, m_items.count());
	}
	
	public function addItemWithTitleActionKeyEquivalent
	(aString:String, aSelector:String, keyEquiv:String):NSMenuItem {
		return insertItemWithTitleActionKeyEquivalentAtIndex
		(aString, aSelector, keyEquiv, m_items.count());
	}
	
	public function removeItem(anItem:NSMenuItem) {
		var index:Number = indexOfItem(anItem);
	
		if (-1 == index) {
			return;
		}
		
		removeItemAtIndex(index);
	}
	
	public function removeItemAtIndex(index:Number):Void {
		var removed:NSNotification;
		var d:NSDictionary;
		var anItem:NSMenuItem = NSMenuItem(m_items.objectAtIndex(index));
	
		if (anItem==null) {
			return;
		}
	
		anItem.setMenu(null);
		m_items.removeObjectAtIndex(index);
		m_needsSizing = true;
		
		d = NSDictionary.dictionaryWithObjectForKey
		(index, "NSMenuItemIndex");
		
		removed = NSNotification.withNameObjectUserInfo
		(NSMenuDidRemoveItemNotification, this, d);
		
		if (m_changedMessagesEnabled) {
			g_nc.postNotification(removed);
		} else {
			m_notifications.addObject(removed);
		}
	}
	
	public function itemChanged(anObject:NSMenuItem):Void {
		var changed:NSNotification;
		var d:NSDictionary;
		var index:Number = indexOfItem(anObject);
	
		if (index == -1) {
			return;
		}
	
		m_needsSizing = true;
	
		d = NSDictionary.dictionaryWithObjectForKey
		(index, "NSMenuItemIndex");
		
		changed = NSNotification.withNameObjectUserInfo
		(NSMenuDidChangeItemNotification, this, d);
	
		if (m_changedMessagesEnabled) {
			g_nc.postNotification(changed);
		} else {
			m_notifications.addObject(changed);
		}
		// Update the menu.
		update();
	}
	
	/*
	 * Finding Menu Items
	 */
	public function itemWithTag(aTag:Number):NSMenuItem {
		var i:Number;
		var count:Number = m_items.count();
		var menuItem:NSMenuItem;
	
		for (i = 0; i < count; i++) {
			menuItem = NSMenuItem(m_items.objectAtIndex(i));
			if (menuItem.tag() == aTag) {
				return menuItem;
			}
		}
		
		return null;
	}
	
	public function itemWithTitle(aString:String):NSMenuItem {
		var i:Number;
		var count:Number = m_items.count();
		var menuItem:NSMenuItem;
	
		for (i = 0; i < count; i++) {
			menuItem = NSMenuItem(m_items.objectAtIndex(i));
			if (menuItem.title() == aString) {
				return menuItem;
			}
		}
		
		return null;
	}
	
	public function itemAtIndex(index:Number):NSMenuItem {
		if (index >= m_items.count() || index < 0) {
			var e:NSException = NSException.exceptionWithNameReasonUserInfo
			(NSException.NSRange, "Range error", null);
			trace(e);
			e.raise();
		}
	
		return NSMenuItem(m_items.objectAtIndex(index));
	}
	
	public function numberOfItems():Number {
		return m_items.count();
	}
	
	public function itemArray():NSArray {
		return m_items;
	}
	
	/*
	 * Finding Indices of Menu Items
	 */
	public function indexOfItem(anObject:NSMenuItem):Number {
		var index:Number = m_items.indexOfObjectIdenticalTo(anObject);
	
		if (index == NSNotFound) {
			return -1;
		} else {
			return index;
		}
	}
	
	public function indexOfItemWithTitle(aTitle:String):Number {
		var anItem:NSMenuItem;
	
		if ((anItem = itemWithTitle(aTitle))) {
			return m_items.indexOfObjectIdenticalTo(anItem);
		} else {
			return -1;
		}
	}
	
	public function indexOfItemWithTag(aTag:Number):Number {
		var anItem:NSMenuItem;
	
		if ((anItem = itemWithTag(aTag))) {
			return m_items.indexOfObjectIdenticalTo(anItem);
		} else {
			return -1;
		}
	}
	
	public function indexOfItemWithTargetAndAction(anObject:Object, actionSelector:String):Number {
		var i:Number;
		var count:Number = m_items.count();
		var menuItem:NSMenuItem;
	
		for (i = 0; i < count; i++) {
			menuItem = NSMenuItem(m_items.objectAtIndex(i));
	
			if (actionSelector == 0 || (menuItem.action() == actionSelector)) {
				if (menuItem.target()==(anObject)) {
					return i;
				}
			}
		}
	
		return -1;
	}
	
	public function indexOfItemWithRepresentedObject(anObject:Object):Number {
		var i:Number;
		var count:Number = m_items.count();
	
		for (i = 0; i < count; i++) {
			//! what if isEqual is null?
			if (m_items.objectAtIndex(i).representedObject().isEqual(anObject)) {
				return i;
			}
		}
	
		return -1;
	}
	
	public function indexOfItemWithSubmenu(anObject:NSMenu):Number {
		var i:Number;
		var count:Number = m_items.count();
		var item:NSMenuItem;
	
		for (i = 0; i < count; i++) {
			item = NSMenuItem(m_items.objectAtIndex(i));
			//! what if isEqual is null?
			if (item.hasSubmenu() && item.submenu().isEqual(anObject)) {
				return i;
			}
		}
		
		return -1;
	}
	
	/**
	* Managing Submenus.
	*/
	public function setSubmenuForItem
	(aMenu:NSMenu, anItem:NSMenuItem):Void {
		anItem.setSubmenu(aMenu);
	}
	
	public function submenuAction(sender:Object) {
		//! do smth
	}
	
	
	public function attachedMenu():NSMenu {
		if (m_attachedMenu && m_transient && !m_attachedMenu.isTransient()) {
			return null;
		}
		
		return m_attachedMenu;
	}
	
	
	/**
		 Look for the semantics in the header.	Note that
		 this implementation works because there are ... cases:
		 <enum>
		 <item>
		 This menu is transient, its supermenu is also transient.
		 In this case we just do the check between the transient windows
		 and everything is fine
		 </item>
		 <item>
		 The menu is transient, its supermenu is not transient.
		 This can go WRONG
		 </item>
		 </enum>
	*/
	public function isAttached():Boolean {
		return ((m_superMenu!=null) && (m_superMenu.attachedMenu() == this));
	}
	
	public function isTornOff():Boolean {
		return m_isTornOff;
	}
	
	public function locationForSubmenu(aSubmenu:NSMenu):NSPoint {
		return m_view.locationForSubmenu(aSubmenu);
	}
	
	public function superMenu():NSMenu {
		return m_superMenu;
	}
	
	public function setSupermenu(supermenu:NSMenu):Void {
		m_superMenu = supermenu;
	}
	
	/**
	* Enabling and Disabling Menu Items
	*/
	public function setAutoenablesItems(flag:Boolean):Void {
		m_autoenable = flag;
	}
	
	public function autoenablesItems():Boolean {
		return m_autoenable;
	}
	
	public function update():Void {
		// We use this as a recursion check.
		if (!m_changedMessagesEnabled) {
			return;
		}
		
		if (autoenablesItems()) {
			var i:Number, count:Number;
			var item:NSMenuItem;
			var action:String;
			var validator:Object;
			var wasEnabled:Boolean;
			var shouldBeEnabled:Boolean;
	
			count = m_items.count();	
				
			// Temporary disable automatic displaying of menu.
			setMenuChangedMessagesEnabled(false);
				
			for (i = 0; i < count; i++) {
				item = NSMenuItem(m_items.objectAtIndex(i));
				action = item.action();
				validator = null;
				wasEnabled = item.isEnabled();
	
				// Update the submenu items if any.
				if (item.hasSubmenu()) {
					item.submenu().update();
				}

				// If there is no action - there can be no validator for the item.
				if (action) {
					validator = m_app.targetForActionToFrom(action, item.target(), item);
				} else if (m_popUpButtonCell != null) {
					if (null != (action = m_popUpButtonCell.action())) {
						validator = m_app.targetForActionToFrom
						(action, m_popUpButtonCell.target(), m_popUpButtonCell.controlView());
					}
				}

				if (validator == null) {
					if ((action == null) && (m_popUpButtonCell != null)) {
						shouldBeEnabled = true;
					} else  {
						shouldBeEnabled = false;
					}
				} else if (validator.respondsToSelector("validateMenuItem")) {
					shouldBeEnabled = validator.validateMenuItem(item);
				} else {
					shouldBeEnabled = true;
				}
	
				if (shouldBeEnabled != wasEnabled) {
					item.setEnabled(shouldBeEnabled);
				}
			}
			
			// Reenable displaying of menus
			setMenuChangedMessagesEnabled(true);
		}
	
		if (m_needsSizing && (m_aWindow.isVisible() || m_bWindow.isVisible())) {
			trace(asDebug(" Calling Size To Fit (A)"));
			sizeToFit();
		}
		
		return;
	}
	
	//
	// Handling Keyboard Equivalents
	//
	public function performKeyEquivalent(theEvent:NSEvent):Boolean {
		var i:Number;
		var count:Number = m_items.count();
		var type:Number = theEvent.type;
		var item:NSMenuItem;
		
		if (type != NSEvent.NSKeyDown && type != NSEvent.NSKeyUp) {
			return false;
		}

		for (i = 0; i < count; i++) {
			item = NSMenuItem(m_items.objectAtIndex(i));

			if (item.hasSubmenu()) {
				//! FIXME: Should we only check active submenus?
				// Recurse through submenus.
				if (item.submenu().performKeyEquivalent(theEvent)) {
					// The event has been handled by an item in the submenu.
					return true;
				}
			} else {
				//! FIXME: Should also check the modifier mask
				if (item.keyEquivalent()==theEvent.charactersIgnoringModifiers) {
					if (item.isEnabled()) {
						m_view.performActionWithHighlightingForItemAtIndex(i);
					}
					return true;
				}
			}
		}
		return false; 
	}
	
	//
	// Simulating Mouse Clicks
	//
	public function performActionForItemAtIndex(index:Number):Void {
		var item:NSMenuItem = NSMenuItem(m_items.objectAtIndex(index));
		var d:NSDictionary;
		var action:String;
	
		if (!item.isEnabled()) {
			return;
		}
	
		// Send the actual action and the estipulated notifications.
		d = NSDictionary.dictionaryWithObjectForKey
		(item, "MenuItem");
		g_nc.postNotificationWithNameObjectUserInfo
		(NSMenuWillSendActionNotification, this, d);
	
		if (m_popUpButtonCell != null) {
			// Tell the popup button, which item was selected
			m_popUpButtonCell.selectItemAtIndex(index);
		}
	
		if ((action = item.action()) != null) {
			m_app.sendActionToFrom
			(action, item.target(), item);
		} else if (m_popUpButtonCell != null) {
			if ((action = m_popUpButtonCell.action()) != null) {
				m_app.sendActionToFrom
				(action, m_popUpButtonCell.target(), m_popUpButtonCell.controlView());
			}
		}
	
		g_nc.postNotificationWithNameObjectUserInfo
		(NSMenuDidSendActionNotification, this, d);
	}
	
	//
	// Setting the Title
	//
	public function setTitle(aTitle:String):Void {
		m_title = aTitle;
	
		m_needsSizing = true;
		if (m_aWindow.isVisible() || (m_bWindow.isVisible())) {
			sizeToFit();
		}
	}
		
	public function title():String {
		return m_title;
	}
	
	//
	// Setting the Representing Object
	//
	public function setMenuRepresentation(menuRep:NSMenuView):Void {
		var contentView:NSView;
	
		// remove the old representation
		contentView = m_aWindow.contentView();
		//! orig = removeSubview
		contentView.removeFromSuperview(m_view);
	
		m_view = menuRep;
		m_view.setMenu(this);
	
		// add the new representation
		contentView.addSubview(m_view);
	}
	
	public function menuRepresentation():NSMenuView {
		return m_view;
	}
	
	/**
	* Updating the Menu Layout
	*
	* Wim 20030301: Question, what happens when the notification trigger
	* new notifications?	I think it is not allowed to add items
	* to the m_notifications array while enumerating it.
	*/
	public function setMenuChangedMessagesEnabled(flag:Boolean):Void { 
		if (m_changedMessagesEnabled != flag) {
			if (flag) {
				if (m_notifications.count()) {
					var enumerator:NSEnumerator = m_notifications.objectEnumerator();
					var aNotification:NSNotification;
	
					while ((aNotification = NSNotification(enumerator.nextObject()))) {
						g_nc.postNotification(aNotification);
					}
				}
				// Clean the notification array.
				m_notifications.removeAllObjects();
			}
			m_changedMessagesEnabled = flag;
		}
	}
	 
	public function menuChangedMessagesEnabled():Boolean {
		return m_changedMessagesEnabled;
	}
	
	public function sizeToFit():Void {
		var oldWindowFrame:NSRect;
		var newWindowFrame:NSRect;
		var menuFrame:NSRect;
		var size:NSSize;
	
		m_view.sizeToFit();
		
		menuFrame = m_view.frame();
		size = menuFrame.size;
	 
		// Main
		oldWindowFrame = m_aWindow.frame();
		newWindowFrame = NSWindow.frameRectForContentRectStyleMask
		(menuFrame, m_aWindow.styleMask());
		
		if (oldWindowFrame.size.height > 1) {
			newWindowFrame.origin = new NSPoint(oldWindowFrame.origin.x, 
			oldWindowFrame.origin.y + oldWindowFrame.size.height - newWindowFrame.size.height);
		}
		m_aWindow.setFrame(newWindowFrame);
		
		// Transient
		oldWindowFrame = m_bWindow.frame();
		newWindowFrame = NSWindow.frameRectForContentRectStyleMask
		(menuFrame, m_bWindow.styleMask());
		if (oldWindowFrame.size.height > 1) {
			newWindowFrame.origin = new NSPoint(oldWindowFrame.origin.x,
			oldWindowFrame.origin.y + oldWindowFrame.size.height - newWindowFrame.size.height);
		}
		m_bWindow.setFrame(newWindowFrame);
		
		if (m_popUpButtonCell == null) {
			m_view.setFrameOrigin(NSPoint.ZeroPoint);
		}
		
		m_view.setNeedsDisplay(true);
		
		m_needsSizing = false;
	}
	
	/*
	 * Displaying Context Sensitive Help
	 */
	public function helpRequested(event:NSEvent):Void {
		//! TODO: Won't be implemented until we have NSHelp*
	}
	
	public static function popUpContextMenuWithEventForView
	(menu:NSMenu, event:NSEvent, view:NSView):Void {
		menu.rightMouseDisplay(event);
	}
	
	/*
	 * NSObject Protocol
	 */
	public function isEqual(anObject:Object):Boolean {
		if (this == anObject) {
			return true;
		}
		if (anObject instanceof NSMenu) {
			if (!m_title == anObject.title()) {
				return false;
			}
			return itemArray().isEqual(anObject.itemArray());
		}
		return false;
	}
	
	/*
	 * NSCopying Protocol
	 */
	public function copyWithZone():NSObject {
		var menu:NSMenu = (new NSMenu()).initWithTitle(m_title);
		var i:Number;
		var count:Number = m_items.count();
	
		menu.setAutoenablesItems(m_autoenable);
		for (i = 0; i < count; i++) {
			// This works because the copy on NSMenuItem sets the menu to null!!!
			menu.insertItemAtIndex
			(m_items.objectAtIndex(i).copyWithZone(), i);
		}
		
		return menu;
	}
	
	private function IS_OFFSCREEN(win:NSWindow) {
		//return !(NSContainsRect([NSScreen mainScreen] frame], [WINDOW.frame()))
	}
	
	public function setTornOff(flag:Boolean):Void {
		var supermenu:NSMenu;
	
		m_isTornOff = flag; 
	
		if (flag) {
			supermenu = superMenu();
			if (supermenu != null) {
				supermenu.menuRepresentation().setHighlightedItemIndex(-1);
				supermenu.m_attachedMenu = null;
			}
		}
		m_view.update();
	}
	
	private function showTornOffMenuIfAny(notification:NSNotification):Void {
		if (m_app.mainMenu() != this) {
			var key:String = locationKey();
			if (key != null) {
				var location:NSRect;
				var defaults:NSUserDefaults;
				var menuLocations:NSDictionary;

				defaults	= NSUserDefaults.standardUserDefaults();
				menuLocations = NSDictionary(defaults.objectForKey(NSMenuLocationsKey));
	
				if (NSDictionary(menuLocations)!=null) {
					location = NSRect(menuLocations.objectForKey(key));
				} else {
					location = null;
				}
				if (location && NSRect(location)!=null) {
					setTornOff(true);
					display();
				}
			}
		}
	}
	
	private function showOnActivateApp(notification:NSNotification):Void {
		if (m_app.mainMenu() == this) {
			display();
			// we must make sure that any attached submenu is visible too.
			attachedMenu().display();
		}
	}
	
	public function isTransient():Boolean {
		return m_transient;
	} 
	
	/*
	* //! fix IS_OFFSCREEN first
	public function isPartlyOffScreen():Boolean {
		return IS_OFFSCREEN (window());
	}*/
	
	private function performMenuClose(sender:Object):Void {
		if (m_attachedMenu!=null) {
			m_view.detachSubmenu();
		}
		m_view.setHighlightedItemIndex(-1);
		close();
		setTornOff(false);
		updateUserDefaults(null);
	} 
	
	public function display():Void {
		if (m_transient) {
			trace(asDebug("trying to display while already displayed transient"));
			//! return here?
		}
	
		if (m_needsSizing) {
			sizeToFit();
		}
		
		if (m_superMenu && !isTornOff()) {								 
			// query super menu for position
			m_aWindow.setFrameOrigin(m_superMenu.locationForSubmenu(this));
			m_superMenu.m_attachedMenu = this;
		} else if (m_aWindow.frame().origin.y <= 0 
		&& m_popUpButtonCell == null) { // get geometry only if not set
			setGeometry();
		}
		
		trace(asDebug("Display, origin: "+m_aWindow.frame().origin));
		
		m_aWindow.orderFrontRegardless();
	}
	
	public function displayTransient():Void {
		var location:NSPoint;
		var contentView:NSView;
	
		if (m_transient) {
			trace(asDebug("displaying transient while it is transient"));
			return;
		}
	
		if (m_needsSizing) {
			sizeToFit();
		}
		
		m_oldHiglightedIndex = menuRepresentation().highlightedItemIndex();
		m_transient = true;
		
		/*
		 * Cache the old submenu if any and query the supermenu our position.
		 * Otherwise, raise menu under the mouse.
		 */
		if (m_superMenu != null) {
			m_oldAttachedMenu = m_superMenu.attachedMenu();
			m_superMenu.m_attachedMenu = this;
			location = m_superMenu.locationForSubmenu(this);
		} else {
			var frame:NSRect = m_aWindow.frame();
	
			location = m_aWindow.mouseLocationOutsideOfEventStream();
			location = m_aWindow.convertBaseToScreen(location);
			location.x -= frame.size.width/2;
			if (location.x < 0) {
				location.x = 0;
			}
			location.y -= frame.size.height - 10;
		}
	
		m_bWindow.setFrameOrigin(location);
	
		m_view.removeFromSuperviewWithoutNeedingDisplay();
	
		contentView = m_bWindow.contentView();
		contentView.addSubview(m_view);
	
		m_view.update();
		
		m_bWindow.orderFront(this);
	}
	
	//! private?
	public function setGeometry():Void {
		var key:String;
		var defaults:NSUserDefaults;
		var menuLocations:NSDictionary;
		var location:NSRect;
		
		var origin:NSPoint;
		var value:Number;
	
		origin = new NSPoint (0, 
		/*NSScreen.mainScreen().frame().size.height*/
		Stage.height - m_aWindow.frame().size.height);
				
		if (null != (key = locationKey())) {
			defaults = NSUserDefaults.standardUserDefaults();
			menuLocations = NSDictionary(defaults.objectForKey(NSMenuLocationsKey));
	
			if (NSDictionary(menuLocations)!=null) {
				location = NSRect(menuLocations.objectForKey(key));
			} else {
				location = null;
			}
	 
			if (location && NSRect(location)!=null) {
				origin = NSPoint(location.origin.copy());
			}
		}
		
		m_aWindow.setFrameOrigin(origin);
		m_bWindow.setFrameOrigin(origin);
	}
	
	public function close():Void {
		var sub:NSMenu = attachedMenu();
	
		if (m_transient) {
			trace(asDebug("We should not close ordinary menu while transient version is still open"));
		}
		
		/*
		 * If we have an attached submenu, we must close that too - but then make
		 * sure we still have a record of it so that it can be re-displayed if we
		 * are redisplayed.
		 */
		if (sub != null) {
			sub.close();
			m_attachedMenu = sub;
		}
		m_aWindow.orderOut(this);
	
		if (m_superMenu && !isTornOff()) {
			m_superMenu.m_attachedMenu = null;
			m_superMenu.menuRepresentation().setHighlightedItemIndex(-1);
		}
	}
	
	public function closeTransient():Void {
		var contentView:NSView ;
	
		if (m_transient == false) {
			trace(asDebug("Closing transient: "+m_title+" while it is NOT transient now"));
			return;
		}
		
		m_bWindow.orderOut(this);
		m_view.removeFromSuperviewWithoutNeedingDisplay();
	
		contentView = m_aWindow.contentView();
		contentView.addSubview(m_view);
	
		contentView.setNeedsDisplay(true); 
		
		// Restore the old submenu (if any).
		if (m_superMenu != null) {
			m_superMenu.m_attachedMenu = m_oldAttachedMenu;
			m_superMenu.menuRepresentation().setHighlightedItemIndex
			(m_superMenu.indexOfItemWithSubmenu(m_superMenu.attachedMenu()));
		}
	
		menuRepresentation().setHighlightedItemIndex(m_oldHiglightedIndex);
		
		m_transient = false;
		m_view.update();
	}
	
	public function window():NSWindow {
		if (m_transient) {
			return m_bWindow;
		} else {
			return m_aWindow;
		}
	}
	
	/**
		 Set the frame origin of the receiver to aPoint. If a submenu of
		 the receiver is attached. The frame origin of the submenu is set
		 appropriately.
	*/
	public function nestedSetFrameOrigin(aPoint:NSPoint):Void {
		var theWindow:NSWindow = window();
	
		// Move ourself and get our width.
		theWindow.setFrameOrigin(aPoint);
	
		// Do the same for attached menus.
		if (m_attachedMenu) {
			aPoint = locationForSubmenu(m_attachedMenu);
			m_attachedMenu.nestedSetFrameOrigin(aPoint);
		}
	}
	
	private static var SHIFT_DELTA:Number;
	
	public function shiftOnScreen():Void {
		var theWindow:NSWindow = m_transient ? m_bWindow : m_aWindow;
		var frameRect:NSRect = theWindow.frame();
		//[NSScreen mainScreen].frame();
		var screenRect:NSRect = new NSRect(Stage.width, Stage.height);
		var vector:NSPoint	= new NSPoint(0, 0);
		var moveIt	:Boolean	= false;
		
		// 1 - determine the amount we need to shift in the y direction.
		if (frameRect.minY() < 0) {
			vector.y = Math.min(SHIFT_DELTA, -frameRect.minY());
			moveIt = true;
		} else if (frameRect.maxY() > screenRect.maxY()) {
			vector.y = -Math.min(SHIFT_DELTA, frameRect.maxY() - screenRect.maxY());
			moveIt = true;
		}
	
		// 2 - determine the amount we need to shift in the x direction.
		if (frameRect.minX() < 0) {
			vector.x = Math.min(SHIFT_DELTA, -frameRect.minX());
			moveIt = true;
		} else if (frameRect.maxX() > (screenRect.maxX() - 3)) {
		// Note the -3.	This is done so the menu, after shifting completely
		// has some spare room on the right hand side.	This is needed otherwise
		// the user can never access submenus of this menu.
			vector.x = -Math.min(SHIFT_DELTA, 
			frameRect.maxX() - screenRect.maxX() + 3);
			moveIt = true;
		}
		
		if (moveIt) {
			var candidateMenu:NSMenu;
			var masterMenu:NSMenu;
			var masterLocation:NSPoint;
			var destinationPoint:NSPoint;

			// Look for the "master" menu, i.e. the one to move from.
			for (candidateMenu = masterMenu = this;
			((candidateMenu = masterMenu.superMenu())
			&& (!masterMenu.isTornOff() || masterMenu.isTransient()));
			masterMenu = candidateMenu);
				
			masterLocation = masterMenu.window().frame().origin;
			destinationPoint.x = masterLocation.x + vector.x;
			destinationPoint.y = masterLocation.y + vector.y;
				
			masterMenu.nestedSetFrameOrigin(destinationPoint);
		}
	}
	
	public function ownedByPopUp():Boolean {
		return m_popUpButtonCell != null;
	}
	
	private function setOwnedByPopUp(popUp:NSPopUpButtonCell):Void {
		if (m_popUpButtonCell != popUp) {
			m_popUpButtonCell = popUp;
			if (popUp != null) {
				m_aWindow.setLevel(NSWindow.NSPopUpMenuWindowLevel);
				m_bWindow.setLevel(NSWindow.NSPopUpMenuWindowLevel);
			}
		}
		update();
	}

	public function description():String {
		return "NSMenu: "+m_title+" ("+m_transient ? "Transient": "Normal"+")";
	}
}