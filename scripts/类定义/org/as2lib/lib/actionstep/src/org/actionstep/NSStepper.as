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
 
import org.actionstep.NSControl;
import org.actionstep.NSStepperCell;
import org.actionstep.NSEvent;
import org.actionstep.NSPoint;
import org.actionstep.NSRect;

class org.actionstep.NSStepper extends NSControl {
	private var m_enabled:Boolean,
		m_rect:NSRect,
		m_down:Boolean;
	
	private static var g_cellClass:Function = org.actionstep.NSStepperCell;
	
	public static function cellClass():Function {
		return g_cellClass;
	}
	
	public static function setCellClass(cellClass:Function) {
		if (cellClass == null) {
			g_cellClass = org.actionstep.NSStepperCell;
		} else {
			g_cellClass = cellClass;
		}
	}
	
	public function init():NSStepper {
		return initWithFrame(NSRect.ZeroRect);
	}
	
	public function initWithFrame (f:NSRect):NSStepper {
		super.initWithFrame(f);
		setEnabled(true);
		m_cell.setControlView(this);
		return this;
	}
	
	public function acceptsFirstMouse(theEvent:NSEvent):Boolean {
		return true;
	}
	
	public function becomeFirstResponder():Boolean {
		m_cell.setShowsFirstResponder(true);
		setNeedsDisplay(true);
	
		return true;
	}
	
	public function resignFirstResponder():Boolean {
		m_cell.setShowsFirstResponder(false);
		setNeedsDisplay(true);
	
		return true;
	}
	
	public function keyDown(theEvent:NSEvent):Void {
	}
	
	public function setEnabled(value:Boolean) {
		m_enabled = value;
		setNeedsDisplay(true);
	}

	public function isEnabled():Boolean {
		return m_enabled;
	}
	
	public function maxValue():Number {
		return NSStepperCell(m_cell).maxValue();
	}
	
	public function setMaxValue(maxValue:Number):Void {
		NSStepperCell(m_cell).setMaxValue(maxValue);
	}
	
	public function minValue():Number {
		return NSStepperCell(m_cell).minValue();
	}
	
	public function setMinValue(minValue:Number):Void {
		NSStepperCell(m_cell).setMinValue(minValue);
	}
	
	public function setIncrement(increment:Number):Void {
		NSStepperCell(m_cell).setIncrement(increment);
	}
	
	public function increment():Number {
		return NSStepperCell(m_cell).increment();
	}
	
	public function autorepeat():Boolean {
		return NSStepperCell(m_cell).autorepeat();
	}
	
	public function setAutorepeat(autorepeat:Boolean):Void {
		NSStepperCell(m_cell).setAutorepeat(autorepeat);
	}
	
	public function valueWraps():Boolean {
		return NSStepperCell(m_cell).valueWraps();
	}
	
	public function setValueWraps(valueWraps:Boolean):Void {
		NSStepperCell(m_cell).setValueWraps(valueWraps);
	}
	
	public function drawRect(rect:NSRect) {
		m_mcBounds.clear();
		m_cell.drawWithFrameInView(rect, this);
	}
	
	public function mouseDown(event:NSEvent):Void {
		var point:NSPoint = event.mouseLocation;
		var rect:NSRect;
		var isDirectionUp:Boolean;
		var autorepeat:Boolean = NSStepperCell(m_cell).autorepeat();
		
		if(m_cell.isEnabled() == false)
			return;
		
		//chk out here
		if(event.type != NSEvent.NSLeftMouseDown)
			return;
		
		var upRect:NSRect = NSStepperCell(m_cell).upButtonRectWithFrame(m_bounds);
		var downRect:NSRect = NSStepperCell(m_cell).downButtonRectWithFrame(m_bounds);
		var txtRect:NSRect = NSStepperCell(m_cell).textRectWithFrame(m_bounds);
		point = convertPointFromView(point, null);
		
		if (upRect.pointInRect(point)) {
			isDirectionUp = true;
			m_rect = upRect;
		} else if (downRect.pointInRect(point)) {
			isDirectionUp = false;
			m_rect = downRect;
		} else {
			return;
		}
		
		//cell will do the inc/dec thing
		NSStepperCell(m_cell).highlightUpButtonWithFrameInView(true, isDirectionUp, m_bounds, this);
		
		if(NSStepperCell(m_cell).autorepeat()) {
			super.mouseDown(event);
		}
		
		setNeedsDisplay(true);
	}
	
	//not needed because cell will use pointInRect on up/down cell
	private function cellTrackingRect():NSRect {
		return m_rect;
	}
	
	/**
	 * Accepts either +1 or -1, replaces _inc/decrements functions.
	 */
	public function $incdec (dir:Number) {
		var newValue:Number, 
			maxValue:Number = NSStepperCell(m_cell).maxValue(),
			minValue:Number = NSStepperCell(m_cell).minValue(),
			increment:Number = NSStepperCell(m_cell).increment();
		
		newValue = m_cell.doubleValue() + (dir * increment);
		if (NSStepperCell(m_cell).valueWraps()) {
			if (newValue > maxValue)	m_cell.setDoubleValue(newValue - maxValue + minValue - 1);
			else if (newValue < minValue)	m_cell.setDoubleValue(newValue + maxValue - minValue + 1);
			else m_cell.setDoubleValue(newValue);
		} else {
			if (newValue > maxValue)	m_cell.setDoubleValue(maxValue);
			else if (newValue < minValue)	m_cell.setDoubleValue(minValue);
			else	m_cell.setDoubleValue(newValue);
		}
		//don't send target, cell will do it
	}
	
	public function description ():String {
		return "NSStepper(doubleValue="+doubleValue()+")";
	}
}