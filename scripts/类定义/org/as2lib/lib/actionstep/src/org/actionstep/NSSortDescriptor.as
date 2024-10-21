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
import org.actionstep.NSCopying;
//import org.actionstep.NSEnumerator;
import org.actionstep.NSObject;
import org.actionstep.constants.NSComparisonResult;

/**
 * This object describes how an array should be sorted.
 *
 * Instances of this object are created by specifying the property key to be compared,
 * whether the sort should be ascending or descending, and a selector that performs
 * the comparisons.
 *
 * @author Scott Hyndman
 */
class org.actionstep.NSSortDescriptor extends NSObject implements NSCopying
{	
	private var m_key:String;
	private var m_ascending:Boolean;
	private var m_selector:String;
	
	
	/**
	 * Creates a new instance of NSSortDescriptor.
	 */
	public function NSSortDescriptor()
	{
	}
	
	
	/** 
	 * Returns the initialized NSSortDescriptor using property key key, and the
	 * sort order of ascending. A default selector is used.
	 */
	public function initWithKeyAscending(key:String, ascending:Boolean)
		:NSSortDescriptor
	{
		m_key = key;
		m_ascending = ascending;
		m_selector = "compare"; // default
		
		return this;
	}
	
	
	/**
	 * Returns the initialized NSSortDescriptor using property key key, the
	 * sort order of ascending, a the selector selector used to perform the sort.
	 */
	public function initWithKeyAscendingSelector(key:String, ascending:Boolean, selector:String)
		:NSSortDescriptor
	{
		m_key = key;
		m_ascending = ascending;
		m_selector = selector;
		
		return this;
	}
	
	//******************************************************															 
	//*                   Properties					 
	//******************************************************
	
	/**
	 * Returns the direction of the sort. TRUE is ascending, FALSE is descending.
	 */
	public function ascending():Boolean
	{
		return m_ascending;
	}
	
	
	/**
	 * @see org.actionstep.NSObject#description
	 */
	public function description():String 
	{
		return "NSSortDescriptor(key=" + key() + ", ascending=" + ascending() + ")";
	}
	
	
	/**
	 * Returns the NSSortDescriptor's property key. This is the key into objects that will
	 * be sorted.
	 */
	public function key():String
	{
		return m_key;
	}
	
	
	/**
	 * Returns a copy of this NSSortDescriptor with its order reversed.
	 */
	public function reversedSortDescriptor():NSSortDescriptor
	{
		var copy:NSSortDescriptor = NSSortDescriptor(super.memberwiseClone());
		copy.m_ascending = !m_ascending;
		
		return copy;
	}
	
	
	/**
	 * Returns the selector the NSSortDescriptor will use to compare objects.
	 */
	public function selector():String
	{
		return m_selector;
	}
	
	//******************************************************															 
	//*                    Public Methods					   
	//******************************************************
	
	/**
	 * Compares object1 to object2 using the NSSortDescriptor's selector.
	 *
	 * Returns NSOrderedAscending if object1 is less than object2.
	 * Returns NSOrderedEqual if object1 is equal to object2.
	 * Returns NSOrderedDescending if object1 is greater than object2.
	 */
	public function compareObjectToObject(object1:Object, object2:Object)
		:NSComparisonResult
	{
		var res:NSComparisonResult;
		
		if (m_key == null)
			res = object1[m_selector](object2);
		else
			res = object1[m_selector].call(object1[m_key], object2[m_key]); //! this seems wrong to me
			
		//
		// Flip ascending to descending and vice-versa if sort order is descending.
		//
		if (!m_ascending)
		{
			if (res == NSComparisonResult.NSOrderedSame)
			{
				// do nothing
			}
			else if (res == NSComparisonResult.NSOrderedAscending)
				res = NSComparisonResult.NSOrderedDescending;
			else if (res == NSComparisonResult.NSOrderedDescending)
				res = NSComparisonResult.NSOrderedAscending;			
		}
		
		return res;
	}
	
	
	/**
	 * @see org.actionstep.NSCopying#copyWithZone()
	 */
	public function copyWithZone():NSObject
	{
		return NSSortDescriptor(super.memberwiseClone());
	}
	
	//******************************************************															 
	//*             Private Static Methods
	//******************************************************
	
	/**
	 * The default selector used if none is specified.
	 */
	private static function defaultSelector(object1:Object, object2:Object):NSComparisonResult
	{
		if (object1 < object2)
			return NSComparisonResult.NSOrderedAscending;
			
		if (object1 > object2)
			return NSComparisonResult.NSOrderedDescending;
			
		//
		// This should be last, because equality is slightly slower to calculate
		// than inequality I expect.
		//
		return NSComparisonResult.NSOrderedSame;
	}
	
	//******************************************************															 
	//*            Internal Static Methods
	//******************************************************

	public static function compareObjectToObjectWithDescriptors(object1:Object, 
		object2:Object, descriptors:NSArray):NSComparisonResult
	{
		var arr:Array = descriptors.internalList();
		var sd:NSSortDescriptor;
		var ret:NSComparisonResult;
		
		for (var i:Number = 0; i < arr.length; i++)
		{
			sd = NSSortDescriptor(arr[i]);
			ret = sd.compareObjectToObject(object1, object2);
			
			if (ret != NSComparisonResult.NSOrderedSame)
				break;
		}
		
		return ret;
	}
}
