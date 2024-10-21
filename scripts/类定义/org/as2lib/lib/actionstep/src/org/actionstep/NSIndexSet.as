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
import org.actionstep.NSDictionary;
import org.actionstep.NSException;
import org.actionstep.NSObject;
import org.actionstep.NSRange;

/**
 * An immutable collection of Numbers (should be unsigned integers). These 
 * Numbers represent a series of indexes. An index can only appear once. These
 * indexes are always sorted, so the order in which they are added does not 
 * matter.
 *
 * Internally, indexes are stored as a collection of ranges.
 *
 * @author Scott Hyndman
 */
class org.actionstep.NSIndexSet extends NSObject
{	
	//******************************************************															 
	//*                     Members
	//******************************************************
	
	private var m_ranges:NSArray;
	
	//******************************************************															 
	//*                   Construction
	//******************************************************
	
	/**
	 * Creates a new instance of NSIndexSet. Must be followed by a call to an
	 * initialization method.
	 */
	public function NSIndexSet()
	{
	}
	
	
	/**
	 * Initializes a new instance with no indexes.
	 */
	public function init():NSIndexSet
	{
		m_ranges = NSArray.array();
		return this;
	}
	
	
	/**
	 * Initializes a new instance with a single index.
	 */
	public function initWithIndex(idx:Number):NSIndexSet
	{
		return initWithIndexesInRange(new NSRange(idx, 1));
	}


	/**
	 * Initializes a new instance with indexes specified by range. 
	 *
	 * An exception is thrown if the range is invalid (negative location).
	 */
	public function initWithIndexesInRange(range:NSRange):NSIndexSet
	{
		if (range.location < 0) // bad range
		{
			var e:NSException = NSException.exceptionWithNameReasonUserInfo(
				"NSRangeException",
				"The range's location is invalid. (" + range.location + ")",
				NSDictionary.dictionaryWithObjectForKey(range, "range"));
			trace(e);
			throw e;
		}
		
		init();
		m_ranges.addObject(range.copyWithZone());
		return this;
	}
	
	
	/**
	 * Initializes a new instance with the indexes in indexSet.
	 */
	public function initWithIndexSet(indexSet:NSIndexSet):NSIndexSet
	{
		m_ranges = NSArray(indexSet.m_ranges.copyWithZone());
		return this;
	}
	
	//******************************************************															 
	//*                    Properties
	//******************************************************
	
	/**
	 * Returns the number of indexes in the set.
	 */
	public function count():Number
	{
		//! consider calculating this up front.
		
		var rng:NSRange;
		var rngs:Array = m_ranges.internalList();
		var len:Number = rngs.length;
		var cnt:Number = 0;
		
		for (var i:Number = 0; i < len; i++)
		{
			rng = NSRange(rngs[i]);
			cnt += rng.length;
		}
		
		return cnt;
	}
	
	
	/**
	 * @see org.actionstep.NSObject#description
	 */
	public function description():String 
	{
		return "NSIndexSet()";
	}
	
	
	/**
	 * Returns the first index in the set, or NSObject.NSNotFound if the set
	 * is empty.
	 */
	public function firstIndex():Number
	{
		if (m_ranges.count() == 0)
		{
			return NSObject.NSNotFound;
		}
		
		var rng:NSRange = NSRange(m_ranges.objectAtIndex(0));
		return rng.location;
	}
	
	
	/**
	 * Returns the last index in the set, or NSObject.NSNotFound if the set
	 * is empty.
	 */
	public function lastIndex():Number
	{
		if (m_ranges.count() == 0)
		{
			return NSObject.NSNotFound;
		}
		
		var rng:NSRange = NSRange(m_ranges.lastObject());
		return rng.location + rng.length - 1;
	}
		
	//******************************************************															 
	//*                 Public Methods
	//******************************************************
	
