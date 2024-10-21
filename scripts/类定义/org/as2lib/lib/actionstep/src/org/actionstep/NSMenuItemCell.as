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
import org.actionstep.NSRect;
import org.actionstep.NSImage;
import org.actionstep.NSSize;
import org.actionstep.NSPoint;
import org.actionstep.NSColor;
import org.actionstep.NSFont;
import org.actionstep.ASDraw;
import org.actionstep.ASTheme;

import org.actionstep.NSButtonCell;
import org.actionstep.NSMenuItem;
import org.actionstep.NSMenuView;
import org.actionstep.constants.NSCellImagePosition;
import org.actionstep.constants.NSTextAlignment;

class org.actionstep.NSMenuItemCell extends NSButtonCell{
	private static var g_arrowImage:NSImage;	/* Cache arrow image.	*/
	
	private var m_menuItem:NSMenuItem;
	private var m_menuView:NSMenuView;

  // Cache
	private var m_needsSizing:Boolean;
	private var m_imageWidth:Number;
	private var m_titleWidth:Number;
	private var m_keyEquivalentWidth:Number;
	private var m_stateImageWidth:Number;
	private var m_menuItemHeight:Number;
	
	private var m_imageToDisplay:NSImage;
	private var m_titleToDisplay:String;
	private var m_imageSize:NSSize;
	
  /* If we belong to a popupbutton, we display image on the extreme
     right */
	private var m_cellBelongsToPopupbutton:Boolean;

	private var m_backgroundColor:NSColor;
	
	public function init():NSMenuItemCell {
		super.init();
		g_arrowImage = NSImage.imageNamed("NSMenuArrow");
		m_target = null;
		m_showAltStateMask = NSNoCellMask;
		m_highlightsByMask = NSChangeBackgroundCellMask;
		setBordered(true);
		setImagePosition(NSCellImagePosition.NSNoImage);
		setAlignment(NSTextAlignment.NSLeftTextAlignment);
		setFont(NSFont.menuFontOfSize(0));
	
		return this;
	}
	
	public function setMenuItem(i:NSMenuItem):Void {
		m_menuItem = i;
		setEnabled(m_menuItem.isEnabled());
	}
	
	public function menuItem():NSMenuItem {
		return m_menuItem;
	}
	
	public function setMenuView(v:NSMenuView):Void {
		m_menuView = v;
	}
	
	public function menuView():NSMenuView {
		return m_menuView;
	}
	
	public function calcSize():Void {
		var componentSize:NSSize = new NSSize(0,0);
		var anImage:NSImage = null;
		var neededMenuItemHeight:Number = 20;
	 
		// Check if m_cellBelongsToPopupbutton = false while cell owned by 
		// popup button. FIXME
		if (!m_cellBelongsToPopupbutton && m_menuView.menu().ownedByPopUp) {
			m_cellBelongsToPopupbutton = true;
			setImagePosition(NSCellImagePosition.NSImageRight);
	}
	
		// State Image
		if (m_menuItem.changesState()) {
			// NSOnState
			if (m_menuItem.onStateImage!=null) {
				componentSize = m_menuItem.onStateImage().size();
			}
			m_stateImageWidth = componentSize.width;
			if (componentSize.height > neededMenuItemHeight) {
				neededMenuItemHeight = componentSize.height;
			}
	
			// NSOffState
			if (m_menuItem.offStateImage!=null) {
				componentSize = m_menuItem.offStateImage().size();
			}
			if (componentSize.width > m_stateImageWidth) {
				m_stateImageWidth = componentSize.width;
			}
			if (componentSize.height > neededMenuItemHeight) {
				neededMenuItemHeight = componentSize.height;
			}
			// NSMixedState
			if (m_menuItem.mixedStateImage!=null) {
				componentSize = m_menuItem.mixedStateImage().size();
			}
			if (componentSize.width > m_stateImageWidth) {
				m_stateImageWidth = componentSize.width;
			}
			if (componentSize.height > neededMenuItemHeight) {
				neededMenuItemHeight = componentSize.height;
			}
		} else {
			m_stateImageWidth = 0;
		}
	
		// Image
		if (((anImage = m_menuItem.image())!=null) && 
		(imagePosition() == NSCellImagePosition.NSNoImage)) {
			setImagePosition(NSCellImagePosition.NSImageLeft);
		}
		if (anImage) {
			componentSize = anImage.size();
			m_imageWidth = componentSize.width;
			if (componentSize.height > neededMenuItemHeight) {
				neededMenuItemHeight = componentSize.height;
			}
		} else {
			m_imageWidth = 0;
		}
	
		// Title and Key Equivalent
		componentSize = font().getTextExtent(m_menuItem.title());
		m_titleWidth = componentSize.width;
		if (componentSize.height > neededMenuItemHeight) {
			neededMenuItemHeight = componentSize.height;
		}
		componentSize = font().getTextExtent(m_menuItem.keyEquivalent());
		m_keyEquivalentWidth = componentSize.width;
		if (componentSize.height > neededMenuItemHeight) {
			neededMenuItemHeight = componentSize.height;
		}
		// Submenu Arrow
		if (m_menuItem.hasSubmenu()) {
			componentSize = g_arrowImage.size();
			m_keyEquivalentWidth = componentSize.width;
			if (componentSize.height > neededMenuItemHeight) {
				neededMenuItemHeight = componentSize.height;
			}
		}
	
		// Cache definitive height
		m_menuItemHeight = neededMenuItemHeight;
	
		// At the end we set sizing to false.
		m_needsSizing = false;
	}
	
