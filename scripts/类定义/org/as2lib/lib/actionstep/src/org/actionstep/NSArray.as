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

import org.actionstep.ASUtils;
 
import org.actionstep.NSEnumerator;
import org.actionstep.NSException;
import org.actionstep.NSObject;
import org.actionstep.NSRange;
import org.actionstep.NSSortDescriptor;

import org.actionstep.constants.NSComparisonResult;

/**
 * Represents an array of objects.
 *
 * This class is a combination of both NSArray and NSMutableArray classes.
 *
 * @author Scott Hyndman
 */
class org.actionstep.NSArray extends NSObject
{	
	/** The internal list */
	private var m_list:Array;
	
	
	/**
	 * Creates a new instance of NSArray.
	 */
	public function NSArray()
	{
		m_list = new Array();
	}
	
	//******************************************************															 
	//*                    Properties
	//******************************************************
	
	/**
	 * Returns the internal array. For super quick operations only.
	 */
	public function internalList():Array
	{
		return m_list;
	}
	
	
	/**
	 * Returns the number of objects currently in the array.
	 */
	public function count():Number
	{
		return m_list.length;
	}


	/**
	 * @see org.actionstep.NSObject#description
	 */
	public function description():String 
	{
    	var ret:String = "NSArray(";
    	var len:Number = m_list.length;
    	
    	//
    	// Append the descriptions of all objects save the last.
    	//
    	for (var i:Number = 0; i < len - 1; i++)
    		ret += m_list[i].toString() + ",";
    		
    	if (len > 0)
    		ret += m_list[len - 1].toString(); // no comma
    	
    	return ret + ")";
	}
		
	
	/**
	 * Returns the last object in the array, or null if the array is
	 * empty.
	 */
	public function lastObject():Object
	{
		return m_list.length == 0 ? null : m_list[m_list.length - 1];
	}
	
	
	/**
	 * Returns an enumerator object that lets you access each object 
	 * in the receiver, in order, starting with the element at index 0.
	 *
	 * @return The enumerator.
	 */
	public function objectEnumerator():NSEnumerator
	{
		return new NSEnumerator(m_list, false);
	}
	
	
	/**
	 * Returns an enumerator object that lets you access each object in the 
	 * receiver, in order, from the element at the highest index down to the
	 * element at index 0. Your code shouldn’t modify the array during 
	 * enumeration.
	 *
	 * @return The enumerator.
	 */
	public function reverseObjectEnumerator():NSEnumerator
	{
		return new NSEnumerator(m_list, true);
	}
	
	  
	//******************************************************															 
	//*                 Public Methods
	//******************************************************
	
	/**
	 * Adds an anObject to the end of the collection.
	 *
	 * This operation should not be performed while the collection is being
	 * enumerated.
	 */
	public function addObject(anObject:Object):Void
	{
		insertObjectAtIndex(anObject, m_list.length);
	}

	
	/**
	 * Clears the collection.
	 *
	 * This operation should not be performed while the collection is being
	 * enumerated.
	 */	
	public function clear():Void
	{
		removeAllObjects();
	}
	
	
	/**
	 * Returns true if anObject is present in the array. This method determines
	 * whether an object is present in the array by sending an isEqual: 
	 * message to each of the array’s objects (and passing anObject as 
	 * the parameter to each isEqual: message).
	 *
	 * @param anObject The object to search for.
	 * @returns True if found, false otherwise.
	 */
	public function containsObject(anObject:Object):Boolean
	{
		return indexOfObject(anObject) != NSObject.NSNotFound;
	}
	
	
	/**
	 * Returns the first object contained in the receiver that’s equal to an 
	 * object in otherArray. If no such object is found, this method returns 
	 * null. This method uses isEqual to check for object equality.
	 */
	public function firstObjectCommonWithArray(otherArray:NSArray):Object
	{
		var idx:Number;
		var len:Number = otherArray.m_list.length;
		
		//
		// Cycle through passed array, searching for each object in turn.
		//
		for (var i:Number = 0; i < len; i++)
		{
			if ((idx = indexOfObject(otherArray.m_list[i])) != NSObject.NSNotFound)
				return m_list[idx];
		}
		
		return null; // not found
	}
	
	
	/**
	 * Searches the receiver for anObject and returns the lowest index whose 
	 * corresponding array value is equal to anObject. Objects are considered 
	 * equal if isEqual: returns YES. If none of the objects in the receiver 
	 * is equal to anObject, indexOfObject: returns NSNotFound.
	 */
	public function indexOfObject(anObject:Object):Number
	{
		return indexOfObjectInRange(anObject, new NSRange(0, m_list.length - 1));
	}

	
	/**
	 * Searches the specified range within the receiver for anObject and returns 
	 * the lowest index whose corresponding array value is equal to anObject. 
	 * Objects are considered equal if isEqual: returns YES. If none of the 
	 * objects in the specified range is equal to anObject, returns NSNotFound.
	 *
	 * @param anObject The object to search for
	 * @param range The range to search
	 * @returns The index of the object if found, NSNotFound otherwise.
	 */
	public function indexOfObjectInRange(anObject:Object, range:NSRange):Number
	{
		var startIdx:Number = range.location;
		var endIdx:Number = range.location + range.length;
		
		for (var i:Number = startIdx; i <= endIdx; i++)
		{
			if (m_list[i].isEqual(anObject))
				return i;
		}
		
		return NSObject.NSNotFound;
	}


