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

import org.actionstep.ASDraw;
import org.actionstep.ASThemeProtocol;
//import org.actionstep.NSArray;
import org.actionstep.NSColor;
import org.actionstep.NSImage;
import org.actionstep.NSRect;
import org.actionstep.NSView;
import org.actionstep.NSColorList;

/**
 * This is the default ActionStep drawer.
 *
 * The current drawer can be accessed through the current class property.
 *
 * @author Scott Hyndman
 * @author Rich Kilmer
 */
class org.actionstep.ASTheme extends org.actionstep.NSObject
  implements ASThemeProtocol
{	
  private static var g_current:ASThemeProtocol;
  private var m_firstResponderColor:NSColor;
  private var m_colorList:NSColorList;
  
  /**
   * Constructs a new instance of ASTheme.
   */
  private function ASTheme() {
    m_firstResponderColor = new NSColor(0x3333dd);
  }

  /**
   * Can perform setup operations in this method
   */
  public function setActive(value:Boolean) {
  }
	
  //******************************************************															 
  //*                   Properties
  //******************************************************
  //******************************************************															 
  //*                 Public Methods
  //******************************************************
	
  /**
   * @see org.actionstep.ASThemeProtocol#drawFillWithRectColorInView
   */
  public function drawFillWithRectColorInView(aRect:NSRect, aColor:NSColor, 
    inView:NSView):Void
  {
    ASDraw.solidRectWithAlphaRect(inView.mcBounds(), aRect, aColor.value, aColor.alphaComponent()*100);
  }

  public function drawBorderButtonWithRectInView(rect:NSRect, view:NSView) {
    drawBorderButtonUp(view.mcBounds(), rect);
  }

  public function drawListWithRectInView(rect:NSRect, view:NSView) {
    var mc:MovieClip = view.mcBounds();
    var topShadowRect:NSRect  = ASDraw.getScaledPixelRect(rect, rect.size.width-20, 0, -rect.size.width+3,                   -2);
    //var itemHiliteRect = ASDraw.getScaledPixelRect(rect, 1, 0, -22, -rect.size.height+19);

    drawTextfield(mc, rect);
    //these are the textfield left fade colors
    //ASDraw.gradientRectWithAlphaRect(mc, topShadowRect, ASDraw.ANGLE_LEFT_TO_RIGHT, [0x767A85, 0xB6BBC1], [0,255], [50,0]);
    //ASDraw.gradientRectWithAlphaRect(mc, itemHiliteRect, ASDraw.ANGLE_LEFT_TO_RIGHT, 
    //  [0x494D56, 0x494D56, 0x494D56, 0x494D56], [265,373,413,430], [40,40,0,0]);
  }

  public function drawBorderButtonDisabledWithRectInView(rect:NSRect, view:NSView) {
    drawBorderButtonDown(view.mcBounds(), rect);
  }

  public function firstResponderColor():NSColor {
    return m_firstResponderColor;
  }

  public function drawFirstResponderWithRectInView(rect:NSRect, view:NSView) {
    drawFirstResponderWithRectInClip(rect, view.mcBounds());
  }

  public function drawFirstResponderWithRectInClip(rect:NSRect, mc:MovieClip) {
    var x:Number = rect.origin.x+1;
    var y:Number = rect.origin.y+1;
    var width:Number = rect.size.width-3;
    var height:Number = rect.size.height-3;
    var color:Number = firstResponderColor().value;

    mc.lineStyle(3, color, 40);
    mc.moveTo(x, y);
    mc.lineTo(x+width, y);
    mc.lineTo(x+width, y+height);
    mc.lineTo(x, y+height);
    mc.lineTo(x, y);
  }

  public function drawBezelButtonUpWithRectInViewHasShadow(rect:NSRect, view:NSView, hasShadow:Boolean) {
    if (hasShadow) {
      drawButtonUp(view.mcBounds(), rect);
    } else {
      drawButtonUpWithoutBorder(view.mcBounds(), rect);
    }
  }

  public function drawBezelButtonDownWithRectInViewHasShadow(rect:NSRect, view:NSView, hasShadow:Boolean) {
    if (hasShadow) {
      drawButtonDown(view.mcBounds(), rect);
    } else {
      drawButtonDownWithoutBorder(view.mcBounds(), rect);
    }
  }

  public function drawBezelButtonDisabledWithRectInViewHasShadow(rect:NSRect, view:NSView, hasShadow:Boolean) {
    if (hasShadow) {
      drawButtonDown(view.mcBounds(), rect);
    } else {
      drawButtonDownWithoutBorder(view.mcBounds(), rect);
    }
  }
	
  public function drawTextFieldWithRectInView(rect:NSRect, view:NSView) {
    drawTextfield(view.mcBounds(), rect);
  }	

  public function drawScrollerSlotWithRectInView(rect:NSRect, view:NSView) {
    drawScrollerSlot(view.mcBounds(), rect);
  }	
  
  public function drawScrollerWithRectInClip(rect:NSRect, clip:MovieClip) {
    drawScroller(clip, rect);
  }	

  public function drawTableHeaderWithRectInViewHighlighted(rect:NSRect, view:NSView, highlighted:Boolean) {
    drawTextFieldWithRectInView(rect, view); //! this is not done
  }

  /**
   * @see org.actionstep.ASThemeProtocol#colors
   */
  public function colors():NSColorList {
    return m_colorList;
  }
  
  /**
   * @see org.actionstep.ASThemeProtocol#setColors
   */
  public function setColors(aColorList:NSColorList):Void {
    m_colorList = aColorList;
  }
  
  public function registerDefaultImages() {
    setImage("NSRadioButton", org.actionstep.images.ASRadioButtonRep);
    setImage("NSHighlightedRadioButton", org.actionstep.images.ASHighlightedRadioButtonRep);
    setImage("NSSwitch", org.actionstep.images.ASSwitchRep);
    setImage("NSHighlightedSwitch", org.actionstep.images.ASHighlightedSwitchRep);

    setImage("NSScrollerUpArrow", org.actionstep.images.ASScrollerUpArrowRep);
    setImage("NSHighlightedScrollerUpArrow", org.actionstep.images.ASHighlightedScrollerUpArrowRep);
    setImage("NSScrollerDownArrow", org.actionstep.images.ASScrollerDownArrowRep);
    setImage("NSHighlightedScrollerDownArrow", org.actionstep.images.ASHighlightedScrollerDownArrowRep);

    setImage("NSScrollerLeftArrow", org.actionstep.images.ASScrollerLeftArrowRep);
    setImage("NSHighlightedScrollerLeftArrow", org.actionstep.images.ASHighlightedScrollerLeftArrowRep);
    setImage("NSScrollerRightArrow", org.actionstep.images.ASScrollerRightArrowRep);
    setImage("NSHighlightedScrollerRightArrow", org.actionstep.images.ASHighlightedScrollerRightArrowRep);
    
    setImage("NSSortUpIndicator", org.actionstep.images.ASSortUpIndicatorRep);
    setImage("NSSortDownIndicator", org.actionstep.images.ASSortDownIndicatorRep);
  }

  public function setImage(name:String, klass:Function) {
    var image:NSImage = (new NSImage()).init();
    image.setName(name);
    image.addRepresentation(new klass());
  }

/**
* @see org.actionstep.NSObject#description
*/
  public function description():String 
  {
    return "ASTheme";
  }
	
  //******************************************************															 
  //*               Private Methods	
  //******************************************************

  private function drawBorderButtonUp(mc:MovieClip, rect:NSRect) {
    var x:Number = rect.origin.x;
    var y:Number = rect.origin.y;
    var width:Number = rect.size.width-1;
    var height:Number = rect.size.height-1;
    ASDraw.drawFill(mc, 0xC7CAD1, x, y, width, height);
    ASDraw.drawRect(mc, 1, 0, x, y, width, height);
  }

  private function drawBorderButtonDown(mc:MovieClip, rect:NSRect) {
    var x:Number = rect.origin.x;
    var y:Number = rect.origin.y;
    var width:Number = rect.size.width-1;
    var height:Number = rect.size.height-1;
    ASDraw.drawFill(mc, 0xB1B5BC, x, y, width, height);
    ASDraw.drawRect(mc, 1, 0, x, y, width, height);
  }

	///////////////////////////////
	// BUTTON DRAW FUNCTIONS

  private static var drawButtonUp_outlineColors:Array = [0x82858E, 0xD3D6DB];
  private static var drawButtonUp_inlineColors:Array  = [0xDFE2E9, 0x858992];
  private static var drawButtonUp_colors:Array = [0xEEF2F5, 0xC7CAD1, 0xC7CAD1, 0x858992];
  private static var drawButtonUp_ratios:Array = [       1,       5,       23,       26];
  private function drawButtonUp(mc:MovieClip, rect:NSRect) 
  {
    drawButtonUpWithoutBorder(mc, rect.insetRect(1,1));
    ASDraw.outlineRectWithRect( mc, rect, drawButtonUp_outlineColors);
  }

  private function drawButtonUpWithoutBorder(mc:MovieClip, rect:NSRect) 
  {
    ASDraw.gradientRectWithRect(mc, rect, ASDraw.ANGLE_TOP_TO_BOTTOM, drawButtonUp_colors, drawButtonUp_ratios);
    ASDraw.outlineRectWithRect( mc, rect, drawButtonUp_inlineColors);
  }

  private static var drawButtonDown_outlineColors:Array = [0x82858E, 0xECEDF0];
  private static var drawButtonDown_inlineColors:Array  = [0x696F79, 0xD4D6DB];
  private static var drawButtonDown_colors:Array = [0x696F79, 0xB1B5BC, 0xB1B5BC, 0xD9DBDF, 0xC9CDD2];
  private static var drawButtonDown_ratios:Array = [       1,        5,       23,       25,       26];
  private function drawButtonDown(mc:MovieClip, rect:NSRect) 
  {
    drawButtonDownWithoutBorder(mc, rect.insetRect(1,1));
    ASDraw.outlineRectWithRect( mc, rect, drawButtonDown_outlineColors);
  }

  private function drawButtonDownWithoutBorder(mc:MovieClip, rect:NSRect) 
  {
    ASDraw.gradientRectWithRect(mc, rect, ASDraw.ANGLE_TOP_TO_BOTTOM, drawButtonDown_colors, drawButtonDown_ratios);
    ASDraw.outlineRectWithRect( mc, rect, drawButtonDown_inlineColors);
  }


	// END BUTTON DRAW FUNCTIONS
	///////////////////////////////

	///////////////////////////////
	// TEXTFIELD DRAW FUNCTIONS
  private static var drawTextfield_outlineColors:Array = [0x4B4F57, 0xDEE1E6];
  private static var drawTextfield_colors:Array = [0x80848F, 0xAFB4BA, 0xCACDD2];
  private static var drawTextfield_ratios:Array = [       0,       6,        24];
  private static var drawTextfieldShadow_colors:Array = [0x767A85, 0xB6BBC1];
  private static var drawTextfieldShadow_alphas:Array = [     100,        0];
  private static var drawTextfieldShadow_ratios:Array = [       0,        5];
  private function drawTextfield(mc:MovieClip, rect:NSRect) 
  {
    var insetRect:NSRect = rect.insetRect(1,1);
    ASDraw.solidRectWithRect(        mc, rect, 0xCACDD2);
    //ASDraw.gradientRectWithRect(     mc, rect, ANGLE_TOP_TO_BOTTOM, drawTextfield_colors, drawTextfield_ratios);
    ASDraw.gradientRectWithRect(     mc, new NSRect(rect.origin.x, rect.origin.y, rect.size.width, 25), ASDraw.ANGLE_TOP_TO_BOTTOM, 
                                            drawTextfield_colors, drawTextfield_ratios);
    ASDraw.gradientRectWithAlphaRect(mc, new NSRect(rect.origin.x, rect.origin.y, 5, rect.size.height), 30, 
                                            drawTextfieldShadow_colors, drawTextfieldShadow_ratios, drawTextfieldShadow_alphas);
    ASDraw.outlineRectWithRect(      mc, rect, drawTextfield_outlineColors);
  }
	// END TEXTFIELD DRAW FUNCTIONS
	///////////////////////////////

	///////////////////////////////
	// SCROLLER DRAW FUNCTIONS
	private static var drawScrollerSlot_outlineColors:Array = [0x4B4F57, 0xDEE1E6];
	private static var drawScrollerSlot_colors:Array = [0x80848F, 0xAFB4BA, 0xCACDD2];
	private static var drawScrollerSlot_ratios:Array = [       0,       6,        24];
	private static var drawScrollerSlotShadow_colors:Array = [0x767A85, 0xB6BBC1];
	private static var drawScrollerSlotShadow_alphas:Array = [     100,        0];
	private static var drawScrollerSlotShadow_ratios:Array = [       0,        5];
	private function drawScrollerSlot(mc:MovieClip, rect:NSRect) 
	{
	  var insetRect:NSRect = rect.insetRect(1,1);
	  ASDraw.solidRectWithRect(        mc, rect, 0xCACDD2);
	  //ASDraw.gradientRectWithRect(     mc, rect, ANGLE_TOP_TO_BOTTOM, drawTextfield_colors, drawTextfield_ratios);
	  ASDraw.gradientRectWithAlphaRect(mc, new NSRect(rect.origin.x, rect.origin.y, rect.size.width, 5), ASDraw.ANGLE_TOP_TO_BOTTOM, 
	                                          drawScrollerSlotShadow_colors, drawScrollerSlotShadow_ratios, drawScrollerSlotShadow_alphas);
	  ASDraw.gradientRectWithAlphaRect(mc, new NSRect(rect.origin.x, rect.origin.y, 5, rect.size.height), 30, 
	                                          drawScrollerSlotShadow_colors, drawScrollerSlotShadow_ratios, drawScrollerSlotShadow_alphas);
	  ASDraw.outlineRectWithRect(      mc, rect, drawScrollerSlot_outlineColors);
	}
	
	private static var drawScroller_outlineColors:Array = [0xDEE1E6, 0x4B4F57];
	private function drawScroller(mc:MovieClip, rect:NSRect) 
	{
	  ASDraw.solidRectWithRect(        mc, rect, 0xCACDD2);
	  ASDraw.outlineRectWithRect(      mc, rect, drawScroller_outlineColors);
	  if (rect.size.width > rect.size.height) {
	    var x1:Number = rect.origin.x + rect.size.width/2-1;
	    var x2:Number = x1 + 6;
	    x1 -= 6;
	    var y1:Number = rect.origin.y + 3;
	    var y2:Number = rect.origin.y + rect.size.height - 4;
	    while (x1 < x2) {
	      mc.lineStyle(1, 0xDEE1E6, 50);
	      mc.moveTo(x1, y1);
	      mc.lineTo(x1, y2);
	      mc.lineStyle(1, 0x4B4F57, 50);
	      mc.moveTo(x1+1, y2);
	      mc.lineTo(x1+1, y1);
	      x1+=2;
	    }
	  } else {
  	  var y1:Number = rect.origin.y + rect.size.height/2-1;
  	  var y2:Number = y1 + 6;
  	  y1 -= 6;
  	  var x1:Number = rect.origin.x + 3;
  	  var x2:Number = rect.origin.x + rect.size.width - 4;
  	  while (y1 < y2) {
        mc.lineStyle(1, 0xDEE1E6, 50);
        mc.moveTo(x1, y1);
        mc.lineTo(x2, y1);
        mc.lineStyle(1, 0x4B4F57, 50);
        mc.moveTo(x2, y1+1);
        mc.lineTo(x1, y1+1);
        y1+=2;
  	  }
  	}
	}
	  
	// END TEXTFIELD DRAW FUNCTIONS
	///////////////////////////////



	//******************************************************															 
	//*			   Public Static Properties				   *
	//******************************************************
	
	/**
	 * Gets / sets the current ASDrawer.
	 */
	public static function current():ASThemeProtocol
	{
		if (g_current == undefined)
		{
			setCurrent(new ASTheme());
		}
		
		return g_current;
	}
	public static function setCurrent(value:ASThemeProtocol)
	{
	  if (g_current != undefined) {
	    g_current.setActive(false);
	  }
		g_current = value;
		g_current.setActive(true);
	}
	
	//******************************************************															 
	//*				 Public Static Methods				   *
	//******************************************************	
}