	public function setNeedsSizing(flag:Boolean):Void {
		m_needsSizing = flag;
	}
	
	public function needsSizing():Boolean {
		return m_needsSizing;
	}
	
	public function imageWidth():Number {
		if (m_needsSizing) {
			calcSize();
	}
		return m_imageWidth;
	}
	
	public function titleWidth():Number {
		if (m_needsSizing) {
			calcSize();
		}
		return m_titleWidth;
	}
	
	public function keyEquivalentWidth():Number {
		if (m_needsSizing) {
			calcSize();
	}
		return m_keyEquivalentWidth;
	}
	
	public function stateImageWidth():Number {
		if (m_needsSizing) {
			calcSize();
	}
		return m_stateImageWidth;
	}
	
	//
	// Sizes for drawing taking into account NSMenuView adjustments.
	//
	public function imageRectForBounds(cellFrame:NSRect):NSRect {
		if (m_cellBelongsToPopupbutton && imagePosition()!=null) {
			// Special case: draw image on the extreme right 
			cellFrame.origin.x += cellFrame.size.width - m_imageWidth - 4;
			cellFrame.size.width = m_imageWidth;
			return cellFrame;
	}
	
		// Calculate the image part of cell frame from NSMenuView
		cellFrame.origin.x	+= m_menuView.imageAndTitleOffset();
		cellFrame.size.width = m_menuView.imageAndTitleWidth();
	
		switch (imagePosition()) {
			case NSCellImagePosition.NSNoImage: 
				cellFrame = NSRect.ZeroRect;
				break;
	
			case NSCellImagePosition.NSImageOnly:
			case NSCellImagePosition.NSImageOverlaps:
				break;
	
			case NSCellImagePosition.NSImageLeft:
				cellFrame.size.width = m_imageWidth;
				break;
	
			//! FIXME
			case NSCellImagePosition.NSImageRight:
				cellFrame.origin.x	+= m_titleWidth;/* + GSCellTextImageXDist;*/
				cellFrame.size.width = m_imageWidth;
				break;
	
			case NSCellImagePosition.NSImageBelow: 
				cellFrame.size.height /= 2;
				break;
	
			case NSCellImagePosition.NSImageAbove: 
				cellFrame.size.height /= 2;
				cellFrame.origin.y += cellFrame.size.height;
				break;
}
	
		return cellFrame;
	}
	
	public function keyEquivalentRectForBounds(cellFrame:NSRect):NSRect {
		// Calculate the image part of cell frame from NSMenuView
		cellFrame.origin.x	+= m_menuView.keyEquivalentOffset();
		cellFrame.size.width = m_menuView.keyEquivalentWidth();
	
		return cellFrame;
	}
	
	public function stateImageRectForBounds(cellFrame:NSRect):NSRect {
		// Calculate the image part of cell frame from NSMenuView
		cellFrame.origin.x	+= m_menuView.stateImageOffset();
		cellFrame.size.width = m_menuView.stateImageWidth();
	
		return cellFrame;
	}
	
