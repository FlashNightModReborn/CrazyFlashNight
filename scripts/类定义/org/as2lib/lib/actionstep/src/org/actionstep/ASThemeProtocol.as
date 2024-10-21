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

//import org.actionstep.NSSize;
//import org.actionstep.NSPoint;
//import org.actionstep.NSArray;
import org.actionstep.NSColor;
import org.actionstep.NSColorList;
import org.actionstep.NSRect;
import org.actionstep.NSView;

/**
 * Describes methods that should be implemented by any "Theme" object, the core
 * object for theming, as all control drawing is done through classes that implement
 * this protocol.
 *
 * @author Scott Hyndman
 */
interface org.actionstep.ASThemeProtocol 
{	
	/**
	 * First responder color
	 */
	public function firstResponderColor():NSColor;

	/**
 	 * Sets this theme to the be active theme
 	 */
	public function setActive(value:Boolean):Void;
  
	/**
	 * Draws a filled rectangle with the color aColor in the view inView.
	 */
	public function drawFillWithRectColorInView(aRect:NSRect, aColor:NSColor, inView:NSView):Void;
	
	/**
	 * Draws a NSButton in the up state bezeled with the supplied rect in the view.
	 */
	public function drawBezelButtonUpWithRectInViewHasShadow(rect:NSRect, view:NSView, hasShadow:Boolean):Void;

	/**
	 * Draws a NSButton in the down state bezeled with the supplied rect in the view.
	 */
	public function drawBezelButtonDownWithRectInViewHasShadow(rect:NSRect, view:NSView, hasShadow:Boolean):Void;

	/**
	 * Draws a NSButton in the disabled state bezeled with the supplied rect in the view.
	 */
	public function drawBezelButtonDisabledWithRectInViewHasShadow(rect:NSRect, view:NSView, hasShadow:Boolean):Void;

	/**
	 * Draws a NSButton bordered with the supplied rect in the view.
	 */
	public function drawBorderButtonWithRectInView(rect:NSRect, view:NSView):Void;

	/**
	 * Draws a NSButton bordered with the supplied rect in the view.
	 */
	public function drawBorderButtonDisabledWithRectInView(rect:NSRect, view:NSView):Void;
	
	/**
	 * Draws the border around the button when it has key focus
	 */
	public function drawFirstResponderWithRectInView(rect:NSRect, view:NSView):Void;

	/**
	 * Draws the border around the button when it has key focus
	 */
	public function drawFirstResponderWithRectInClip(rect:NSRect, clip:MovieClip):Void;

	/**
	 * Draws the the ASList background
	 */
	public function drawListWithRectInView(rect:NSRect, view:NSView):Void;
	
	/**
	 * Draws an NSTextFieldCell in the view.
	 */
	public function drawTextFieldWithRectInView(rect:NSRect, view:NSView):Void;
	
	/**
	 * Draws an NSScroller slot in the view.
	 */
	public function drawScrollerSlotWithRectInView(rect:NSRect, view:NSView):Void;

	/**
	 * Draws an NSScroller slot in the view.
	 */
	public function drawScrollerWithRectInClip(rect:NSRect, clip:MovieClip):Void;

	/**
	 * Draws a table header in the view. If highlighted is TRUE, it means the
	 * column header should be drawn selected.
	 */
	public function drawTableHeaderWithRectInViewHighlighted(rect:NSRect, view:NSView, highlighted:Boolean):Void;
	
	/**
	 * Returns the list of colors used by the application.
	 * 
	 * The following keys are used by the theme:
	 * 	"alternatingRowColor" - The NSTable's alternating row color.
	 */
	public function colors():NSColorList;
	
	/**
	 * Sets the list of colors used by the theme.
	 * 
	 * @see #colors
	 */
	public function setColors(aColorList:NSColorList):Void;
	
	/**
	 * Registers the default image representations for buttons and other 
	 * controls.
	 */
	public function registerDefaultImages():Void;

}