	/**
	 * Searches the receiver for anObject and returns the index of the first
	 * equal object. Objects are considered equal when comparer returns TRUE.
	 *
	 * The comparer function must return TRUE if equal, FALSE if inequal, and
	 * take 2 objects as arguments (the objects to compare).
	 */
	public function indexOfObjectWithCompareFunction(anObject:Object, 
		comparer:Function):Number
	{
		return indexOfObjectWithCompareFunctionInRange(anObject, comparer, 
			new NSRange(0, m_list.length - 1));
	}
	
	
	/**
	 * Searches the specified range for anObject and returns the index of the first
	 * equal object. Objects are considered equal when comparer returns TRUE.
	 *
	 * The comparer function must return TRUE if equal, FALSE if inequal, and
	 * take 2 objects as arguments (the objects to compare).
	 */
	public function indexOfObjectWithCompareFunctionInRange(anObject:Object,
		comparer:Function, range:NSRange):Number
	{
		var startIdx:Number = range.location;
		var endIdx:Number = range.location + range.length;
		
		for (var i:Number = startIdx; i <= endIdx; i++)
		{
			if (comparer(m_list[i], anObject))
				return i;
		}
		
		return NSObject.NSNotFound;
	}

	/**
	 * Searches the receiver for anObject (testing for equality by comparing 
	 * object addresses) and returns the lowest index whose corresponding 
	 * array value is identical to anObject. If none of the objects in the 
	 * receiver is identical to anObject, indexOfObjectIdenticalTo: returns 
	 * NSNotFound.
	 */
	public function indexOfObjectIdenticalTo(anObject:Object):Number
	{
		return indexOfObjectIdenticalToInRange(anObject, new NSRange(0, m_list.length - 1));
	}