	public function titleRectForBounds(cellFrame:NSRect):NSRect {
		// Calculate the image part of cell frame from NSMenuView
		cellFrame.origin.x	+= m_menuView.imageAndTitleOffset();
		cellFrame.size.width = m_menuView.imageAndTitleWidth();
	
		switch (imagePosition()) {
				case NSCellImagePosition.NSNoImage:
				case NSCellImagePosition.NSImageOverlaps:
		break;
	
				case NSCellImagePosition.NSImageOnly:
		cellFrame = NSRect.ZeroRect;
		break;
	
			//! FIXME
				case NSCellImagePosition.NSImageLeft:
		cellFrame.origin.x	+= m_imageWidth;/* + GSCellTextImageXDist;*/
		cellFrame.size.width = m_titleWidth;
		break;
	
				case NSCellImagePosition.NSImageRight:
		cellFrame.size.width = m_titleWidth;
		break;
	
				case NSCellImagePosition.NSImageBelow:
		cellFrame.size.height /= 2;
		cellFrame.origin.y += cellFrame.size.height;
		break;
	
				case NSCellImagePosition.NSImageAbove:
		cellFrame.size.height /= 2;
		break;
			}
	
		return cellFrame;
	}
	
	//
	// Drawing.
	//
	public function drawBorderAndBackgroundWithFrameInView
	(cellFrame:NSRect, controlView:NSView):Void {
		if (!isBordered()) {
			return;
		}
		if (isHighlighted() && (m_highlightsByMask & NSPushInCellMask)) {
			//! use ASTheme.current()
			//GSDrawFunctions drawGrayBezel:.cellFrame (NSZeroRect];)
		} else {
			//GSDrawFunctions drawButton:.cellFrame (NSZeroRect];)
		}
		trace("");
		
		ASTheme.current().drawBorderButtonWithRectInView
		(cellFrame, controlView);
	}
	
	public function drawImageWithFrameInView(cellFrame:NSRect, controlView:NSView):Void {
		var size:NSSize;
		var position:NSPoint;
	
		cellFrame = imageRectForBounds(cellFrame);
		size = m_imageToDisplay.size();
		position.x = Math.max(cellFrame.minX() - (size.width/2), 0);
		position.y = Math.min(cellFrame.midY() - (size.height/2), 0);
		
		//note: flipped views are ignored
	
		//! FIXME
		/*
		m_imageToDisplay.compositeToPointOperation
		(position ,NSCompositeSourceOver);*/
	}
	
	public function drawKeyEquivalentWithFrameInView
	(cellFrame:NSRect, controlView:NSView):Void {
		cellFrame = keyEquivalentRectForBounds(cellFrame);
	
		if (m_menuItem.hasSubmenu()) {
			var size:NSSize;
			var position:NSPoint;
	
			size = g_arrowImage.size();
			position.x = cellFrame.origin.x + cellFrame.size.width - size.width;
			position.y = Math.max(cellFrame.midY() - (size.height/2), 0);
	
			//! FIXME
			/*
			g_arrowImage.compositeToPointOperation
			(position ,NSCompositeSourceOver);*/
		}
		/* FIXME/TODO here - decide a consistent policy for images.
		 *
		 * The reason of the following code is that we draw the key
		 * equivalent, but not if we are a popup button and are displaying
		 * an image (the image is displayed in the title or selected entry
		 * in the popup, it's the small square on the right). In that case,
		 * the image will be drawn in the same position where the key
		 * equivalent would be, so we do not display the key equivalent,
		 * else they would be displayed one over the other one.
		 */
		else if (!m_menuView.menu().ownedByPopUp()) {		
			drawTextInFrame(m_menuItem.keyEquivalent(), cellFrame);
		} else if (m_imageToDisplay == null) {
			drawTextInFrame(m_menuItem.keyEquivalent(), cellFrame);
		}
	}
	
	
	public function drawSeparatorItemWithFrameInView(cellFrame:NSRect, controlView:NSView):Void {
		//! FIXME: This only has sense in MacOS or Windows interface styles.
	}
	
	public function drawStateImageWithFrameInView(cellFrame:NSRect, controlView:NSView):Void {
		var size:NSSize;
		var position:NSPoint;
		var imageToDisplay:NSImage;
	
		switch (m_menuItem.state()) {
				case NSOnState:
		imageToDisplay = m_menuItem.onStateImage();
		break;
	
				case NSMixedState:
		imageToDisplay = m_menuItem.mixedStateImage();
		break;
	
				case NSOffState:
				default:
		imageToDisplay = m_menuItem.offStateImage();
		break;
			}
	
		if (imageToDisplay == null) {
			return;
		}
		
		size = imageToDisplay.size();
		cellFrame = stateImageRectForBounds(cellFrame);
		position.x = Math.max(cellFrame.midX() - (size.width/2),0);
		position.y = Math.max(cellFrame.midY() - (size.height/2),0);
		
		//! FIXME
		/*
		imageToDisplay.compositeToPointOperation
		(position ,NSCompositeSourceOver);*/
	}
	
