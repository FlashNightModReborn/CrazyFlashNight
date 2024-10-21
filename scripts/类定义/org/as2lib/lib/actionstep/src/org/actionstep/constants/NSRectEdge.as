/*
 * Copyright (c) 2005, InfoEther, Inc.
 * All rights reserved.
 *
 * Copyright (c) 2005, Scott Hyndman
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
 * 3) The name InfoEther, Inc. and Scott Hyndman may not be used to endorse or promote products  
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
 * Used by NSRect.divideRect to determine how to slice the rectangle in 
 * question.
 * 
 * @see org.actionstep.NSRect
 * @author Scott Hyndman
 */
class org.actionstep.constants.NSRectEdge
{
	/**
	 * The inRect parameter is sliced vertically. The amount parameter will 
	 * specify the distance from the minimum x edge to place in slice.
	 */
	public static var NSMinXEdge:NSRectEdge = new NSRectEdge(0);
	
	/**
	 * The inRect parameter is sliced horizontally. The amount parameter will
	 * specify the distance from the minimum y edge to place in slice.
	 */
	public static var NSMinYEdge:NSRectEdge = new NSRectEdge(1);
	
	/**
	 * The inRect parameter is sliced vertically. The amount parameter will 
	 * specify the distance from the maximum x edge to place in slice.
	 */
	public static var NSMaxXEdge:NSRectEdge = new NSRectEdge(2);
	
	/**
	 * The inRect parameter is sliced horizontally. The amount parameter will
	 * specify the distance from the maximum y edge to place in slice.
	 */
	public static var NSMaxYEdge:NSRectEdge = new NSRectEdge(3);
	
	/**
	 * The unique (among the other constants of the same type) numeric value of 
	 * this constant.
	 */
	public var value:Number;
		
	/**
	 * Constructs a new instance of NSRectEdge.
	 * 
	 * This method should never be called.
	 */
	private function NSRectEdge(value:Number) 
	{
		this.value = value;
	}
}