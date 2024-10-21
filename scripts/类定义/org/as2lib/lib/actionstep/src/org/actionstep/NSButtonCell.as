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

 import org.actionstep.ASTheme;

 
import org.actionstep.NSActionCell;
import org.actionstep.NSImage;
import org.actionstep.NSSound;
import org.actionstep.NSFont;
import org.actionstep.NSAttributedString;
import org.actionstep.NSEvent;
import org.actionstep.NSRect;
import org.actionstep.NSPoint;
import org.actionstep.NSView;
import org.actionstep.NSSize;
import org.actionstep.NSControl;
import org.actionstep.NSColor;
import org.actionstep.NSCell;

import org.actionstep.constants.NSCellImagePosition;
import org.actionstep.constants.NSGradientType;
import org.actionstep.constants.NSBezelStyle;
import org.actionstep.constants.NSCellType;
import org.actionstep.constants.NSButtonType;
import org.actionstep.constants.NSTextAlignment;

class org.actionstep.NSButtonCell extends NSActionCell {
    
  private var m_textField:TextField;
  private var m_textFormat:TextFormat;

  private var m_highlightsBy:Number;
  private var m_showsStateBy:Number;
  private var m_imageDimsWhenDisabled:Boolean;
  private var m_alternateImage:NSImage;
  private var m_imagePosition:NSCellImagePosition;
  private var m_gradientType:NSGradientType;
  private var m_bezelStyle:NSBezelStyle;
  private var m_showsBorderOnlyWhileMouseInside:Boolean;
  private var m_mouseInside:Boolean;
  private var m_sound:NSSound;
  private var m_keyEquivalent:String;
  private var m_keyEquivalentModifierMask:Number;
  private var m_keyEquivalentFont:NSFont;
  private var m_alternateTitle:String;
  private var m_bcellTransparent:Boolean;
  private var m_backgroundColor:NSColor;
  private var m_periodicInterval:Number;
  private var m_periodicDelay:Number;
	private var m_showAltStateMask:Number;
	private var m_highlightsByMask:Number;

  
  public function NSButtonCell() {
    m_textField = null;
    m_imageDimsWhenDisabled = true;
    m_showsBorderOnlyWhileMouseInside = false;
    m_mouseInside = false;
    m_keyEquivalent = "";
    m_alternateTitle = "";
    m_bcellTransparent = false;
    m_bezelStyle = NSBezelStyle.NSRegularSquareBezelStyle;
  }

  public function release() {
    if (m_textField != null) {
      m_textField.removeTextField();
      m_textField = null;
    }
  }  
  
  private function __init():NSButtonCell {
    setAlignment(NSTextAlignment.NSCenterTextAlignment);
    m_showsStateBy = NSNoCellMask;
    m_highlightsBy = NSPushInCellMask | NSChangeGrayCellMask;
    m_keyEquivalentModifierMask = NSEvent.NSCommandKeyMask;
    m_bordered = true;
    m_keyEquivalent = "";
    m_alternateTitle = "";
    m_gradientType = NSGradientType.NSGradientNone;
    m_bezeled = true;
    m_bordered = false;
    return this;
  }
  
  public function init():NSButtonCell {
    initTextCell("Button");
    return this;
  }
  
  public function initImageCell(image:NSImage):NSButtonCell {
    super.initImageCell(image);
    m_imagePosition = NSCellImagePosition.NSImageOnly;
    return __init();
  }
  
  public function initTextCell(string:String):NSButtonCell {
    super.initTextCell(string);
    m_imagePosition = NSCellImagePosition.NSNoImage;
    return __init();
  }

  // Setting the titles

  public function setType(type:NSCellType) {
    //Do nothing (just like Cocoa)
  }
  
  public function setTitle(title:String) {
    setStringValue(title);
  }
  
  public function title():String {
    return stringValue();
  }
  
  public function setAlternateTitle(value:String) {
    m_alternateTitle = value;
    if (m_controlView != null) {
      if (m_controlView instanceof NSControl) {
        NSControl(m_controlView).updateCell(this);
      }
    }  
  }
  
  public function setAttributedTitle(string:NSAttributedString) {
    setAttributedStringValue(string);
  }
  
  public function attributedTitle():NSAttributedString {
    return attributedStringValue();
  }
  
  public function setAttributedAlternateTitle(attribString:NSAttributedString) {
    //! Implement this
    setAlternateTitle(attribString.string());
  }
  
  public function attributedAlternateTitle():NSAttributedString {
    //! Implement this
    return null;
  }
  
  public function alternateTitle():String {
    return m_alternateTitle;
  }
  
