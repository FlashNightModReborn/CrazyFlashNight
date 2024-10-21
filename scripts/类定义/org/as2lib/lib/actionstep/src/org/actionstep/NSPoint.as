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
 
import flash.geom.Point;

import org.actionstep.NSObject;
import org.actionstep.NSCopying;

/**
 * Represents a point in 2D space. Contains an x-coordinate and a y-coordinate.
 */
class org.actionstep.NSPoint extends NSObject implements NSCopying {
  
  /** A point with location (0, 0). */
	//please see NSRect for reasons on using getter func
  public static function get  ZeroPoint ():NSPoint {
		return new NSPoint(0,0);
	}
  
  /** The x-coordinate. */
  public var x:Number;
  
  /** The y-coordinate. */
  public var y:Number;
    
  /**
   * Creates a new instance of NSPoint with the specified x and y
   * coordinates.
   */
  public function NSPoint(x:Number, y:Number) {
    this.x = x;
    this.y = y;
  }

  /**
   * Creates a new point with the same properties as this one.
   */  
  public function clone():NSPoint {
    return new NSPoint(x, y);
  }
	
	public function copyWithZone():NSObject {
		return new NSPoint(x, y);
	}

  /**
   * Returns a flash.geom.Point containing the same x and y coordinates as 
   * this NSPoint.
   */
  public function toFlashPoint():Point {
    return new Point(x, y);
  }
  
  /**
   * @see org.actionstep.NSObject#description
   */
  public function description():String {
    return "NSPoint(x="+x+", y="+y+")";
  }
  
  /**
   * Returns true if this point's x and y coordinates are the same
   * as other's.
   */
  public function isEqual(other:NSPoint):Boolean {
    return x == other.x && y == other.y;
  }
  
  /**
   * Adds point to receiver and returns a new NSPoint.
   * This does not change the value of the receiver.
   */
  public function addPoint(point:NSPoint):NSPoint
  {
    return new NSPoint(x + point.x, y + point.y); 
  }

  /**
   * Subtracts point from receiver and returns a new NSPoint.
   * This does not change the value of the receiver.
   */ 
  public function subtractPoint(point:NSPoint):NSPoint
  {
    return new NSPoint(x - point.x, y - point.y);
  }
  
  /**
   * Translates point with supplied dx, dy and returns a new NSPoint.
   * This does not change the value of the receiver.
   */ 
  public function translate(dx:Number, dy:Number):NSPoint {
    return new NSPoint(x + dx, y + dy);
  }
	
	public function distanceToPoint(pt:NSPoint):Number {
		return Math.sqrt((x-pt.x)*(x-pt.x), (y-pt.y)*(y-pt.y));
	}
	
  /**
   * Creates and returns a newly initialized NSPoint containing the data of
   * the flash.geom.Point, aPoint.
   */
  public static function pointWithFlashPoint(aPoint:Point):NSPoint {
    return new NSPoint(aPoint.x, aPoint.y);
  }
}