	/**
	 * Returns TRUE if the index set contains the index idx.
	 */
	public function containsIndex(idx:Number):Boolean
	{
		var low:Number;
		var high:Number;
		var rng:NSRange;
		var rngs:Array = m_ranges.internalList();
		var len:Number = rngs.length;
		
		for (var i:Number = 0; i < len; i++)
		{
			rng = NSRange(rngs[i]);
			low = rng.location;
			high = low + rng.length - 1;
			
			if (idx <= high && idx >= low)
			{
				return true;
			}
		}
		
		return false;
	}
	
	
	/**
	 * Returns TRUE if this index set contains all the indexes found in
	 * indexSet.
	 */
	public function containsIndexes(indexSet:NSIndexSet):Boolean
	{
		//! implement
		
		return false;
	}
	
	
	/**
	 * Returns TRUE if this index set contains all the indexes found in
	 * range.
	 */
	public function containsIndexesInRange(range:NSRange):Boolean
	{
		var low:Number;
		var high:Number;
		var rng:NSRange;
		var alow:Number = range.location;
		var ahigh:Number = alow + range.length - 1;
		var rngs:Array = m_ranges.internalList();
		var len:Number = rngs.length;
		
		for (var i:Number = 0; i < len; i++)
		{
			rng = NSRange(rngs[i]);
			low = rng.location;
			high = low + rng.length - 1;
			
			if (ahigh <= high && alow >= low)
			{
				return true;
			}
		}
		
		return false;
	}
	
	
	//! getIndexes:maxCount:inIndexRange:
	
	
	/**
	 * Returns the next closest index that is greater than idx or NSNotFound
	 * if value is the last index in the set.
	 */
	public function indexGreaterThanIndex(idx:Number):Number
	{
		//! implement
		
		return NSObject.NSNotFound;
	}
	
	
	/**
	 * Returns the next closest index that is greater than or equal to idx or
	 * NSNotFound if value is the last index in the set.
	 */
	public function indexGreaterThanOrEqualToIndex(idx:Number):Number
	{
		//! implement
		
		return NSObject.NSNotFound;
	}
	
	
	/**
	 * Returns the next closest index that is less than idx or NSNotFound
	 * if value is the first index in the set.
	 */
	public function indexLessThanIndex(idx:Number):Number
	{
		//! implement
		
		return NSObject.NSNotFound;
	}
	
	
	/**
	 * Returns the next closest index that is less than or equal to idx or
	 * NSNotFound if value is the first index in the set.
	 */
	public function indexLessThanOrEqualToIndex(idx:Number):Number
	{
		//! implement
		
		return NSObject.NSNotFound;
	}
	
	
	//! intersectsIndexesInRange
	
	/**
	 * @see org.actionstep.NSObject#isEqual
	 */
	public function isEqual(anObject:NSObject):Boolean
	{
		if (anObject instanceof NSIndexSet)
		{
			return isEqualToIndexSet(NSIndexSet(anObject));
		}

		return super.isEqual(anObject); // else
	}
	
	
	/**
	 * Returns TRUE if the indexes contained in indexSet are identical to the
	 * ones contained in this index set.
	 */
	public function isEqualToIndexSet(indexSet:NSIndexSet):Boolean
	{
		//! implement
		
		return false;
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
	//*              Static Creation Methods
	//******************************************************	

	/**
	 * Initializes and returns an empty index set.
	 */
	public static function indexSet():NSIndexSet
	{
		return (new NSIndexSet()).init();
	}
	

	/**
	 * Initializes and returns an index set containing a single index.
	 */
	public static function indexSetWithIndex(idx:Number):NSIndexSet
	{
		return (new NSIndexSet()).initWithIndex(idx);
	}
	
	
	/**
	 * Initializes and returns an index set containing the indexes found in
	 * range.
	 */
	public static function indexSetWithIndexesInRange(range:NSRange):NSIndexSet
	{
		return (new NSIndexSet()).initWithIndexesInRange(range);
	}	
	
}
