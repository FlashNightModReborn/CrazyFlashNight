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

import org.actionstep.NSArray;

/**
 * Represents a method invocation. Used for passing around a method
 * invocation with arguments and stores the return value once the method
 * has been called.
 *
 * Create an instance using 
 * NSInvocation.invocationWithTargetSelectorArguments().
 *
 * Please note this class differs from its Cocoa counterpart, due to 
 * ActionScript's lack of reflection.
 *
 * @see org.actionstep.NSInvocation#invoke
 * @see org.actionstep.NSInvocation#invokeWithTarget
 * @see org.actionstep.NSInvocation#invocationWithTargetSelectorArguments
 *
 * @author Scott Hyndman
 */
class org.actionstep.NSInvocation extends org.actionstep.NSObject
{	
	private var m_target:Object;
	private var m_selector:String;
	private var m_arguments:NSArray;
	private var m_returnval:Object;
	
	/**
	 * Private constructor. Use NSInvocation.invocationWithTargetSelectorArguments().
	 *
	 * @see org.actionstep.NSInvocation#invocationWithTargetSelectorArguments()
	 */
	private function NSInvocation()
	{
		m_arguments = new NSArray();
	}
	
	//******************************************************															 
	//*                    Properties
	//******************************************************
	
	/**
	 * @see org.actionstep.NSObject#description
	 */
	public function description():String 
	{
		return "NSInvocation(target=" + target() + ",selector=" + selector() + 
			",arguments=" + m_arguments + ")";
	}
	
	
	/**
	 * Returns the invocation's selector, or null if one doesn't exist.
	 */
	public function selector():String
	{
		return m_selector == undefined ? null : m_selector;
	}
	
	
	/**
	 * Sets the invocation's selector. 
	 */
	public function setSelector(sel:String):Void
	{
		m_selector = sel;
	}
	
	
	/**
	 * Returns the invocation's target.
	 */
	public function target():Object
	{
		return m_target;
	}
	
	/**
	 * Sets the invocation's target.
	 */
	public function setTarget(target:Object):Void
	{
		m_target = target;
	}
	
	
	//******************************************************															 
	//*                 Public Methods
	//******************************************************
	
	/**
	 * Calls invokeWithTarget() using this invocation's target.
	 */
	public function invoke():Void
	{
		invokeWithTarget(m_target);
	}
	
	
	/**
	 * Calls anObject[m_selector].apply(anObject, arguments) and stores
	 * the return value.
	 *
	 * @see org.actionstep.NSInvocation#invoke()
	 * @see org.actionstep.NSInvocation#getReturnValue()
	 */
	public function invokeWithTarget(anObject:Object):Void
	{
		setReturnValue(
			anObject[m_selector].apply(anObject, m_arguments.internalList()));
	}
	
	
	//******************************************************															 
	//*                     Arguments
	//******************************************************
	
	/**
	 * Gets the argument at index idx if one exists. If not, an exception
	 * is thrown.
	 */
	public function getArgumentAtIndex(idx:Number):Object
	{
		return m_arguments.objectAtIndex(idx);
	}
	
	
	/**
	 * Sets the argument at index idx to anObject.
	 */
	public function setArgumentAtIndex(anObject:Object, idx:Number):Void
	{
		var len:Number = m_arguments.count();
		
		//
		// Return if bad input.
		//! Should we maybe throw an exception
		//
		if (idx < 0)
			return;
		
		if (idx == len) // Just add it.
		{
			m_arguments.addObject(anObject);
		}
		else if (idx > len) // Fill with nulls, then add it.
		{
			for (var i:Number = len; i < idx; i++)
			{
				m_arguments.addObject(null); // fill with nulls
			}
			
			m_arguments.addObject(anObject);
		}
		else // Replace it.
		{
			m_arguments.replaceObjectAtIndexWithObject(idx, anObject);
		}
	}
	
	//******************************************************															 
	//*                  Return Values
	//******************************************************

	/**
	 * Sets the return value of the method.
	 *
	 * This is usually called by invoke() or invokeWithTarget().
	 */
	public function setReturnValue(anObject:Object):Void
	{
		m_returnval = anObject;
	}
	
	
	/**
	 * Gets the return value of the method.
	 */
	public function getReturnValue():Object
	{
		return m_returnval;
	}
		
	//******************************************************															 
	//*              Public Static Methods
	//******************************************************	
	
	/**
	 * This is the counterpart to invocationWithMethodSignature in ActionStep.
	 * Since ActionScript doesn't have reflection, we aren't able to match
	 * method signitures at runtime.
	 */
	public static function invocationWithTargetSelectorArguments(target:Object,
		selector:String /* ,... */):NSInvocation
	{
		var args:Array;
		var invok:NSInvocation = new NSInvocation();
		
		invok.setTarget(target);
		invok.setSelector(selector);
		
		args = arguments.splice(2);
		
		for (var i:Number = 0; i < args.length; i++)
		{
			invok.setArgumentAtIndex(args[i], i);
		}
		
		return invok;
	}
}