	/**
	 * Searches the specified range within the receiver for anObject (testing 
	 * for equality by comparing object addresses) and returns the lowest index 
	 * whose corresponding array value is identical to anObject. If none of the 
	 * objects in the specified range is identical to anObject, NSNotFound is 
	 * returned.
	 * 
	 * @param anObject The object to search for
	 * @param range The range to search
	 * @returns The index of the object if found, NSNotFound otherwise.
	 */
	public function indexOfObjectIdenticalToInRange(anObject:Object, 
		range:NSRange):Number
	{
		var startIdx:Number = range.location;
		var endIdx:Number = range.location + range.length;
		
		for (var i:Number = startIdx; i <= endIdx; i++)
		{
			if (m_list[i] == anObject)
				return i;
		}
		
		return NSObject.NSNotFound;
	}
	
	
	/**
	 * Inserts anObject into the collection at index index.
	 *
	 * An error is thrown if the index is greater than the length of the list
	 * or is less than zero.
	 *
	 * This operation should not be performed while the collection is being
	 * enumerated.
	 */
	public function insertObjectAtIndex(anObject:Object, index:Number):Void
	{		
		//
		// Check for index validity.
		//
		if (index > m_list.length || index < 0)
		{
			var e:NSException = NSException.exceptionWithNameReasonUserInfo("InvalidArgumentException", 
				"NSArray::insertObject - The index " + index + " is invalid.", 
				null);
			trace(e);
			throw e;
		}
		
		//
		// Insert the object.
		//
		if (index == m_list.length)
		{
			m_list.push(anObject);			
		}
		else
			m_list.splice(index, 0, anObject);
	}
	
	
	/**
	 * Compares the receiving array to otherArray. If the contents of 
	 * otherArray are equal to the contents of the receiver, this method 
	 * returns true. If not, it returns false.
     * 
     * Two arrays have equal contents if they each hold the same number 
     * of objects and objects at a given index in each array satisfy the 
     * isEqual test.
     *
     * @param otherArray The array to compare against.
     * @returns True if the arrays are the same, false otherwise.
	 */
	public function isEqualToArray(otherArray:NSArray):Boolean
	{
		//
		// Test lengths first, as it's speedy.
		//
		if (m_list.length != otherArray.m_list.length)
			return false;
			
		//
		// Test each of the elements against eachother in turn.
		//
		var len:Number = m_list.length;
		
		for (var i:Number = 0; i < len; i++)
		{
			if (!m_list[i].isEqual(otherArray.m_list[i]))
				return false;
		}
		
		return true;
	}
	
	
	/**
	 * Returns the object located at index. If index is beyond the end of the 
	 * array (that is, if index is greater than or equal to the value returned 
	 * by count), null is returned.
	 */
	public function objectAtIndex(index:Number):Object
	{
		//
		// Check if the index is in range.
		//
		if (index < 0 || index >= m_list.length)
			return null;
			
		return m_list[index];
	}
	
	
	/**
	 * Clears the collection.
	 *
	 * This operation should not be performed while the collection is being
	 * enumerated.
	 */	
	public function removeAllObjects():Void
	{
		m_list = new Array();
	}
	
	
	/**
	 * Removes the last object in the collection.
	 *
	 * An exception is raised if the collection is empty.
	 */
	public function removeLastObject():Void
	{
		if (m_list.length == 0)
		{
			var e:NSException = NSException.exceptionWithNameReasonUserInfo(
				"RangeException", 
				"NSArray::removeLastObject - This method cannot be called " + 
				"when the collection is empty.", 
				null);
			trace(e);
			throw e;
		}
		
		//! this could be faster with splice, but is better practice this way
		removeObjectAtIndex(m_list.length - 1); 
	}
	
	
	/**
	 * Removes the object anObject from the collection.
	 */
	public function removeObject(anObject:Object):Void
	{
		var idx:Number = indexOfObjectIdenticalTo(anObject);
		
		if (idx == NSObject.NSNotFound)
			return;
			
		m_list.splice(idx, 1);
	}
	
	
	/**
	 * Removes the object at the index index from the collection. 
	 */
	public function removeObjectAtIndex(index:Number):Void
	{
		//
		// Check if the index is in range.
		//
		if (index < 0 || index >= m_list.length)
		{
			var e:NSException = NSException.exceptionWithNameReasonUserInfo(
				"RangeException", 
				"NSArray::removeObjectAtIndex - The index " + index + 
				" is out of range.", 
				null);
			trace(e);
			throw e;
		}
			
		m_list.splice(index, 1); // Remove the object.
	}
	
	
	/**
	 * //!
	 * I'm not really sure why this is here since it is the same as 
	 * replaceObjectAtIndexWithObject.
	 */
	public function replaceObject(index:Number, anObject:Object):Void 
	{
		replaceObjectAtIndexWithObject(index, anObject);
	}
	
	
	/**
	 * Replaces the object at index index with anObject.
	 */
	public function replaceObjectAtIndexWithObject(index:Number, anObject:Object):Void
	{			
		m_list[index] = anObject;
	}
	
	
	/**
	 * Sets object[key] = value for each of the objects in the array.
	 *
	 * @param key The key (or property) to change.
	 * @param value The new value of the property.
	 */
	public function setValue(key:String, value:Object):Void
	{
		var setterKey:String = "set" + ASUtils.capitalizeWords(key);
		
		var len:Number = m_list.length; // faster
		for (var i:Number = 0; i < len; i++)
		{
			var obj:Object = m_list[i];
			
			//
			// If there is a setter function for the key, call it using the
			// provided value. Otherwise, set the object's ["key"] property
			// equal to value.
			//
			if (obj[setterKey] != undefined && 
				obj[setterKey] instanceof Function) // leave as 2nd test
			{
				obj[setterKey](value);
			}
			else
			{
				obj[key] = value;
			}
		}
	}
	
	//******************************************************															 
	//*                  Sorting Functions
	//******************************************************
	
