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

//import org.actionstep.ASEventMonitor;
import org.actionstep.NSColor;
import org.actionstep.NSImage;
import org.actionstep.NSPoint;


/**
 *
 *
 * Instances of this class are immutable. You cannot change their hotspots or images
 * after creation.
 *
 * @author Scott Hyndman
 */
class org.actionstep.NSCursor extends org.actionstep.NSObject
{	
	private static var g_classConstructed:Boolean = false;
	private static var g_current:NSCursor;
	private static var g_cursorStack:Array = [];;
	
	private static var g_arrowCursor:NSCursor;
	private static var g_closedHandCursor:NSCursor;
	private static var g_crosshairCursor:NSCursor;
	private static var g_disappearingItemCursor:NSCursor;
	private static var g_IBeamCursor:NSCursor;
	private static var g_openHandCursor:NSCursor;
	private static var g_pointingHandCursor:NSCursor;
	private static var g_resizeDownCursor:NSCursor;
	private static var g_resizeLeftCursor:NSCursor;
	private static var g_resizeLeftRightCursor:NSCursor;
	private static var g_resizeRightCursor:NSCursor;
	private static var g_resizeUpCursor:NSCursor;
	private static var g_resizeUpDownCursor:NSCursor;
	
	private var m_image:NSImage;
	private var m_hotSpot:NSPoint;
	private var m_foregroundColorHint:NSColor;
	private var m_backgroundColorHint:NSColor;
	
	//******************************************************															 
	//*                    Construction
	//******************************************************
	
	/**
	 * Constructs a new instance of NSCursor.
	 */
	public function NSCursor()
	{
		//
		// Class initialization.
		//
		if (!g_classConstructed)
		{
			//
			// Create cursors
			//
			//g_arrowCursor = (new NSCursor()).
			
			g_classConstructed = true;
		}
	}
	
	
	/**
	 * Initializes a newly created NSCursor with an image, a hotspot and foreground
	 * and background color hints. (//! WHAT is a colour hint???)
	 */
	public function initWithImageForegroundColorHintBackgroundColorHintHotSpot
		(newImage:NSImage, foregroundColorHint:NSColor, backgroundColorHint:NSColor, 
		hotSpot:NSPoint):NSCursor
	{
		initWithImageHotSpot(newImage, hotSpot);
		m_foregroundColorHint = foregroundColorHint;
		m_backgroundColorHint = backgroundColorHint;
		
		return this;
	}
	
	
	/**
	 * Initializes a newly created NSCursor with an image and a hotSpot.
	 *
	 * @see org.actionstep.NSCursor#hotSpot()
	 * @see org.actionstep.NSCursor#image()
	 */
	public function initWithImageHotSpot(newImage:NSImage, hotSpot:NSPoint):NSCursor
	{
		m_image = newImage;
		m_hotSpot = hotSpot;
		
		return this;
	}
		
	
	
	//******************************************************															 
	//*                    Properties
	//******************************************************
	
	/**
	 * @see org.actionstep.NSObject#description
	 */
	public function description():String 
	{
		return "NSCursor(hotSpot=" + hotSpot() + ", image=" + image() + ")";
	}
	
	
	/**
	 * Returns this cursor's hotspot. If the cursor's image's hit area overlaps
	 * this point, the cursor will become visible.
	 */
	public function hotSpot():NSPoint
	{
		return m_hotSpot;
	}
	
	
	/**
	 * Returns this cursor's image.
	 *
	 * The size of this image determines when the cursor will be shown. If the
	 * image's rect overlaps hotSpot().
	 */
	public function image():NSImage
	{
		return m_image;
	}
	
	
	//******************************************************															 
	//*           Cursor Stack Manipulation
	//******************************************************
	