  public function setFont(font:NSFont) {
    super.setFont(font);
    if((font != null) && (m_keyEquivalentFont!=null) && font.pointSize()!=m_keyEquivalentFont.pointSize()) {
      setKeyEquivalentFont(NSFont.fontWithNameSizeEmbedded(m_keyEquivalentFont.fontName(), font.pointSize(), font.isEmbedded()));
    }
  }
  
  public function setFontColor(color:NSColor) {
    super.setFontColor(color);
    if (m_textFormat != null) {
      m_textFormat.color = color.value;
    }
    if (m_textField != null) {
      m_textField._alpha = color.alphaComponent();
    }
  }

  // Setting the images
  
  public function setAlternateImage(value:NSImage) {
    m_alternateImage = value;
  }
  
  public function alternateImage():NSImage {
    return m_alternateImage;
  }
  
  public function setImagePosition(value:NSCellImagePosition) {
    m_imagePosition = value;
  }
  
  public function imagePosition():NSCellImagePosition {
    return m_imagePosition;
  }
  
  // Setting the repeat interval
  
  /**
   * Returns an object with delay and interval properties
   */
  public function getPeriodicDelayInterval():Object {
    return {delay:m_periodicDelay, interval:m_periodicInterval};
  }
  
  public function setPeriodicDelayInterval(delay:Number, interval:Number) {
    m_periodicDelay = delay;
    m_periodicInterval = interval;
  }
  
  // Setting the key equivalent

  public function setKeyEquivalent(value:String) {
    m_keyEquivalent = value;
  }
  
  public function keyEquivalent():String {
    return m_keyEquivalent;
  }
  
  public function setKeyEquivalentModifierMask(value:Number) {
    m_keyEquivalentModifierMask = value;
  }
  
  public function keyEquivalentModifierMask():Number {
    return m_keyEquivalentModifierMask;
  }
  
  public function setKeyEquivalentFont(value:NSFont) {
    m_keyEquivalentFont = value;
  }
  
  public function setKeyEquivalentFontSize(font:String, size:Number) {
    m_keyEquivalentFont = NSFont.fontWithNameSize(font, size);
  }
  
  public function keyEquivalentFont():NSFont {
    return m_keyEquivalentFont;
  }

  // Modifying graphics attributes
  
  public function setBackgroundColor(value:NSColor) {
    m_backgroundColor = value;
  }
  
  public function backgroundColor():NSColor {
    return m_backgroundColor;
  }
  
  public function setTransparent(value:Boolean) {
    m_bcellTransparent = value;
  }
  
  public function isTransparent():Boolean {
    return m_bcellTransparent;
  }
  
  public function isOpaque():Boolean {
    return m_bordered && !m_bcellTransparent;
  }
  
  public function setShowsBorderOnlyWhileMouseInside(value:Boolean) {
    m_showsBorderOnlyWhileMouseInside = value;
  }
  
  public function showsBorderOnlyWhileMouseInside():Boolean {
    return m_showsBorderOnlyWhileMouseInside;
  }
  
  public function setGradientType(value:NSGradientType) {
    m_gradientType = value;
  }
  
  public function gradientType():NSGradientType {
    return m_gradientType;
  }
  

  public function setImageDimsWhenDisabled(value:Boolean) {
    m_imageDimsWhenDisabled = value;
  }

  public function imageDimsWhenDisabled():Boolean {
    return m_imageDimsWhenDisabled;
  }
  
  public function setBezelStyle(value:NSBezelStyle) {
    m_bezelStyle = value;
  }
  
  public function bezelStyle():NSBezelStyle {
    return m_bezelStyle;
  }

  // Displaying
  
