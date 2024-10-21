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
import org.actionstep.NSEvent;
import org.actionstep.NSCell;
import org.actionstep.NSImage;
import org.actionstep.NSException;
import org.actionstep.NSUserDefaults;

import org.actionstep.NSMenu;
import org.actionstep.ASMenuSeparator;

class org.actionstep.NSMenuItem extends NSObject {
	private static var g_usesUserKeyEquivalents:Boolean;
	
	private var m_keyEquivalentModifierMask:Number;
	private var	m_keyEquivalent:String;
	private var	m_mnemonicLocation:Number;
	private var	m_state:Number;
	private var	m_enabled:Boolean;
	private var	m_action:String;
	private var	m_target:Object;
	private var	m_tag:Number;
	private var	m_representedObject:Object;
	private var	m_title:String;
	private var	m_changesState:Boolean;
	
	//Menus
	private var	m_menu:NSMenu;
	private var	m_submenu:NSMenu;
	
	//Images
	private var	m_image:NSImage;
	private var	m_onStateImage:NSImage;
	private var	m_offStateImage:NSImage;
	private var	m_mixedStateImage:NSImage;
	
	public static function setUsesUserKeyEquivalents(flag:Boolean):Void {
	  g_usesUserKeyEquivalents = flag;
	}
	
	public static function usesUserKeyEquivalents():Boolean {
	  return g_usesUserKeyEquivalents;
	}
	
	/**
	* Returns a separator.
	* This is just a blank menu item which serves to divide the menu into separate parts.
	*/
	public static function separatorItem ():NSMenuItem {
		return new ASMenuSeparator();
	}
	
	public function init():NSMenuItem {
	  return initWithTitleActionKeyEquivalent("", null, "");
	}
	
	public function initWithTitleActionKeyEquivalent(aString:String, aSelector:String, charCode:String):NSMenuItem {
	  setTitle(aString);
	  setKeyEquivalent(charCode);
	  m_keyEquivalentModifierMask = NSEvent.NSCommandKeyMask;
	  m_mnemonicLocation = 255; // No mnemonic
	  m_state = NSCell.NSOffState;
	  m_enabled = true;
	  // Set the images according to the spec. On: check mark; off: dash.
	  setOnStateImage(NSImage.imageNamed("NSMenuCheckmark"));
	  setMixedStateImage(NSImage.imageNamed("NSMenuMixedState"));
	  m_action = aSelector;
	  return this;
	}
	
	public function setMenu(menu:NSMenu):Void {
	  /* The menu is retaining us.  Do not retain it.  */
	  m_menu = menu;
	  if (m_submenu != null) {
			m_submenu.setSupermenu(menu);
	    setTarget(m_menu);
		}
	}
	
	public function menu ():NSMenu {
	  return m_menu;
	}
	
	public function hasSubmenu():Boolean {
	  return !(m_submenu == null);
	}
	
	public function setSubmenu(submenu:NSMenu):Void {
	  if (submenu.superMenu() != null) {
			var e:NSException = NSException.exceptionWithNameReasonUserInfo
			(NSException.NSInvalidArgument, 
			"submenu ("+submenu.title()+") already has superMenu ("+submenu.superMenu().title()+")", 
			null);
			trace(e);
			e.raise();
		}
	  m_submenu = submenu;
	  if (submenu != null) {
			submenu.setSupermenu(m_menu);
			submenu.setTitle(m_title);
		}
	  setTarget(m_menu);
	  setAction("submenuAction");
	  m_menu.itemChanged(this);
	}
	
	public function submenu():NSMenu {
	  return m_submenu;
	}
	
	public function setTitle(aString:String):Void{
	  if (aString==null)	aString = "";
	
	  m_title = aString;
	  m_menu.itemChanged(this);
	}
	
	public function title():String {
	  return m_title;
	}
	
	public function isSeparatorItem():Boolean {
	  return false;
	}
	
	public function setKeyEquivalent(aKeyEquivalent:String):Void {
	  if (null == aKeyEquivalent)
	    aKeyEquivalent = "";
	
	  m_keyEquivalent = aKeyEquivalent;
	  m_menu.itemChanged(this);
	}
	
	public function keyEquivalent():String {
	  if (usesUserKeyEquivalents)	return userKeyEquivalent();
			else	return m_keyEquivalent;
	}
	
