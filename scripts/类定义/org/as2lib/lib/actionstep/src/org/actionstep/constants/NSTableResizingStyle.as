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


/**
 * The following constants specify the autoresizing styles.
 *
 * @author Scott Hyndman
 */
class org.actionstep.constants.NSTableResizingStyle
{	    
	/**
	 * Disable table column autoresizing.
	 */
	public static var NSTableViewNoColumnAutoresizinge:NSTableResizingStyle 
		= new NSTableResizingStyle(0);
		
	/**
	 * Autoresize all columns by distributing space equally, simultaeously.
	 */
	public static var NSTableViewUniformColumnAutoresizingStyle:NSTableResizingStyle 
		= new NSTableResizingStyle(1);
		
	/**
	 * Autoresize each table column sequentially, from left to right. Proceed
	 * to the next column when the current column has reached its minimum or
	 * maximum size. 
	 */
	public static var NSTableViewSequentialColumnAutoresizingStyle:NSTableResizingStyle 
		= new NSTableResizingStyle(2);
		
	/**
	 * Autoresize each table column sequentially, from right to left. Proceed
	 * to the next column when the current column has reached its minimum or
	 * maximum size.
	 */
	public static var NSTableViewReverseSequentialColumnAutoresizingStyle:NSTableResizingStyle
	 	= new NSTableResizingStyle(3);
	 	
	/**
	 * Autoresize only the last table colum. When that table column can no
	 * longer be resized, stop autoresizing.
	 */
	public static var NSTableViewLastColumnOnlyAutoresizingStyle:NSTableResizingStyle 
		= new NSTableResizingStyle(4);
		
	/**
	 * Autoresize only the first table colum. When that table column can no
	 * longer be resized, stop autoresizing. 
	 */
	public static var NSTableViewFirstColumnOnlyAutoresizingStyle:NSTableResizingStyle
	 	= new NSTableResizingStyle(5);
	
	/**
	 * The value of the constant.
	 */
	public var value:Number;

	
	/**
	 * Creates a new instance of NSTableResizingStyle
	 */
	private function NSTableResizingStyle(value:Number)
	{		
		this.value = value;
	}
}
