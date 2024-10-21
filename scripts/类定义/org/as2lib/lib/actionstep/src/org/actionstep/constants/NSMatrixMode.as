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


/**
 * These constants determine how NSCells behave when the NSMatrix is tracking 
 * the mouse.
 *
 * @author Scott Hyndman
 */
class org.actionstep.constants.NSMatrixMode 
{	
	/**
	 * The NSCells are asked to track the mouse with 
	 * trackMouse:inRect:ofView:untilMouseUp: whenever the cursor is inside 
	 * their bounds. No highlighting is performed.
	 */
	public static var NSTrackModeMatrix:NSMatrixMode 		= new NSMatrixMode(0);
	
	/**
	 * An NSCell is highlighted before it’s asked to track the mouse, 
	 * then unhighlighted when it’s done tracking.
	 */
	public static var NSHighlightModeMatrix:NSMatrixMode 	= new NSMatrixMode(1);
	
	/** 
	 * Selects no more than one NSCell at a time. Any time an NSCell is 
	 * selected, the previously selected NSCell is unselected.
	 */
	public static var NSRadioModeMatrix:NSMatrixMode 		= new NSMatrixMode(2);
	
	/**
	 * NSCells are highlighted, but don’t track the mouse.
	 */
	public static var NSListModeMatrix:NSMatrixMode 		= new NSMatrixMode(3);
	
	public var value:Number;
	
	private function NSMatrixMode(value:Number)
	{
		this.value = value;
	}
}