  public function setButtonType(type:NSButtonType) {
    switch(type.value) {
      case NSButtonType.NSMomentaryLightButton.value:
        setHighlightsBy(NSPushInCellMask | NSChangeGrayCellMask);
        setShowsStateBy(NSChangeBackgroundCellMask);
        setImageDimsWhenDisabled(true);
        break;
      case NSButtonType.NSPushOnPushOffButton.value:
        setHighlightsBy(NSPushInCellMask | NSChangeGrayCellMask);
        setShowsStateBy(NSChangeBackgroundCellMask);
        setImageDimsWhenDisabled(true);
        break;
      case NSButtonType.NSToggleButton.value:
        setHighlightsBy(NSPushInCellMask | NSContentsCellMask);
        setShowsStateBy(NSContentsCellMask);
        setImageDimsWhenDisabled(true);
        break;
      case NSButtonType.NSRadioButton.value:
        setHighlightsBy(NSContentsCellMask);
        setShowsStateBy(NSContentsCellMask);
        setAlignment(NSTextAlignment.NSLeftTextAlignment);
        setImage(NSImage.imageNamed("NSRadioButton"));
        setAlternateImage(NSImage.imageNamed("NSHighlightedRadioButton"));
        setImagePosition(NSCellImagePosition.NSImageLeft);
        setBordered(false);
        setBezeled(false);
        setImageDimsWhenDisabled(false);
        break;
      case NSButtonType.NSSwitchButton.value:
        setHighlightsBy(NSContentsCellMask);
        setShowsStateBy(NSContentsCellMask);
        setAlignment(NSTextAlignment.NSLeftTextAlignment);
        setImage(NSImage.imageNamed("NSSwitch"));
        setAlternateImage(NSImage.imageNamed("NSHighlightedSwitch"));
        setImagePosition(NSCellImagePosition.NSImageLeft);
        setBordered(false);
        setBezeled(false);
        setImageDimsWhenDisabled(true);
        break;
      case NSButtonType.NSMomentaryChangeButton.value:
        setHighlightsBy(NSContentsCellMask);
        setShowsStateBy(NSNoCellMask);
        setImageDimsWhenDisabled(true);
        break;
      case NSButtonType.NSOnOffButton.value:
        setHighlightsBy(NSChangeBackgroundCellMask);
        setShowsStateBy(NSChangeBackgroundCellMask);
        setImageDimsWhenDisabled(true);
        break;
      case NSButtonType.NSMomentaryPushInButton.value:
        setHighlightsBy(NSPushInCellMask | NSChangeGrayCellMask);
        setShowsStateBy(NSNoCellMask);
        setImageDimsWhenDisabled(true);
        break;
    }
  }
  
  public function setHighlightsBy(value:Number) {
    m_highlightsBy = value;
  }
  
  public function highlightsBy():Number {
    return m_highlightsBy;
  }
  
  public function setShowsStateBy(value:Number) {
    m_showsStateBy = value;
  }
  
  public function showsStateBy():Number {
    return m_showsStateBy;
  }
  
  // Playing sound

  public function setSound(value:NSSound) {
    m_sound = value;
  }
  
  public function sound():NSSound {
    return m_sound;
  }
  
  // Handling events and action messages
  
  public function mouseEntered(event:NSEvent) {
    m_mouseInside = true;
  }

  public function mouseExited(event:NSEvent) {
    m_mouseInside = false;
  }
  
  public function performClickWithFrameInView(frame:NSRect, view:NSView) {
    if (m_sound != null) {
      m_sound.play();
    }
    super.performClickWithFrameInView(frame, view);
  }
  
  // Drawing 
  
  public function cellSize():NSSize {
    var size:NSSize = new NSSize(0,0);
    var titleSize:NSSize;
    var imageSize:NSSize;
    var borderSize:NSSize;
    var mask:Number;
    var image:NSImage;
    var title:NSAttributedString;
    
    if (m_highlighted) {
      mask = m_highlightsBy;
      if (m_state == 1) {
        mask &= ~m_showsStateBy;
      }
    } else if (m_state == 1) {
      mask = m_showsStateBy;
    } else {
      mask = NSCell.NSNoCellMask;
    }
    
    if (mask & NSCell.NSContentsCellMask) {
      image = m_alternateImage;
      if (image == null) {
        image = m_image;
      }
      title = attributedAlternateTitle();
      if (title == null || title.string().length==0) {
        title = attributedTitle();
      }
    } else {
      image = m_image;
      title = attributedTitle();
    }
    
    if (title != null) {
      titleSize = m_font.getTextExtent(title.string());
    }
    if (image != null) {
      imageSize = image.size();
    }
    
    switch (m_imagePosition) {
    case NSCellImagePosition.NSNoImage:
      size = titleSize;
      break;
    case NSCellImagePosition.NSImageOnly:
      size = imageSize;
      break;
    case NSCellImagePosition.NSImageLeft:
    case NSCellImagePosition.NSImageRight:
      size.width = titleSize.width + imageSize.width + 5;
      size.height = Math.max(imageSize.height, titleSize.height);
      break;
    case NSCellImagePosition.NSImageBelow:
    case NSCellImagePosition.NSImageAbove:
      size.width = Math.max(imageSize.width, titleSize.width);
      size.height = imageSize.height + titleSize.height + 3;
      break;
    case NSCellImagePosition.NSImageOverlaps:
      size.width = Math.max(imageSize.width, titleSize.width);
      size.height = Math.max(imageSize.height, titleSize.height);
      break;
    }
    
    if (m_bordered) {
      borderSize = new NSSize(3,3);
    } else {
      borderSize = new NSSize(0,0);
    }    
    if ((m_bordered && m_imagePosition != NSCellImagePosition.NSImageOnly) || m_bezeled) {
      borderSize.width += 6;
      borderSize.height += 6;
    }
    size.width += borderSize.width;
    size.height += borderSize.height;
    return size;
  }