	/**
	 *
	 */
	public function sortUsingDescriptors(sortDescriptors:NSArray):Void
	{
		//
		// Can't sort if there are no descriptors.
		//
		if (sortDescriptors.count() == 0)
		{
			return;
		}
		
		NSArray.quickSort(m_list, 0, m_list.length - 1, sortDescriptors);
	}
	
	
	/**
	 * Sorts the collection in ascending order using the comparison function
	 * compare. The comparison method prototype should be as follows:
	 *
	 * compare(object1:Object, object2:Object[, context:Object]):NSComparisonResult
	 *
	 * The optional context argument is that specified by context, and can contain
	 * additional information relating to the sort.
	 */
	public function sortUsingFunctionContext(compare:Function, context:Object):Void
	{
		NSArray.quickSort(m_list, 0, m_list.length - 1, compare, context);
	}
	
	
	/**
	 * Sorts the array using the comparison method specified by comparator.
	 *
	 * The method named comparator is called on each object in the array with the 
	 * single argument of another object in the array. It should return 
	 * NSComparisonResult.NSOrderedAscending if the receiver is smaller than the
	 * argument, NSComparisonResult.NSOrderedEqual if they are equal, and 
	 * NSComparisonResult.NSOrderedDescending if the receiver is less than the 
	 * argument.
	 */
	public function sortUsingSelector(comparator:String):Void
	{
		NSArray.quickSort(m_list, 0, m_list.length - 1, comparator);
	}
	
	//******************************************************															 
	//*	                   NSCopying
	//******************************************************
	
	public function copyWithZone():NSObject
	{
		var ret:NSArray = NSArray.array();
		var len:Number = m_list.length;
		
		for (var i:Number = 0; i < len; i++)
		{
			var val:Object = m_list[i];
			
			if (m_list[i].copyWithZone instanceof Function)
			{
				val = m_list[i].copyWithZone();
			}
			else if (m_list[i].memberwiseClone instanceof Function)
			{
				val = m_list[i].memberwiseClone();
			}
			
			ret.addObject(val);
		}
		
		return ret;		
	}
	
	//******************************************************															 
	//*				    Protected Methods				   *
	//******************************************************
	//******************************************************															 
	//*					 Private Methods				   *
	//******************************************************
	//******************************************************															 
	//*			     Public Static Methods				   *
	//******************************************************
	
	/**
	 * Combines two arrays and returns a new array consisting of 
	 * all elements from both.
	 *
	 * Duplicates are allowed.
	 *
	 * Note: This method is not covered by the Cocoa specification.
	 */
	public static function combine(array1:NSArray, array2:NSArray):NSArray
	{
		var newArray:Array = array1.m_list.concat(array2.m_list);
		
		return NSArray.arrayWithArray(newArray);
	}
		
	//******************************************************															 
	//*				 Private Static Methods				   *
	//******************************************************
	
	/**
	 * This is the standard quicksort algorithm modified a little bit
	 * to support selectors and custom comparing methods.
	 *
	 * @param arr      The array to sort.
	 * @param first    The starting index of the sort.
	 * @param last     The last index of the sort.
	 * @param compare  This argument can be a selector string or a comparison function.
	 *                 Please see NSArray.sortUsingSelector() and 
	 *                 NSArray.sortUsingFunctionContext() for further details.
	 * @param context  This is an optional piece of information that is passed on every
	 *                 call to the comparison function.
	 * @param sortMode Used internally. Do not pass a value.
	 */
	public static function quickSort(arr:Array, first:Number, last:Number, 
		compare:Object, context:Object, sortMode:Number):Void
	{			
		var f:Number = first;
		var l:Number = last;
		var item:Object = arr[Math.round((f + l) / 2)];
		
		//
		// Determine sort mode if applicable
		//
		if (sortMode == undefined)
		{
			if(typeof(compare) == "string" || compare instanceof String)
			{
				sortMode = 1; // selector
			}
			else if (typeof(compare) == "function" || compare instanceof Function)
			{
				sortMode = 2; // compare function
			}
			else if (compare instanceof NSArray)
			{
				sortMode = 3; // array of descriptors
			}
		}
		
		//
		// Sort the array.
		//
		do
		{
			switch (sortMode)
			{
				//
				// Sort using selectors
				//
				case 1: 
				
					while (arr[f][compare](item) == NSComparisonResult.NSOrderedAscending) 
						f++;
						
					while (item[compare](arr[l]) == NSComparisonResult.NSOrderedAscending)
						l--;
					
					break;
				
				//
				// Sort using a compare function (and context)
				//
				case 2:
				
					var compareFunc:Function = Function(compare);
					
					while (compareFunc(arr[f], item, context) == NSComparisonResult.NSOrderedAscending) 
						f++;
						
					while (compareFunc(item, arr[l], context) == NSComparisonResult.NSOrderedAscending)
						l--;
						
					break;
					
				//
				// Sort using an array of NSSortDescriptors
				//
				case 3:
					
					var arrDesc:NSArray = NSArray(compare);
					
					while (NSSortDescriptor.compareObjectToObjectWithDescriptors(
						arr[f], item, arrDesc) == NSComparisonResult.NSOrderedAscending) 
					{
						f++;
					}
						
					while (NSSortDescriptor.compareObjectToObjectWithDescriptors(
						item, arr[l], arrDesc) == NSComparisonResult.NSOrderedAscending)
					{
						l--;
					}
										
					break;
			}
			
			if (f <= l)
			{
				//
				// swap
				//
				var temp:Object = arr[f];
				arr[f] = arr[l];
				arr[l] = temp;
				
				f++;
				l--;
			}
		}
		while (f <= l);
		
		if (first < l) 
			quickSort(arr, first, l, compare, context, sortMode);
			
		if (f < last)  
			quickSort(arr, f, last, compare, context, sortMode);
	}
	
