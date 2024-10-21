/*
 * Copyright (c) 2005, InfoEther, Inc.
 * All rights reserved.
 *
 * Copyright (c) 2005, Affinity Systems
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
 * 3) The name InfoEther, Inc. and Affinity Systems may not be used to endorse or promote products  
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

//**************************************************************************
// NSColorList TODO:
//**************************************************************************
// 
// Consider implementing a "save" method to add the current color list to
// available color lists instead of making it instantly available.
//
//**************************************************************************

import org.actionstep.ASUtils;
import org.actionstep.NSObject;
import org.actionstep.NSArray;
import org.actionstep.NSEnumerator;
import org.actionstep.NSColor;
import org.actionstep.NSException;
import org.actionstep.NSNotificationCenter;

/**
 * NSColorList represents a list of colors indexed by keys. These lists are used
 * to manage lists of colors. NSColorPanel uses this class.
 *
 * @author Scott Hyndman
 */
class org.actionstep.NSColorList extends NSObject
{	
	/**
	 * Posted whenever a color list changes.
	 */
	public static var NSColorListDidChangeNotification:Number 
		= ASUtils.intern("NSColorListDidChangeNotification");
	
	
	/** The available color lists in the application. */
	private static var g_availablelists:NSArray;
	
	/** The list's name. */
	private var m_name:String;
	
	/** TRUE if the list is editable, FALSE otherwise. */
	private var m_editable:Boolean;
		
	/** 
	 * The internal color list. 
	 *
	 * This array contains simple objects formatted as follows:
	 * {name:String, color:NSColor}
	 */
	private var m_colors:NSArray;
	
	
	/**
	 * Creates a new instance of NSColor list. 
	 */
	public function NSColorList()
	{
		m_colors = new NSArray();
		m_editable = true;
	}
	
	
	/**
	 * Initializes and returns the color list with the name name. If name
	 * is unspecified or empty (""), it will not be given a name.
	 */ 
	public function initWithName(name:String):NSColorList
	{
		if (name != null && name.length > 0)
			m_name = name;
			
		return this;
	}
	
	//******************************************************															 
	//*					  Properties					   *
	//******************************************************
	
	/**
	 * Returns an NSArray of all the string keys with which the colors
	 * of this list are associated.
	 */
	public function allKeys():NSArray
	{
		//! consider generating this on an update
		
		var keys:NSArray = new NSArray();
		var itr:NSEnumerator = m_colors.objectEnumerator();
		var obj:Object;
		
		while (null != (obj = itr.nextObject()))
		{
			keys.addObject(obj.name);
		}
		
		return keys;
	}
	
	
	/**
	 * Returns TRUE if the list is editable.
	 *
	 * Some system-defined color lists will not be editable. All user-defined
	 * lists will be editable.
	 */
	public function isEditable():Boolean
	{
		return m_editable;
	}
	
	
	/**
	 * Returns the name of the color list.
	 */
	public function name():String
	{
		return m_name;
	}
	
	
	/**
	 * @see org.actionstep.NSObject#description
	 */
	public function description():String 
	{
		return "NSColorList(" +
			"name=" + name() + ", " + 
			"allKeys=" + allKeys().description() + 
			")";
	}
	
	//******************************************************															 
	//*			List Access and Manipulation			   *
	//******************************************************
	