	/**
	 * Pops the current cursor off of NSCursor stack. 
	 *
	 * Note that in Objective-C, this method is called -(void) pop(). Since
	 * we can't have a class method named the same as an instance method,
	 * we've changed its name.
	 *
	 * @see NSCursor#pop
	 */
	public function popCursor():Void
	{
		NSCursor.pop();
	}
	
	
	/**
	 * Pushes this cursor on to the top of the cursor stack. This cursor will
	 * be displayed immediately.
	 */
	public function push():Void
	{
		
	}
	
	
	/**
	 * Sets this cursor to be the current cursor.
	 *
	 * Note that in Objective-C, this method is called -(void) set(). Since
	 * set is a reserved word in actionscript, this method name has been
	 * changed for the ActionStep implementation.
	 */
	public function setSelf():Void
	{
		//!
	}
	
	//******************************************************															 
	//*                  Private Methods
	//******************************************************
	//******************************************************															 
	//*            Class Properties - Cursors
	//******************************************************
	
	/**
	 * Returns the current cursor.
	 */
	public static function current():NSCursor
	{
		return g_current;
	}
	
	
	/**
	 * Returns the default arrow cursor. Hotspot at the tip.
	 */
	public static function arrowCursor():NSCursor	
	{
		return g_arrowCursor;
	}
	
	
	/**
	 * Returns the closed hand cursor.
	 */
	public static function closedHandCursor():NSCursor
	{
		return g_closedHandCursor;
	}
	
	
	/**
	 * Returns the cross-hair cursor, used when precision is necessary.
	 */
	public static function crosshairCursor():NSCursor
	{
		return g_crosshairCursor;
	}
	
	
	/**
	 * Returns a cursor that displays an item disappearing.
	 */
	public static function disappearingItemCursor():NSCursor
	{
		return g_disappearingItemCursor;
	}	

	
	/**
	 * Returns the cursor used when hovering over text. It is used to
	 * specify the insertion point when clicking on text. The hotspot is
	 * where the I meets the top crossbeam.
	 */
	public static function IBeamCursor():NSCursor
	{
		return g_IBeamCursor;
	}
	
	
	/**
	 * Returns the open hand cursor.
	 */
	public static function openHandCursor():NSCursor
	{
		return g_openHandCursor;
	}
	
	
	/**
	 * Returns the pointing hand cursor.
	 */
	public static function pointingHandCursor():NSCursor
	{
		return g_pointingHandCursor;
	}


	/**
	 * Returns the resize-down cursor.
	 */
	public static function resizeDownCursor():NSCursor
	{
		return g_resizeDownCursor;
	}
	

	/**
	 * Returns the resize-left cursor.
	 */	
	public static function resizeLeftCursor():NSCursor
	{
		return g_resizeLeftCursor;
	}
	

	/**
	 * Returns the resize-left-and-right cursor.
	 */	
	public static function resizeLeftRightCursor():NSCursor
	{
		return g_resizeLeftRightCursor;
	}
	
	
	/**
	 * Returns the resize-right cursor.
	 */	
	public static function resizeRightCursor():NSCursor
	{
		return g_resizeRightCursor;
	}
	
	
	/**
	 * Returns the resize-up cursor.
	 */	
	public static function resizeUpCursor():NSCursor
	{
		return g_resizeUpCursor;
	}	
	
	
	/**
	 * Returns the resize-up-and-down cursor.
	 */	
	public static function resizeUpDownCursor():NSCursor
	{
		return g_resizeUpDownCursor;
	}
	
	
	//******************************************************															 
	//*            Class Methods - Cursor Stack
	//******************************************************
		
	public static function pop():Void
	{
		
	}
	
	//******************************************************															 
	//*     Class Methods - Current Cursor Visibility
	//******************************************************
	
	/**
	 * Hides the current cursor.
	 */
	public static function hide():Void
	{
		
	}
	
	
	/**
	 * Unhides the current cursor.
	 */
	public static function unhide():Void
	{
		
	}
	
	
	/**
	 * If flag is TRUE, a call to this method hides the current cursor until
	 * the mouse moves or the method is called again with flag as FALSE.
	 *
	 * unhide() will not counter the effects of this method call.
	 */
	public static function setHiddenUntilMouseMoves(flag:Boolean):Void
	{
		
	}
}
