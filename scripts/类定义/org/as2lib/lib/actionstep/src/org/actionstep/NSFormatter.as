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

import org.actionstep.NSAttributedString;
import org.actionstep.NSDictionary;
import org.actionstep.NSException;

/**
 * An abstract formatting class. Provides common operations to be implemented
 * by subclasses.
 * 
 * Notes for those intending to subclass NSFormatter:
 *	 Please examine the getObjectValueForStringErrorDescription method's 
 *	 comments, as it describes differences from the Cocoa implementation of
 *	 the method.
 *
 * @see org.actionstep.NSDateFormatter
 * @see org.actionstep.NSNumberFormatter
 * @author Scott Hyndman
 */
class org.actionstep.NSFormatter extends org.actionstep.NSObject
{	
	/**
	 * Creates a new instance of NSFormatter.
	 *
	 * Since this is an abstract class, the constructor is private (protected)
	 * so only subclasses can call it.
	 */
	private function NSFormatter()
	{
	}
	
	//******************************************************															 
	//*                    Properties
	//******************************************************
	
	/**
	 * @see org.actionstep.NSObject#description
	 */
	public function description():String 
	{
		return "NSFormatter()";
	}
	
	//******************************************************															 
	//*                 Public Methods
	//******************************************************
	
	/**
	 * The default (NSFormatter) implementation returns null.
	 *
	 * This method generates an attributed string based on a source object.
	 */
	public function attributedStringForObjectValueWithDefaultAttributes(
		anObject:Object, attributes:NSDictionary):NSAttributedString
	{
		return null;
	}
	
	
	//! editingStringForObjectValue(anObject:Object):String
	
	
	/**
	 * The default (NSFormatter) implementation raises an exception.
	 * Subclasses override this method to perform object to string conversion.
	 *
	 * Subclassing notes:
	 * The type of the value argument should be tested. If it is not an 
	 * instance of the expected class, null should be returned.
	 * Remember localization!
	 */
	public function stringForObjectValue(value:Object):String 
	{
		var e:NSException = NSException.exceptionWithNameReasonUserInfo(
			"NSAbstractMethodException",
			"This method is only implemented by subclasses of NSFormatter.",
			null);
		trace(e);
		throw e;
		
		return null;
	}
	
	
	//! isPartialStringValidNewEditingStringErrorDescription
	
	
	//! isPartialStringValid:proposedSelectedRange:originalString:originalSelectedRange:errorDescription:
	
	
	/**
	 * The default (NSFormatter) implementation raises an exception.
	 * Subclasses override this method to perform string to object conversion.
	 *
	 * This method will return an object formatted as follows:
	 * {success:Boolean, obj:Object, error:String}
	 *
	 * If the success property is true, the conversion succeeded and the obj
	 * property will contain the newly created object. If the success property
	 * is FALSE, the conversion failed and the error property will contain
	 * a descriptive error message.
	 *
	 * The implementation of this method differs from Cocoa's as ActionScript
	 * does not have pointers. Ordinarily a boolean is returned indicating
	 * success and the obj and error arguments are pointers.
	 */	 
	public function getObjectValueForStringErrorDescription(string:String)
		:Object
	{
		var e:NSException = NSException.exceptionWithNameReasonUserInfo(
			"NSAbstractMethodException",
			"This method is only implemented by subclasses of NSFormatter.",
			null);
		trace(e);
		throw e;
		
		return null;
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
}