  public function drawWithFrameInView(cellFrame:NSRect, inView:NSView) {
    if (m_controlView != inView) {
      m_controlView = inView;
    }
    
    if (m_bcellTransparent) {
      return;
    }
    
    var mc:MovieClip = m_controlView.mcBounds();
    
    var titleSize:NSSize;
    var imageRect:NSRect = new NSRect(0,0,0,0);
    var mask:Number;
    var image:NSImage;
    var title:NSAttributedString;
		
		if (m_highlighted) {
      mask = m_highlightsBy;
      if (m_state == 1) {
        mask &= ~m_showsStateBy;
      }
    } else if (m_state == 1) {
      mask = m_showsStateBy;
    } else {
      mask = NSCell.NSNoCellMask;
    }

    if (mask & NSCell.NSContentsCellMask) {
      image = m_alternateImage;
      if (image == null) {
        image = m_image;
      }
      title = attributedAlternateTitle();
      if (title == null || title.string().length==0) {
        title = attributedTitle();
      }
    } else {
      image = m_image;
      title = attributedTitle();
    }

    if (title != null) {
      titleSize = m_font.getTextExtent(title.string());
    }
    if (image != null) {
      imageRect.size = image.size();
    }
		
		drawTitleInView(m_controlView, title);
		
		imageRect.origin = positionParts(cellFrame, imageRect.size, titleSize);

    drawBorderAndBackgroundWithFrameInView
		(cellFrame, m_controlView, imageRect.origin, mask);
    
		drawImageWithFrameInView
		(cellFrame, m_controlView, imageRect, image);
  }
	
  private function drawTitleInView(controlView:NSView, title:NSAttributedString):Void {
  	if (m_textField == null || m_textField._parent == undefined) {
      m_textField = controlView.createBoundsTextField();
      m_textField.autoSize = true;
      m_textField.selectable = false;
      m_textFormat = m_font.textFormat();
      m_textFormat.color = m_fontColor.value;
      m_textField._alpha = m_fontColor.alphaComponent()*100;
      m_textField.embedFonts = m_font.isEmbedded();
    }
	
    if (title.string() == null) {
      m_textField.text = "";
    } else if (m_textField.text != title.string()) {
      if (title.isFormatted()) {
        m_textField.html = true;
        m_textField.htmlText = title.htmlString();
      } else {
        m_textField.text = title.string();
        m_textField.setTextFormat(m_textFormat);
      }
    }
    
		if (m_imagePosition == NSCellImagePosition.NSImageOnly) {
      m_textField._visible = false;
    } else {
      m_textField._visible = true;
    }
	}
	
	private function drawBorderAndBackgroundWithFrameInView(cellFrame:NSRect, inView:NSView, imageLocation:NSPoint, mask:Number):Void {
		if (!m_bordered && !m_bezeled && m_backgroundColor != null) {
      ASTheme.current().drawFillWithRectColorInView(cellFrame, m_backgroundColor, inView);
    }

    if (m_bordered) {
      if (m_enabled) {
        ASTheme.current().drawBorderButtonWithRectInView(cellFrame, inView);
      } else {
        ASTheme.current().drawBorderButtonDisabledWithRectInView(cellFrame, inView);
      }
    } else if (m_bezeled) {
      if (m_highlighted || !m_enabled || (mask & (NSChangeGrayCellMask | NSChangeBackgroundCellMask))) {
        m_textField._x += 1;
        m_textField._y += 1;
        imageLocation.x += 1;
        imageLocation.y += 1;
      }
      if (m_enabled) {
        if (m_highlighted || (mask & (NSChangeGrayCellMask | NSChangeBackgroundCellMask))) {
            ASTheme.current().drawBezelButtonDownWithRectInViewHasShadow(cellFrame, inView, m_bezelStyle != NSBezelStyle.NSShadowlessSquareBezelStyle);
        } else {
          ASTheme.current().drawBezelButtonUpWithRectInViewHasShadow(cellFrame, inView, m_bezelStyle != NSBezelStyle.NSShadowlessSquareBezelStyle);
        }
      } else {
        ASTheme.current().drawBezelButtonDisabledWithRectInViewHasShadow(cellFrame, inView, m_bezelStyle != NSBezelStyle.NSShadowlessSquareBezelStyle);
      }      
    }
	}
	
