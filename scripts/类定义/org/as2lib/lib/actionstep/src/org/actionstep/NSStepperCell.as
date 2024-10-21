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
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

//01 June 2005 -- simple
//02 June 2005 -- drawing

import org.actionstep.ASDraw;

import org.actionstep.NSActionCell;
import org.actionstep.NSRect;
import org.actionstep.NSView;
import org.actionstep.NSButtonCell;
import org.actionstep.NSCell;
import org.actionstep.NSImage;
import org.actionstep.NSPoint;
import org.actionstep.NSEvent;
import org.actionstep.NSStepper;import org.actionstep.NSException;import org.actionstep.NSDictionary;

import org.actionstep.constants.NSBezelStyle;
import org.actionstep.constants.NSCellImagePosition;
import org.actionstep.constants.NSTextAlignment;

class org.actionstep.NSStepperCell extends NSActionCell {

	private var m_maxValue:Number;
	private var m_minValue:Number;
	private var m_increment:Number;
	private var m_autorepeat:Boolean;
	private var m_valueWraps:Boolean;
	private var m_mc:MovieClip;
	private var m_cell:NSCell;
	private var m_rect:NSRect;
	private var m_value:Number;
	private var m_textField:TextField;
	private var m_periodicDelay:Number;
	private var m_periodicInterval:Number;
	private var $m_trackingCallback:Object;
	private var $m_trackingCallbackSelector:String;

	private static var g_upCell:NSButtonCell,
		g_downCell:NSButtonCell;

	var highlightUp:Boolean;

	public function NSStepperCell() {
		m_textField = null;
		m_autorepeat = true;
		m_valueWraps = true;
		m_maxValue = 59;
		m_minValue = 0;
		setIntValue(0);
		m_increment = 1;
		highlightUp = false;

		m_trackingCallback = this;
		m_trackingCallbackSelector = "trackBtn";

		drawParts();
	}

	public function init():NSStepperCell {
		super.init();
		setAlignment(NSTextAlignment.NSRightTextAlignment);
		setContinuous(true);
		sendActionOn(NSEvent.NSLeftMouseDownMask | NSEvent.NSLeftMouseUpMask | NSEvent.NSPeriodicMask);
		setPeriodicDelayInterval(0.5, 0.1);
		//setBordered(true);
		setBezelStyle(NSBezelStyle.NSShadowlessSquareBezelStyle);
		setBezeled(true);
		setHighlighted(false);
		//setBezeled(true);
		return this;
	}

	public function setTrackingCallbackSelector(callback:Object, selector:String) {
		$m_trackingCallback = callback;
		$m_trackingCallbackSelector = selector;
	}

	public function setDoubleValue(n:Number):Void {
		if(n<m_minValue || n>m_maxValue) {
			var e:NSException = NSException.exceptionWithNameReasonUserInfo
			(NSException.NSInvalidArgument, "value out of range",
			(new NSDictionary()).initWithObjectsAndKeys(n, "value"));
			trace(e);
			e.raise();
		}
		m_value = n;
		m_textField.text = n.toString();
	}

	public function doubleValue():Number {
		return m_value;
	}

	public function setIntValue(n:Number):Void {
		setDoubleValue(n);
	}

	public function intValue():Number {
		return m_value;
	}

	public function maxValue():Number {
		return m_maxValue;
	}

	public function setMaxValue (maxValue:Number):Void {
		m_maxValue = maxValue;
	}

	public function minValue():Number {
		return m_minValue;
	}

	public function setMinValue(minValue:Number):Void {
	  if (m_value < minValue) {
	    m_value = minValue;
  		m_textField.text = m_value.toString();
	  }
		m_minValue = minValue;
	}

	public function increment ():Number {
		return m_increment;
	}

	public function setIncrement(increment:Number):Void	{
		m_increment = increment;
	}

	public function autorepeat():Boolean {
		return m_autorepeat;
	}

	public function setAutorepeat(autorepeat:Boolean):Void {
		m_autorepeat = autorepeat;
	}

	public function valueWraps():Boolean	{
		return m_valueWraps;
	}

	public function setValueWraps(valueWraps:Boolean):Void {
		m_valueWraps = valueWraps;
	}

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

	/**
	 * Assume that both up/down have same props.
	 */

	public function setBordered(f:Boolean) {
		g_upCell.setBordered(f);
		g_downCell.setBordered(f);
	}

	public function isBordered():Boolean {
		return g_upCell.isBordered();
	}

	public function setBezeled(f:Boolean) {
		g_upCell.setBezeled(f);
		g_downCell.setBezeled(f);
	}

	public function isBezeled():Boolean {
		return g_upCell.isBezeled();
	}

	public function setBezelStyle(f:NSBezelStyle) {
		g_upCell.setBezelStyle(f);
		g_downCell.setBezelStyle(f);
	}

	public function bezelStyle():NSBezelStyle {
		return g_upCell.bezelStyle();
	}

