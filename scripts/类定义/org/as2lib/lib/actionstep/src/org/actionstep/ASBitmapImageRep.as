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

import flash.display.BitmapData;
import flash.geom.Rectangle;
import org.actionstep.NSImageRep;
//import org.actionstep.NSPoint;
import org.actionstep.NSRect;
import org.actionstep.NSView;

/**
 * Represents an image defined by a rectangle of a BitmapData instance.
 *
 * @author Scott Hyndman
 */
class org.actionstep.ASBitmapImageRep extends NSImageRep
{	
	private var m_image:BitmapData;
	
	/**
	 * Creates a new instance of ASBitmapImageRep. This image is composed
	 * of the area of source as defined by rect.
	 */
	public function ASBitmapImageRep(source:BitmapData, rect:NSRect)
	{
		m_image = new BitmapData(rect.size.width, rect.size.height);
		source.copyPixels(m_image, new Rectangle(0, 0, 
			rect.size.width, rect.size.height), rect.origin.toFlashPoint());
		m_size = rect.size;
	}
	
	//******************************************************															 
	//*                    Properties
	//******************************************************
	
	/**
	 * @see org.actionstep.NSObject#description
	 */
	public function description():String 
	{
		return "ASBitmapImageRep()";
	}
	 
	//******************************************************															 
	//*                 Public Methods
	//******************************************************
	
	/**
	 * Draws the image.
	 */
	public function draw():Void
	{		
		var clip:MovieClip;
		var depth:Number;
		
		depth = m_drawClip.getNextHighestDepth();
		
		if (m_drawClip.view != undefined)
		{
			depth = NSView(m_drawClip.view).getNextDepth();
		}
		
		clip = m_drawClip.createEmptyMovieClip("clip" + depth, depth);
		clip._x = m_drawPoint.x;
		clip._y = m_drawPoint.y;
		clip._width = m_size.width;
		clip._height = m_size.height;
		
		clip.attachBitmap(m_image, 0);
		
		super.addImageRepToDrawClip(clip);
    }
}