	public function setKeyEquivalentModifierMask(mask:Number):Void {
	  m_keyEquivalentModifierMask = mask;
	}
	
	public function keyEquivalentModifierMask():Number {
	  return m_keyEquivalentModifierMask;
	}
	
	public function userKeyEquivalent():String {
		var userKeyEquivalent:String = //NSDictionary(
		NSUserDefaults.standardUserDefaults().
		persistentDomainForName("NSGlobalDomain").
		objectForKey("NSCommandKeys").
		objectForKey(m_title);
	  /*NSString *userKeyEquivalent = [(NSDictionary*)[
					     objectForKey: @"NSCommandKeys"]
					    objectForKey: _title];*/
	
	  if (null == userKeyEquivalent) {
			userKeyEquivalent = "";
		}
	
	  return userKeyEquivalent;
	}
	
	public function userKeyEquivalentModifierMask():Number {
	  return NSEvent.NSCommandKeyMask;
	}
	
	public function setMnemonicLocation(location:Number):Void {
	  m_mnemonicLocation = location;
	  m_menu.itemChanged(this);
	}
	
	public function mnemonicLocation():Number {
	  if (m_mnemonicLocation != 255) {
			return m_mnemonicLocation;
		} else {
			return NSObject.NSNotFound;
		}
	}
	
	public function mnemonic():String {
	  if (m_mnemonicLocation != 255) {
	    //return m_title.substringWithRange(NSMakeRange(m_mnemonicLocation, 1));
	    return m_title.substr(m_mnemonicLocation, 1);
		} else {
	    return "";
		}
	}
	
	public function setTitleWithMnemonic(stringWithAmpersand:String):Void {
	  var location:Number = stringWithAmpersand.indexOf("&");
		var f1:Array = stringWithAmpersand.split("&");
		
	  setTitle(f1.join(""));		//removes "&"
	  setMnemonicLocation(location);
	}
	
	public function setImage(image:NSImage):Void {
		m_image = (image==null) ? null : image;
	  m_menu.itemChanged(this);
	}
	
	public function image():NSImage {
	  return m_image;
	}
	
	public function setState(state:Number):Void {
	  if (m_state == state) {
	    return;
		}
	
	  m_state = state;
	  m_changesState = true;
	  m_menu.itemChanged(this);
	}
	
	public function state():Number {
	  return m_state;
	}
	
	public function setOnStateImage(image:NSImage):Void {
		m_onStateImage = (image==null) ? null : image;
	  m_menu.itemChanged(this);
	}
	
	public function onStateImage():NSImage {
	  return m_onStateImage;
	}
	
	public function setOffStateImage(image:NSImage) {
		m_offStateImage = (image==null) ? null : image;
	  m_menu.itemChanged(this);
	}
	
	public function offStateImage():NSImage {
	  return m_offStateImage;
	}
	
	public function setMixedStateImage(image:NSImage) {
	  m_mixedStateImage = (image==null) ? null : image;
	  m_menu.itemChanged(this);
	}
	
	public function mixedStateImage():NSImage {
	  return m_mixedStateImage;
	}
	
	public function setEnabled(flag:Boolean):Void {
	  if (flag == m_enabled) {
	    return;
		}
	
	  m_enabled = flag;
	  m_menu.itemChanged(this);
	}
	
	public function isEnabled():Boolean {
	  return m_enabled;
	}
	
	public function setTarget(anObject:Object):Void {
	  if (m_target == anObject) {
	    return;
		}
	
	  m_target = anObject;
	  m_menu.itemChanged(this);
	}
	
	public function target():Object {
	  return m_target;
	}
	
	public function setAction(aSelector:String):Void {
	  if (m_action == aSelector) {
	    return;
		}
	
	  m_action = aSelector;
	  m_menu.itemChanged(this);
	}
	
	public function action():String {
	  return m_action;
	}
	
	public function setTag(anInt:Number) {
	  m_tag = anInt;
	}
	
	public function tag():Number {
	  return m_tag;
	}
	
	public function setRepresentedObject(anObject:Object) {
	  m_representedObject = anObject;
	}
	
	public function representedObject():Object {
	  return m_representedObject;
	}
	
	public function setChangesState(n:Boolean):Void {
			m_changesState = n;
	}
	
	public function changesState():Boolean {
		return m_changesState;
	}
}