	public function drawParts():Void {
		if (g_upCell != null) {
			return;
		}
		g_upCell = new NSButtonCell();
		g_upCell.setHighlightsBy(NSCell.NSChangeBackgroundCellMask | NSCell.NSContentsCellMask);
		g_upCell.setImage(NSImage.imageNamed("NSScrollerUpArrow"));
		g_upCell.setAlternateImage(NSImage.imageNamed("NSHightlightedScrollerUpArrow"));
		g_upCell.setImagePosition(NSCellImagePosition.NSImageOnly);
		g_upCell.setTrackingCallbackSelector(this, "trackButton");

		g_downCell = new NSButtonCell();
		g_downCell.setHighlightsBy(NSCell.NSChangeBackgroundCellMask | NSCell.NSContentsCellMask);
		g_downCell.setImage(NSImage.imageNamed("NSScrollerDownArrow"));
		g_downCell.setAlternateImage(NSImage.imageNamed("NSHightlightedScrollerDownArrow"));
		g_downCell.setImagePosition(NSCellImagePosition.NSImageOnly);
		g_downCell.setTrackingCallbackSelector(this, "trackButton");
	}

	public function drawInteriorWithFrameInView(cellFrame:NSRect, inView:NSView):Void {
		var upRect:NSRect = upButtonRectWithFrame(cellFrame);
		var downRect:NSRect = downButtonRectWithFrame(cellFrame);
		var txtRect:NSRect = textRectWithFrame(cellFrame);
		var m_bezelStyle:NSBezelStyle = bezelStyle();
		var m_bezeled:Boolean = isBezeled();
		var m_bordered:Boolean = isBordered();
		var m_textFormat:TextFormat;

		var x:Number = cellFrame.origin.x;
		var y:Number = cellFrame.origin.y;
		var width:Number = cellFrame.size.width;
		var height:Number = cellFrame.size.height;
		var tf:TextField;

		if (m_textField == null || m_textField._parent == undefined) {
			m_textField = inView.createBoundsTextField();
			tf = m_textField;
			m_textFormat = m_font.textFormatWithAlignment(m_alignment);
			//tf.selectable = false;

			tf._width = txtRect.size.width;
			tf._height = txtRect.size.height;
			tf._x = txtRect.origin.x;
			tf._y = txtRect.origin.y;

			tf.background = true;
			tf.border = true;
			tf.setNewTextFormat(m_textFormat);
		}

		if(!g_upCell.isHighlighted() && !g_downCell.isHighlighted()) {
			//m_rect = null;
			//m_cell = null;
		}

		//don't bother about border/bezel
		ASDraw.drawRect(inView.mcBounds(), 0.25, 0xFF0000, x, y, width, height);
		setDoubleValue(doubleValue());

		g_upCell.drawWithFrameInView(upRect, inView);
		g_downCell.drawWithFrameInView(downRect, inView);
	}

	public function highlightUpButtonWithFrameInView (hlt:Boolean, upButton:Boolean, frame:NSRect, controlView:NSView):Void {
		var upRect:NSRect = upButtonRectWithFrame(frame);
		var downRect:NSRect = downButtonRectWithFrame(frame);

		m_rect = (upButton) ? upRect : downRect;
		m_cell = (upButton) ? g_upCell : g_downCell;

		highlightUp = upButton;

		NSStepper(m_controlView).$incdec((highlightUp ? 1 : -1));
	}

	public function setHighlighted (sel:Boolean) {
		super.setHighlighted(sel);
		if(m_highlighted) {
			g_upCell.setHighlighted(highlightUp);
			g_downCell.setHighlighted(!highlightUp);
		} else {
			g_upCell.setHighlighted(false);
			g_downCell.setHighlighted(false);
		}
		//drawWithFrameInView(m_controlView.bounds(), m_controlView);
	}

	public function upButtonRectWithFrame(f:NSRect):NSRect {
		return new NSRect(
		f.maxX() - 16, f.minY() + (f.size.height / 2) - 10,
		15, 10);
	}

	public function downButtonRectWithFrame(f:NSRect):NSRect {
		return new NSRect(
		f.maxX() - 16, f.minY() + (f.size.height / 2),
		15, 10);
	}

	public function textRectWithFrame (f:NSRect):NSRect {
		return new NSRect(
		f.minX()+2, f.minY() + (f.size.height - 20)/2,
		f.maxX() - 23, 20);
	}

	public function continueTrackingAtInView(lastPoint:NSPoint, currentPoint:NSPoint, controlView:NSView):Boolean {
		if(m_rect.pointInRect(currentPoint)) {
			return true;
		} else {
			return false;
		}
	}

	public function stopTrackingAtInViewMouseIsUp(lastPoint:NSPoint, stopPoint:NSPoint, controlView:NSView, mouseIsUp:Boolean) {
		if(!mouseIsUp) {
			//trackBtn(false);
			//NSControl takes care of highlighting
			//$m_trackingCallback[$m_trackingCallbackSelector].call($m_trackingCallback, true);
			setHighlighted(false);
		}
	}

	/**
	 * param is actually isMouseUp
	 */
	public function trackBtn(mouse:Boolean, p:Boolean) {
		if(mouse && !isHighlighted())	{
			setHighlighted(false);
		} else if(p) {
			highlightUpButtonWithFrameInView (highlightUp, highlightUp, m_controlView.bounds(), m_controlView);
		}
		$m_trackingCallback[$m_trackingCallbackSelector].call($m_trackingCallback, mouse);
	}
}