/*
   Copyright 2004 Ralf Siegel

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*/
import org.log4f.logging.util.List;

/**
*	@author Ralf Siegel
*	@deprecated will use standard classes if available
*/
class org.log4f.logging.util.Vector implements List
{
	private var a:Array;
	
	/**
	* Constructs a new Vector object
	*/
	public function Vector(init:Array)
	{
		if (init == undefined) {
			a = new Array();
		} else {
			a = init;
		}
	}
	
	/**
	* @see org.log4f.logging.util.List
	*/
	public function addItem(o:Object):Boolean
	{
		if(o != null) {
			a.push(o);
			return true;
		}
		return false;
	}

	/**
	* @see org.log4f.logging.util.List
	*/	
	public function addAll(list:List):Boolean
	{
		// TODO Array.concat could be faster
		var retval:Boolean = true;
		for (var p = 0; p < list.size(); p++) {
			var addResult = this.addItem(list.getItem(p));
			if (addResult == false) {
				retval = false;
			}
		}
		return retval;
	}
	
	/**
	* @see org.log4f.logging.util.List
	*/
	public function clear():Void
	{
		a = new Array();
	}
	
	/**
	* @see org.log4f.logging.util.List
	*/
	public function containsItem(o:Object):Boolean
	{
		for ( var i:Number = 0; i < a.length; i++) {
			if (a[i] === o) return true;
		}
		return false;
	}
	
	/**
	* @see org.log4f.logging.util.List
	*/
	public function getItem(index:Number):Object
	{
		return a[index];
	}
	
	/**
	* @see org.log4f.logging.util.List
	*/
	public function indexOf(o:Object):Number
	{
		for ( var i:Number = 0; i < a.length; i++) {
			if (a[i] === o) return i;
		}
		return -1;
	}
	
	/**
	* @see org.log4f.logging.util.List
	*/
	public function isEmpty():Boolean
	{
		return a.length == 0 ? true : false;
	}
	
	/**
	* @see org.log4f.logging.util.List
	*/
	public function removeItem(o:Object):Boolean
	{
		for ( var i:Number = 0; i < a.length; i++) {
			if (a[i] === o) {
				a.splice(i, 1);
				return true;
			}
		}
		return false;
	}
	
	/**
	* @see org.log4f.logging.util.List
	*/
	public function size():Number
	{
		return a.length;
	}
	
	/**
	* @see org.log4f.logging.util.List
	*/
	public function toArray():Array
	{
		return a.slice();
	}
}