	private function drawImageWithFrameInView(cellFrame:NSRect, inView:NSView, imageRect:NSRect, image:NSImage):Void {
    if (image != null) {
      image.lockFocus(inView.mcBounds());
      image.drawAtPoint(imageRect.origin);
      image.unlockFocus();
    }
    if (m_showsFirstResponder) {
      if (image != null) {
        ASTheme.current().drawFirstResponderWithRectInView(new NSRect(
				imageRect.origin.x-1, imageRect.origin.y-1, 
				imageRect.size.width+2, imageRect.size.height+2), inView);
      } else {
        ASTheme.current().drawFirstResponderWithRectInView(cellFrame, inView);
      }
    }
	}
	
	private function positionParts(cellFrame:NSRect, imageSize:NSSize, titleSize:NSSize):NSPoint {
		var borderSize:NSSize;
		
		if (m_bordered) {
      borderSize = new NSSize(3,3);
    } else {
      borderSize = new NSSize(0,0);
    }    
    if ((m_bordered && m_imagePosition != NSCellImagePosition.NSImageOnly) || m_bezeled) {
      borderSize.width += 6;
      borderSize.height += 6;
    }
    
    var imageLocation:NSPoint = new NSPoint(0,0);
		
		var x:Number = cellFrame.origin.x;
    var y:Number = cellFrame.origin.y;
		var width:Number = cellFrame.size.width-1;
    var height:Number = cellFrame.size.height-1;
    
    var combinedHeight:Number = imageSize.height+titleSize.height+3;
    var combinedWidth:Number = imageSize.width+titleSize.width+3;
    
    switch (m_imagePosition) {
    case NSCellImagePosition.NSNoImage:
      m_textField._x = x + (width - titleSize.width)/2;
      m_textField._y = y + (height - titleSize.height)/2;
      break;
    case NSCellImagePosition.NSImageOnly:
      imageLocation.x = x + (width - imageSize.width)/2;
      imageLocation.y = y + (height - imageSize.height)/2;
      break;
    case NSCellImagePosition.NSImageLeft:
      switch(m_alignment) {
      case NSTextAlignment.NSRightTextAlignment:
        imageLocation.x = x + width - combinedWidth - borderSize.width/2 - 1;
        break;
      case NSTextAlignment.NSCenterTextAlignment:
        imageLocation.x = x + (width - combinedWidth)/2;
        break;
      case NSTextAlignment.NSLeftTextAlignment:
      default:
        imageLocation.x = x + borderSize.width/2 + 1;
        break;
      }
      imageLocation.y = y + (height - imageSize.height)/2;
      m_textField._x = imageLocation.x + imageSize.width + 3;
      m_textField._y = y + (height - titleSize.height)/2;
      break;
    case NSCellImagePosition.NSImageRight:
      switch(m_alignment) {
      case NSTextAlignment.NSRightTextAlignment:
        imageLocation.x = x + width - imageSize.width - borderSize.width/2 - 1;
        break;
      case NSTextAlignment.NSCenterTextAlignment:
        imageLocation.x = x + (width - combinedWidth)/2 + titleSize.width + 3;
        break;
      case NSTextAlignment.NSLeftTextAlignment:
      default:
        imageLocation.x = x + borderSize.width/2 + 1 + combinedWidth - imageSize.width;
        break;
      }
      imageLocation.y = y + (height - imageSize.height)/2;
      m_textField._x = imageLocation.x - titleSize.width - 3;
      m_textField._y = y + (height - titleSize.height)/2;
      break;
    case NSCellImagePosition.NSImageBelow:
      m_textField._x = x + (width - titleSize.width)/2;
      imageLocation.x = x + (width - imageSize.width)/2;
      m_textField._y = y + (height - combinedHeight)/2;
      imageLocation.y = m_textField._y + titleSize.height + 3;
      break;
    case NSCellImagePosition.NSImageAbove:
      imageLocation.x = x + (width - imageSize.width)/2;
      imageLocation.y = y + (height - combinedHeight)/2;
      m_textField._x = x + (width - titleSize.width)/2;
      m_textField._y = y + imageLocation.y + imageSize.height + 3;
      break;
    case NSCellImagePosition.NSImageOverlaps:
      imageLocation.x = x + (width - imageSize.width)/2;
      imageLocation.y = y + (height - imageSize.height)/2;
      m_textField._x = x + (width - titleSize.width)/2;
      m_textField._y = y + (height - titleSize.height)/2;
      break;
    }
		
		return imageLocation;
	}
}