	public function drawTitleWithFrameInView(cellFrame:NSRect, controlView:NSView):Void {
		drawTextInFrame(m_menuItem.title(), titleRectForBounds(cellFrame));
	}
	
	public function drawWithFrameInView(cellFrame:NSRect, controlView:NSView):Void {
		// Save last view drawn to
		if (m_controlView != controlView) {
			m_controlView = controlView;
		}
		// Transparent buttons never draw
		if (m_bcellTransparent) {
			return;
		}
		// Do nothing if cell's frame rect is zero
		if (cellFrame.isEmptyRect()) {
			return;
		}
		trace("in");
		// Draw the border if needed
		drawBorderAndBackgroundWithFrameInView(cellFrame, controlView);
	
		drawInteriorWithFrameInView(cellFrame, controlView);
	}
	
	public function drawInteriorWithFrameInView(cellFrame:NSRect, controlView:NSView):Void {
		var mask:Number;
	
		// Transparent buttons never draw
		if (m_bcellTransparent) {
			return;
		}
		cellFrame = drawingRectForBounds(cellFrame);
	
		if (isHighlighted()) {
			mask = m_highlightsByMask;
	
			if (state() != null) {
		mask &= ~m_showAltStateMask;
			}
		} else if (state()) {
			mask = m_showAltStateMask;
		} else {
			mask = NSNoCellMask;
		}
		// pushed in buttons contents are displaced to the bottom right 1px
		if (isBordered() && (mask & NSPushInCellMask)) {
			cellFrame = cellFrame.offsetRect(1, -1);
		}
	
		/*
		 * Determine the background color and cache it in an ivar so that the
		 * low-level drawing methods don't need to do it again.
		 */
		if (mask & (NSChangeGrayCellMask | NSChangeBackgroundCellMask)) {
			m_backgroundColor = new NSColor(0x00FF00);
			//! NSColor.selectedMenuItemColor();
		}
		if (m_backgroundColor == null) {
			m_backgroundColor = new NSColor(0x00FF00);
			//!NSColor.controlBackgroundColor();
		}
		// Set cell's background color
		trace(m_bordered);
		ASDraw.solidRectWithRect(controlView.mcBounds(), cellFrame, m_backgroundColor.value);
	
		/*
		 * Determine the image and the title that will be
		 * displayed. If the NSContentsCellMask is set the
		 * image and title are swapped only if state is 1 or
		 * if highlighting is set (when a button is pushed it's
		 * content is changed to the face of reversed state).
		 * The results are saved in two ivars for use in other
		 * drawing methods.
		 */
		if (mask & NSContentsCellMask) {
			m_imageToDisplay = m_alternateImage;
			if (!m_imageToDisplay) {
				m_imageToDisplay = m_menuItem.image();
			}
			m_titleToDisplay = m_alternateTitle;
			if (m_titleToDisplay == null || m_titleToDisplay=="") {
				m_titleToDisplay = m_menuItem.title();
			}
		} else {
			m_imageToDisplay = m_menuItem.image();
			m_titleToDisplay = m_menuItem.title();
		}
	
		if (m_imageToDisplay) {
			m_imageWidth = m_imageToDisplay.size.width;
		}
	
		// Draw the state image
		if (m_stateImageWidth > 0) {
			drawStateImageWithFrameInView(cellFrame, controlView);
		}
		// Draw the image
		if (m_imageWidth > 0) {
			drawImageWithFrameInView(cellFrame,controlView);
		}
		// Draw the title
		if (m_titleWidth > 0) {
			drawTitleWithFrameInView(cellFrame, controlView);
		}
		// Draw the key equivalent
		if (m_keyEquivalentWidth > 0) {
			drawKeyEquivalentWithFrameInView(cellFrame, controlView);
		}
		m_backgroundColor = null;
	}
	
	//! TODO: NSCopying protocol
	
	/*
	
	public function drawWithFrameInView(rect:NSRect, v:NSView) {
		var mc:MovieClip = v.mcBounds();
		ASDraw.outlineCornerRectWithRect(mc, rect, 0, 0xFF0000);
	}*/
	
	//! should be in NSCell
	private function drawTextInFrame(aString:String, cellFrame:NSRect):Void {
		
	}
}