	/**
	 * Returns the color associated with the key, or NULL if there is none.
	 */
	public function colorWithKey(key:String):NSColor
	{
		var idx:Number = m_colors.indexOfObjectWithCompareFunction({name: key},
			NSColorList.colorName_comparer);
			
		if (idx == NSObject.NSNotFound)
			return null;
			
		return NSColor(m_colors.objectAtIndex(idx).color);
	}
	
	
	/**
	 * Inserts a color named key at the index location. If a color with
	 * the key already exists, it is removed.
	 *
	 * This method posts NSColorListDidChangeNotification to the notification
	 * center.
	 *
	 * If the color list is not editable, an NSException is thrown.
	 */
	public function insertColorKeyAtIndex(color:NSColor, key:String, 
		location:Number):Void
	{
		if (!m_editable) // Throw exception if !editable.
		{
			var e:NSException = NSException.exceptionWithNameReasonUserInfo(
				"NSColorListNotEditableException",
				"This color list (" + m_name + ") is not editable.",
				null);
			trace(e);
			throw e;
		}
		
		var idx:Number = m_colors.indexOfObjectWithCompareFunction({name: key},
			NSColorList.colorName_comparer);
			
		//
		// If a color named key already exists, remove it.
		//
		if (idx != NSObject.NSNotFound)
		{
			m_colors.removeObjectAtIndex(idx);
			
			//
			// Account for the shift in index after object removal.
			//
			if (location > idx) 
				location--;
		}
		
		m_colors.insertObjectAtIndex({name: key, color: color}, location);
		
		postNotification(); // notify
	}
	
	
	/**
	 * Removes the color associated with key. If the color does not exist,
	 * this method does nothing.
	 *
	 * This method posts NSColorListDidChangeNotification to the notification
	 * center.
	 *
	 * If the color list is not editable, an NSException is thrown.
	 */
	public function removeColorWithKey(key:String):Void
	{
		if (!m_editable) // Throw exception if !editable.
		{
			var e:NSException = NSException.exceptionWithNameReasonUserInfo(
				"NSColorListNotEditableException",
				"This color list (" + m_name + ") is not editable.",
				null);
			trace(e);
			throw e;
		}
		
		//
		// Find the color
		//
		var idx:Number = m_colors.indexOfObjectWithCompareFunction({name: key},
			NSColorList.colorName_comparer);
			
		if (idx == NSObject.NSNotFound) // If not found, do nothing.
			return;
			
		m_colors.removeObjectAtIndex(idx);
		
		postNotification(); // notify
	}
	
	
	/**
	 * Associates color with key. If a color is already associated with key,
	 * the existing color is replaced with the new one, otherwise the color
	 * is inserted into the end of the list.
	 *
	 * This method posts NSColorListDidChangeNotification to the notification
	 * center.
	 *
	 * If the color list is not editable, an NSException is thrown.
	 */
	public function setColorForKey(color:NSColor, key:String):Void
	{
		if (!m_editable) // Throw exception if !editable.
		{
			var e:NSException = NSException.exceptionWithNameReasonUserInfo(
				"NSColorListNotEditableException",
				"This color list (" + m_name + ") is not editable.",
				null);
			trace(e);
			throw e;
		}
		
		//
		// Find the color
		//
		var idx:Number = m_colors.indexOfObjectWithCompareFunction({name: key},
			NSColorList.colorName_comparer);
			
		var element:Object = {name: key, color: color};
		
		if (idx == NSObject.NSNotFound) // If not found, add to end.
		{
			m_colors.addObject(element);
		}
		else // Otherwise, replace with new color.
		{
			m_colors.replaceObjectAtIndexWithObject(idx, element);
		}
		
		postNotification(); // notify
	}
	
	
	//******************************************************															 
	//*					 Public Methods					   *
	//******************************************************
	
	/**
	 * Makes this color list available in NSColorList.availableColorLists.
	 *
	 * This method should only be called once.
	 */
	public function addToAvailableColorLists():Void
	{
		g_availablelists.addObject(this);
	}
	
	//******************************************************															 
	//*					    Events						   *
	//******************************************************
	//******************************************************															 
	//*				    Protected Methods				   *
	//******************************************************
	//******************************************************															 
	//*					 Private Methods				   *
	//******************************************************
	
	/**
	 * Posts a NSColorListDidChangeNotification notification to the default
	 * notification center.
	 */
	private function postNotification():Void
	{
		var nc:NSNotificationCenter = NSNotificationCenter.defaultCenter();
		nc.postNotificationWithNameObject(NSColorListDidChangeNotification, this);
	}
	
	//******************************************************															 
	//*			   Public Static Properties				   *
	//******************************************************
	
	/**
	 * Returns an array of all system NSColorLists and any user-created
	 * color lists that have been saved using the "save()" method.
	 */
	public static function availableColorLists():NSArray
	{
		return g_availablelists;	
	}
	
	//******************************************************															 
	//*				 Public Static Methods				   *
	//******************************************************
	
	/**
	 * Searches through availableColorLists and returns the NSColorList
	 * with name if it exists, or null if not found.
	 */
	public static function colorListNamed(name:String):NSColorList
	{
		var idx:Number = g_availablelists.indexOfObjectWithCompareFunction(
				{m_name:name}, NSColorList.listName_comparer);
		
		if (idx == NSObject.NSNotFound)
		{
			return null;
		}
		
		return NSColorList(g_availablelists.objectAtIndex(idx));
	}
		
		
	/**
	 * Compares the m_name members of two objects and returns TRUE if they match.
	 * 
	 * Used as a compare function for NSColorList.colorListNamed().
	 */
	private static function listName_comparer(obj1:Object, obj2:Object):Boolean
	{
		return obj1.m_name == obj2.m_name;
	}
		

	/**
	 * Compares the name members of two objects and returns TRUE if they match.
	 * 
	 * Used as a compare function for NSColorList.colorWithKey().
	 */		
	private static function colorName_comparer(obj1:Object, obj2:Object):Boolean
	{
		return obj1.name == obj2.name;
	}
	
	//******************************************************															 
	//*				  Static Constructor				   *
	//******************************************************
	
	/**
	 * Creates the static available list.
	 */
	private static function classConstruct():Boolean
	{
		if (classConstructed)
			return true;
			
		g_availablelists = new NSArray();
		
		return true;
	}
	
	private static var classConstructed:Boolean = classConstruct();
}
