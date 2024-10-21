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

import flash.geom.Rectangle;

import org.actionstep.NSCopying; 
import org.actionstep.NSObject;
import org.actionstep.NSPoint;
import org.actionstep.NSSize;
import org.actionstep.constants.NSRectEdge;


class org.actionstep.NSRect extends NSObject implements NSCopying {
	
	public var size:NSSize;
	public var origin:NSPoint;
	
	public function NSRect(x:Number, y:Number, width:Number, height:Number) {
		origin = new NSPoint(x, y);
		size = new NSSize(width, height);
	}
	
	/**
	 * Allows for use of NSRects as refs.
	 * eg. 
	 * function foo(ref:NSRect) {
	 *   //do smth
	 *   ref.reset(...);
	 * }
	 */
	public function reset(x:Number, y:Number, width:Number, height:Number) {
		origin.x = x;
		origin.y = y;
		size.width = width;
		size.height = height;
	}
	
	public function clone():NSRect {
	  return NSRect.withOriginSize(origin, size);
	}
	
	public function copyWithZone():NSObject {
		return NSRect.withOriginSize(origin, size);
	}
	
	public function description():String {
		return "NSRect(origin="+origin.description()+", size="+size.description()+")";
	}
	
	/**
	 * Returns a flash.geom.Rectangle containing the same coordinates and size
	 * as this rectangle.
	 */
	public function toFlashRect():Rectangle {
		return new Rectangle(origin.x, origin.y, size.width, size.height);
	}
	
	public function isEqual(other:NSRect):Boolean {
		return origin.x == other.origin.x &&
					 origin.y == other.origin.y &&
					 size.width == other.size.width &&
					 size.height == other.size.height;
	}
	
	public function midX():Number {
		return origin.x + size.width/2;
	}

	public function midY():Number {
		return origin.y + size.height/2;
	}
	
	public function minX():Number {
		return origin.x;
	}
	
	public function minY():Number {
		return origin.y;
	}
	
	public function maxX():Number {
		return origin.x + size.width;
	}
	
	public function maxY():Number {
		return origin.y + size.height;
	}
	
	public function width():Number {
		return size.width;
	}
	
	public function height():Number {
		return size.height;
	}

	public function insetRect(dx:Number, dy:Number):NSRect {
		return new NSRect(origin.x + dx, origin.y + dy, size.width - 2*dx, size.height - 2*dy);
	}
	
	public function offsetRect(dx:Number, dy:Number):NSRect {
		return new NSRect(origin.x + dx, origin.y + dy, size.width, size.height);
	}

	public function isEmptyRect():Boolean {
		return (size.width == 0) && (size.height == 0);
	}
	
	public function intersectionRect(rect:NSRect):NSRect {
		var result:NSRect = new NSRect(0,0,0,0);
		result.origin.x = Math.max(minX(), rect.minX());
		result.origin.y = Math.max(minY(), rect.minY());
		result.size.width = Math.min(maxX(), rect.maxX()) - result.minX();
		result.size.height = Math.min(maxY(), rect.maxY()) - result.minY();
		return (result.isEmptyRect() ? ZeroRect : result);
	}

	public function pointInRect(point:NSPoint):Boolean {
		//! x>=minX, y<=maxY
		if ( (point.x > origin.x && point.x < (origin.x+size.width)) &&
				 (point.y > origin.y && point.y < (origin.y+size.height))) {
			return true;
		} else {
			return false;
		}
	}
	
	public function containsRect(rect:NSRect):Boolean {
		return minX()<rect.minX() &&
					 minY()<rect.minY() &&
					 maxX()>rect.maxX() &&
					 maxY()>rect.maxY();
	}
	
	public function intersectsRect(rect:NSRect):Boolean {
		/* Note that intersecting at a line or a point doesn't count */
		return !(maxX() <= rect.minX()
		|| rect.maxX() <= minX()
		|| maxY() <= rect.minY()
		|| rect.maxY() <= minY());
	}

	//******************************************************															 
	//*                   Static Methods
	//******************************************************
	
	/**
	 * Divides a rectangle into two new rectangles. The slice and remainder
	 * parameters should be newly initialized NSRects.
	 */
	public static function divideRect(inRect:NSRect, slice:NSRect, 
		remainder:NSRect, amount:Number, edge:NSRectEdge):Void
	{		
		var h:Number = inRect.size.height;
		var w:Number = inRect.size.width;
		var x:Number = inRect.origin.x;
		var y:Number = inRect.origin.y;
		
		switch (edge)
		{
			case NSRectEdge.NSMinXEdge: // vertical slice from min x (left)
				slice.size.height = remainder.size.height = h;
				slice.size.width = amount;
				remainder.size.width = w - amount;
				slice.origin.y = remainder.origin.y = y;
				slice.origin.x = x;
				remainder.origin.x = x + amount;
				break;
				
			case NSRectEdge.NSMaxXEdge: // vertical slice from max x (right)
				slice.size.height = remainder.size.height = h;
				remainder.size.width = amount;
				slice.size.width = w - amount;
				slice.origin.y = remainder.origin.y = y;
				remainder.origin.x = x;
				slice.origin.x = x + w - amount;
				break;
				
			case NSRectEdge.NSMinYEdge: // horizontal slice from min y (top)
				slice.size.width = remainder.size.width = w;
				slice.size.height = amount;
				remainder.size.height = h - amount;
				slice.origin.x = remainder.origin.x = x;
				slice.origin.y = y;
				remainder.origin.y = y + amount;
				break;
				
			case NSRectEdge.NSMaxYEdge: // vertical slice from max y (bottom)
				slice.size.width = remainder.size.width = w;
				remainder.size.height = amount;
				slice.size.height = h - amount;
				slice.origin.x = remainder.origin.x = x;
				remainder.origin.y = y;
				slice.origin.y = y + h - amount;
				break;
		}
	}
	
	/**
	 * Prevents reference-related errors, as in the static var implementation.
	 */
	public static function get ZeroRect():NSRect {
		return new NSRect(0,0,0,0);
	}
	
	/**
	 * Returns a newly initialized NSRect containing an origin and a size.
	 */
	public static function withOriginSize(origin:NSPoint, size:NSSize):NSRect {
		return new NSRect(origin.x, origin.y, size.width, size.height);
	}
	
	/**
	 * Returns a new initialized NSRect containing the origin and size of
	 * the provided flash.geom.Rectangle.
	 */
	public static function rectWithFlashRect(rect:Rectangle):NSRect {
		return new NSRect(rect.x, rect.y, rect.width, rect.height);
	}
}