	//******************************************************															 
	//*				 	Class Constructors				   *
	//******************************************************	
	
	/**
	 * Creates and returns a new NSArray.
	 *
	 * @returns The new NSArray.
	 */
	public static function array():NSArray 
	{
		return new NSArray();
	}
	

	/**
	 * Creates and returns an NSArray containing the objects in anArray.
	 *
	 * Please note that this differs from 
	 * @see ActionStep.NSArray#arrayWithNSArray as it takes Flash's intrinsic
	 * Array type and not an NSArray.
	 *
	 * @param anArray An Array to copy.
	 * @returns The new NSArray.
	 */	
	public static function arrayWithArray(anArray:Array):NSArray
	{		
		var ret:NSArray = new NSArray();
		ret.m_list = anArray.slice(0, anArray.length);
						
		return ret;		
	}
	
	
	/**
	 * Creates and returns an NSArray containing the objects in anArray.
	 *
	 * @param anArray An NSArray to copy.
	 * @returns The new NSArray.
	 */
	public static function arrayWithNSArray(anArray:NSArray):NSArray
	{
		return arrayWithArray(anArray.m_list);
	}
	
	
	/**
	 * Creates and returns an NSArray with a capacity of numItems.
	 *
	 * Since the Cocoa docs say that numItems is an unsigned int, and
	 * we don't have any equivalent in ActionScript, this method
	 * will throw an exception if numItems is negative.
	 */
	public static function arrayWithCapacity(numItems:Number):NSArray
	{
		//
		// Throw an exception if out of range.
		//
		if (numItems < 0)
		{
			var e:NSException = NSException.exceptionWithNameReasonUserInfo(
				"NSInvalidArgumentException",
				"numItems cannot be negative.",
				null);
			trace(e);
			throw e;
		}
		
		var ret:NSArray = new NSArray();
		ret.m_list = new Array(numItems);
		
		return ret;
	}
	
	
	/**
	 * Creates and returns an array containing the single element anObject.
	 *
	 * @param anObject The single object to add to the array.
	 * @returns The new NSArray.
	 */
	public static function arrayWithObject(anObject:Object):NSArray
	{
		var ret:NSArray = new NSArray();
		ret.m_list.push(anObject);
						
		return ret;
	}
	

	/**
	 * Creates and returns an array containing the objects in the argument list.
	 *
	 * This method takes a list comma-seperated objects.
	 *
	 * @returns The new NSArray.
	 */	
	public static function arrayWithObjects():NSArray
	{
		return NSArray.arrayWithArray(arguments);
	}
	
	
	/**
	 * Creates and returns an array containing count objects from objects.
	 *
	 * This method takes a list comma-seperated objects followed by a numeric
	 * count as parameters.
	 *
	 * @returns The new NSArray.
	 */
	public static function arrayWithObjectsCount():NSArray
	{
		var args:Array = Array(arguments);
		var cnt:Number = Number(args.pop());
		var objects:Array = args.splice(0, cnt);
		
		return NSArray.arrayWithArray(objects);
	}
	
	/**
	 * Sends the aSelector message to each object in the array, starting with 
	 * the first object and continuing through the array to the last object. The 
	 * aSelector method must not take any arguments. It shouldn’t have the 
	 * side effect of modifying the receiving array. This method raises an 
	 * NSInvalidArgumentException if aSelector is NULL.
	*/
	
	public function makeObjectsPerformSelector(sel:String):Void {
		
	}
	
	public function makeObjectsPerformSelectorWithObject(sel:String, obj:Object):Void {
		
	}
}
