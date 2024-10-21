import logging.util.List;

/**
*	@author Ralf Siegel
*	@deprecated will use standard classes if available
*/
class logging.util.Vector implements List
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
	* @see logging.util.List
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
	* @see logging.util.List
	*/	
	public function addAll(list:List):Boolean
	{
		// TODO Array.concat could be faster
		var stat:Boolean = false;
		for (var p = 0; p < list.size(); p++) {
			stat |= this.addItem(list.getItem(p));
		}
		return stat;
	}
	
	/**
	* @see logging.util.List
	*/
	public function clear():Void
	{
		a = new Array();
	}
	
	/**
	* @see logging.util.List
	*/
	public function containsItem(o:Object):Boolean
	{
		for ( var i:Number = 0; i < a.length; i++) {
			if (a[i] === o) return true;
		}
		return false;
	}
	
	/**
	* @see logging.util.List
	*/
	public function getItem(index:Number):Object
	{
		return a[index];
	}
	
	/**
	* @see logging.util.List
	*/
	public function indexOf(o:Object):Number
	{
		for ( var i:Number = 0; i < a.length; i++) {
			if (a[i] === o) return i;
		}
		return -1;
	}
	
	/**
	* @see logging.util.List
	*/
	public function isEmpty():Boolean
	{
		return a.length == 0 ? true : false;
	}
	
	/**
	* @see logging.util.List
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
	* @see logging.util.List
	*/
	public function size():Number
	{
		return a.length;
	}
	
	/**
	* @see logging.util.List
	*/
	public function toArray():Array
	{
		return a.slice();
	}
}
