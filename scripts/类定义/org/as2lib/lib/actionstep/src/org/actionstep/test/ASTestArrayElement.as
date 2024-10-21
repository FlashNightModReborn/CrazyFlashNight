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

import org.actionstep.NSObject;
import org.actionstep.constants.NSComparisonResult;

/**
 *
 *
 * @author Scott Hyndman
 */
class org.actionstep.test.ASTestArrayElement extends NSObject
{	
	public var age:Number;
	public var iq:Number;
	
	public function ASTestArrayElement(age:Number, iq:Number)
	{
		this.age = age;
		
		if (iq != undefined)
			this.iq = iq;
	}
	
	//******************************************************															 
	//*                    Properties
	//******************************************************
	
	/**
	 * @see org.actionstep.NSObject#description
	 */
	public function description():String 
	{
		var ret:String = "ASTestArrayElement(age=" + age; 
		
		if (iq != undefined)
			ret += ", IQ=" + iq;
			
		ret += ")";
		
		return ret;
	}
	
	//******************************************************															 
	//*                 Public Methods
	//******************************************************
	
	public function compareAge(that:Object)
	{
		if (this.age < that.age)
			return NSComparisonResult.NSOrderedAscending;
		else if (this.age > that.age)
			return NSComparisonResult.NSOrderedDescending;
			
		return NSComparisonResult.NSOrderedSame;
	}
	
	public function compareProperty(that:Object)
	{		
		if (this < that)
			return NSComparisonResult.NSOrderedAscending;
		else if (this > that)
			return NSComparisonResult.NSOrderedDescending;
			
		return NSComparisonResult.NSOrderedSame;
	}
	
	//******************************************************															 
	//*                     Events
	//******************************************************
	//******************************************************															 
	//*                 Protected Methods
	//******************************************************
	//******************************************************															 
	//*                  Private Methods
	//******************************************************
	//******************************************************															 
	//*             Public Static Properties
	//******************************************************
	//******************************************************															 
	//*              Public Static Methods
	//******************************************************	
	//******************************************************															 
	//*               Static Constructor
	//******************************************************
	
	/**
	 * Runs when the application begins.
	 */
	private static function classConstruct():Boolean
	{
		if (classConstructed)
			return true;
				
		return true;
	}
	
	private static var classConstructed:Boolean = classConstruct();
}
