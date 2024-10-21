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
import org.actionstep.NSEnumerator;
import org.actionstep.NSException;
import org.actionstep.NSObject;


/**
 * The NSDictionary object holds key value pairs, accessible by key. Keys
 * are unique, that is, there can only be one object for every key.
 *
 * This class is a combination of NSDictionary and NSMutableDictionary classes
 * as defined in the Cocoa documentation.
 *
 * @author Scott Hyndman
 */
class org.actionstep.NSDictionary extends NSObject
	implements NSCopying
{
	private var m_keys:NSArray;
	private var m_objects:NSArray;
	private var m_dict:Object;
	private var m_count:Number;


	/**
	 * Creates a new instance of NSDictionary with no entries.
	 */
	public function NSDictionary()
	{
		m_dict = new Object();
		m_count = 0;
		m_keys = new NSArray();
		m_objects = new NSArray();
	}


	/**
	 * Initializes this dictionary with the contents from another
	 * dictionary, and returns the initialized object.
	 */
	public function initWithDictionary(otherDictionary:NSDictionary):NSDictionary
	{
		return initWithDictionaryCopyItems(otherDictionary, false);
	}


	/**
	 * Initializes this dictionary with the contents of otherDictionary
	 * if flag is FALSE, and copies of the contents of otherDictionary if
	 * flag is TRUE.
	 */
	public function initWithDictionaryCopyItems(otherDictionary:NSDictionary,
		flag:Boolean):NSDictionary
	{
		var dict:Object = otherDictionary.m_dict;

		for (var key:String in dict)
		{
			var val:Object = dict[key];

			if (flag && val.copyWithZone instanceof Function)
			{
				val = val.copyWithZone();
			}

			setObjectForKey(val, key);
		}

		return this;
	}


	/**
	 * Initializes this dictionary with the contents of objects and keys.
	 * The objects and keys array are stepped through, with each entry
	 * being added in turn.
	 *
	 * An exception is through if objects and keys don't contain the same
	 * number of elements.
	 */
	public function initWithObjectsForKeys(objects:NSArray, keys:NSArray)
		:NSDictionary
	{
		if (objects.count() != keys.count())
		{
			var e:NSException = NSException.exceptionWithNameReasonUserInfo(
				"InvalidArgumentException", "initWithObjectsForKeys - object " +
				"and key arrays must have the same number of elements", null);
			trace(e);
			throw e;
		}

		var kitr:NSEnumerator = keys.objectEnumerator();
		var oitr:NSEnumerator = objects.objectEnumerator();
		var key:Object;
		var obj:Object;

		while (null != (key = kitr.nextObject()))
		{
			obj = oitr.nextObject();

			try {
				setObjectForKey(obj, String(key));
			} catch(e:NSException) {
				break;
			}
		}

		return this;
	}


	/**
	 * Initializes this dictionary with count entries consisting of
	 * keys from the keys array and objects from the objects array.
	 *
	 * An exception is through if objects and keys don't contain the same
	 * number of elements.
	 */
	public function initWithObjectsForKeysCount(objects:NSArray, keys:NSArray,
		count:Number):NSDictionary
	{
		if (objects.count() != keys.count())
		{
			var e:NSException = NSException.exceptionWithNameReasonUserInfo(
				"InvalidArgumentException", "initWithObjectsForKeys - object " +
				"and key arrays must have the same number of elements", null);
			trace(e);
			throw e;
		}

		while (keys.count() > count)
			keys.removeObjectAtIndex(keys.count() - 1);

		while (objects.count() > count)
			objects.removeObjectAtIndex(objects.count() - 1);

		return initWithObjectsForKeys(objects, keys);
	}


	/**
	 * Initializes this dictionary containing entries constructed from
	 * the arguments list, which alternate between objects and keys.
	 *
	 * An exception is raised if a key is null.
	 */
	public function initWithObjectsAndKeys():NSDictionary
	{
		var args:Array = arguments;
		var obj:Object;

		for (var i:Number = 0; i < args.length; i++)
		{
			var isObj:Boolean = (i % 2) == 0;

			if (isObj)
			{
				obj = args[i];
				continue;
			}

			//
			// Key handling
			//
			if (args[i] == null)
			{
				var e:NSException = NSException.exceptionWithNameReasonUserInfo(
					"InvalidArgumentException", "initWithObjectsAndKeys - object " +
					"and key arrays must have the same number of elements", null);
				trace(e);
				throw e;
			}
			
			try {
				setObjectForKey(obj, args[i]);
			} catch(e:NSException) {
				//if obj is null, continue to next pair
				continue;
			}
		}

		return this;
	}


	//******************************************************
	//*					  Properties					   *
	//******************************************************

	/**
	 * Returns a new array containing this dictionary's keys.
	 */
	public function allKeys():NSArray
	{
		return NSArray.arrayWithNSArray(m_keys);
	}


	/**
	 * Returns a new array containing this dictionary's objects.
	 */
	public function allValues():NSArray
	{
		return NSArray.arrayWithNSArray(m_objects);
	}


	/**
	 * Returns the number of entries this dictionary contains.
	 */
	public function count():Number
	{
		return m_count;
	}


	/**
	 * @see org.actionstep.NSObject#description
	 */
	public function description():String
	{
		var ret:String = "NSDictionary(";

		for (var key:String in m_dict)
		{
			ret += "\n\t"+key + "=>" + m_dict[key].toString() + ",";
		}

		if (count() > 0)
			ret = ret.substr(0, ret.length -1);

		ret += "\n\t)";

		return ret;
	}


	/**
	 * Returns the internal data structure of this dictionary.
	 *
	 * For developer use only.
	 */
	public function internalDictionary():Object
	{
		return m_dict;
	}


	/**
	 * Returns an enumerator for this dictionary's keys.
	 *
	 * Do not modify this collection while undergoing enumeration. If you
	 * wish to do so, use the allKeys() method, and enumerate through that
	 * array, as it is a copy.
	 */
	public function keyEnumerator():NSEnumerator
	{
		return m_keys.objectEnumerator();
	}


	/**
	 * Returns an enumerator for this dictionary's values.
	 *
	 * Do not modify this collection while undergoing enumeration. If you
	 * wish to do so, use the allObjects() method, and enumerate through that
	 * array, as it is a copy.
	 */
	public function objectEnumerator():NSEnumerator
	{
		return m_objects.objectEnumerator();
	}


	/**
	 * Returns the object associated with the key aKey, or null if the key does
	 * not exist.
	 */
	public function objectForKey(key:String):Object
	{
		var obj:Object = m_dict[key];
		return obj == undefined ? null : obj; // make sure null is returned, not undefined
	}

	//******************************************************
	//*					 Public Methods					   *
	//******************************************************

	/**
	 * Returns a new array containing all keys associated with anObject.
	 */
	public function allKeysForObject(anObject:Object):NSArray
	{
		var ret:NSArray = new NSArray();
		var isNSObj:Boolean = anObject instanceof NSObject;

		//
		// If anObject is an NSObject, we use isEqual, and
		// reference equality otherwise.
		//
		if (isNSObj)
		{
			for (var p:String in m_dict)
			{
				if (anObject.isEqual(m_dict[p]))
					ret.addObject(p);
			}
		}
		else
		{
			for (var p:String in m_dict)
			{
				if (anObject == m_dict[p])
					ret.addObject(p);
			}
		}

		return ret;
	}


	/**
	 * Returns TRUE if this dictionary is equal to otherDictionary, and FALSE
	 * otherwise.
	 *
	 * The two dictionaries are equal if their sizes are the same, and for any
	 * given key, the corresponding object must satisfy an isEqual() test
	 * (if NSObject) or an equality test (if not NSObject).
	 */
	public function isEqualToDictionary(otherDictionary:NSDictionary):Boolean
	{
		//
		// Size test (fastest and easiest)
		//
		if (m_count != otherDictionary.m_count)
			return false;

		//!

		return true;
	}


	//******************************************************
	//*			  Adding and Removing Entries			   *
	//******************************************************

	/**
	 * Adds each entry from otherDictionary into this dictionary.
	 *
	 * If a key in otherDictionary already exists in this dictionary, the
	 * object is replaced.
	 */
	public function addEntriesFromDictionary(otherDictionary:NSDictionary):Void
	{
		var itr:NSEnumerator = otherDictionary.keyEnumerator();
		var key:String;

		while (null != (key = String(itr.nextObject())))
		{
			this.setObjectForKey(otherDictionary.objectForKey(key), key);
		}
	}


	/**
	 * Empties the dictionary.
	 */
	public function removeAllObjects():Void
	{
		m_keys.clear();
		m_objects.clear();
		m_dict = new Object();
		m_count = 0;
	}


	/**
	 * Removes the object corresponding to aKey from the dictionary.
	 */
	public function removeObjectForKey(aKey:String):Void
	{
		if (aKey == null)
			return;

		var obj:Object = objectForKey(aKey);

		if (obj == null) // don't do anything
			return;

		m_objects.removeObject(obj);
		m_keys.removeObject(aKey);
		m_count--;
		delete m_dict[aKey];
	}


	/**
	 * Removes the objects corresponding to the keys in keyArray.
	 */
	public function removeObjectsForKeys(keyArray:NSArray):Void
	{
		var itr:NSEnumerator = keyArray.objectEnumerator();

		//
		// Remove objects for each key in turn.
		//
		var key:String;
		while (null != (key = String(itr.nextObject())))
		{
			removeObjectForKey(key);
		}
	}


	/**
	 * Sets the contents of this dictionary to the contents of otherDictionary.
	 */
	public function setDictionary(otherDictionary:NSDictionary):Void
	{
		removeAllObjects();
		addEntriesFromDictionary(otherDictionary);
	}


	/**
	 * Adds an entry to this dictionary consisting of the key aKey, and its
	 * corresponding value anObject.
	 *
	 * If a value corresponding to aKey already exists, it is replaced with
	 * anObject.
	 *
	 * An exception is thrown if anObject or aKey is null.
	 */
	public function setObjectForKey(anObject:Object, aKey:String):Void
	{
		if (anObject == null || aKey == null)
		{
			var e:NSException = NSException.exceptionWithNameReasonUserInfo(
				"InvalidArgumentException", "setObjectForKey - anObject " +
				"and aKey arguments cannot be null.", null);
			trace(e);
			throw e;
		}

		//
		// If doesn't exist, add the key, and up the count,
		// otherwise remove the old object.
		//
		if (objectForKey(aKey) == null)
		{
			m_keys.addObject(aKey);
			m_count++;
		}
		else
		{
			m_objects.removeObject(objectForKey(aKey));
		}

		//
		// No need to store multiple references to the same object.
		//
		if (!m_objects.containsObject(anObject))
			m_objects.addObject(anObject);

		m_dict[aKey] = anObject;
	}

	//******************************************************
	//*	                   NSCopying
	//******************************************************

	public function copyWithZone():NSObject
	{
		var result:NSDictionary = new NSDictionary();
		result.initWithDictionaryCopyItems(NSDictionary(this), true);
		return result;
	}

	//******************************************************
	//*				    Protected Methods				   *
	//******************************************************
	//******************************************************
	//*					 Private Methods				   *
	//******************************************************
	//******************************************************
	//*			   Public Static Properties				   *
	//******************************************************
	//******************************************************
	//*				 Public Static Methods				   *
	//******************************************************

	/**
	 * Creates and returns an empty dictionary.
	 */
	public static function dictionary():NSDictionary
	{
		return new NSDictionary();
	}


	/**
	 * Creates and returns a dictionary filled with the contents
	 * of otherDictionary.
	 */
	public static function dictionaryWithDictionary(
		otherDictionary:NSDictionary):NSDictionary
	{
		return (new NSDictionary()).initWithDictionary(otherDictionary);
	}


	/**
	 * Creates and returns a dictionary containing a single entry
	 * of anObject indexed on aKey.
	 */
	public static function dictionaryWithObjectForKey(anObject:Object,
		aKey:String):NSDictionary
	{
		var dict:NSDictionary = new NSDictionary();
		try {
			dict.setObjectForKey(anObject, aKey);
		} catch(e:NSException) {
			//tag it so that line, class name, etc set
			trace(e);
			e.raise();
		}
		return dict;
	}


	/**
	 * Creates and returns a dictionary containing the contents of
	 * objects and keys.
	 *
	 * An exception is raised if the objects and keys array don't have the
	 * same number of elements.
	 */
	public static function dictionaryWithObjectsForKeys(objects:NSArray,
		keys:NSArray):NSDictionary
	{
		return (new NSDictionary()).initWithObjectsForKeys(
			objects, keys);
	}


	/**
	 * Creates and returns a dictionary containing count objects from
	 * objects and keys.
	 *
	 * An exception is raised if the objects and keys array don't have the
	 * same number of elements.
	 */
	public static function dictionaryWithObjectsForKeysCount(objects:NSArray,
		keys:NSArray, count:Number):NSDictionary
	{
		return (new NSDictionary()).initWithObjectsForKeysCount(
			objects, keys, count);
	}


	/**
	 * Creates and returns a dictionary containing entries constructed from
	 * the arguments list, which alternate between objects and keys.
	 *
	 * An exception is raised if a key is null.
	 */
	public static function dictionaryWithObjectsAndKeys():NSDictionary
	{
		var dict:NSDictionary = new NSDictionary();
		dict.initWithObjectsAndKeys.apply(dict, arguments);
		return dict;
	}
}
