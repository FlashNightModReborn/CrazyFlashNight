/*
   Copyright 2004 Peter Armstrong

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
import mx.controls.treeclasses.TreeNode;
import mx.controls.treeclasses.TreeDataProvider;

/**
 * An InstanceDataProvider makes a tree model out of an object.
 */
class org.log4f.logging.console.InstanceDataProvider
	implements TreeDataProvider {
	
	private var _key:String;
	
	private var _value:Object;
	
	private var _dataString:String;
	
	private var _children:Array;

	private var _addedChildren:Boolean;

	public function InstanceDataProvider(key:String, value:Object) {
		_key = key;
		_value = value;
		_dataString = _key + " = " + _value;
		_addedChildren = false;
		_children = null;
	}

	private function addChildrenIfNecessary() {
		if (_addedChildren) return;
		_children = new Array();
		for (var childPropKey:String in _value) {
			var childPropValue:Object = _value[childPropKey];
			_children.push(new InstanceDataProvider(
				childPropKey, childPropValue));
		}
		_addedChildren = true;
	}
	
	/**
	 * Returns an Array that contains all child nodes.
	 */
	public function getChildNodes():Array {
		addChildrenIfNecessary();
		return _children;
	}
	
	/**
	 * Returns the data for this item.
	 */	
	public function getData():Object {
		return _dataString;
	}

	/**
	 * Returns a property of this item.
	 */
	public function getProperty(propertyName: String) {
	}

	/**
	 * Gets a reference to the child item at a specified position.
	 */
	public function getTreeNodeAt(index: Number) {
	}

	/**
	 * Returns true if the item has child nodes.
	 */
	public function hasChildNodes():Boolean {
		if (_addedChildren) {
			return _children.length > 0;
		} else {
			return true;//TODO - typeof??
		}
	}

	/**
	 * Returns the index of an item.
	 */
	public function indexOf(item:Object):Number {
		return 0;//TODO
	}
	
	public function toString():String {
		return _dataString;
	}

	//
	//UNIMPLEMENTED METHODS OF TreeDataProvider
	//

	public function getParent() {
		return undefined;
	}

	/**
	 * THIS METHOD ALWAYS RETURNS TRUE.
	 * Determines whether the data provider is valid.
	 */
	public function isTreeDataProvider():Boolean {
		return true;
	}
	
	/**
	 * THIS METHOD IS NOT IMPLEMENTED.
	 * Adds a new child at the end of the data provider.
	 */
    public function addTreeNode(labelOrNode, data) {}

	/**
	 * THIS METHOD IS NOT IMPLEMENTED.
	 * Adds a child at the specified position of this data provider.
	 */
    public function addTreeNodeAt(index, labelOrNode, data) {}
    
	/**
	 * THIS METHOD IS NOT IMPLEMENTED.
	 * Removes all children from this node.
	 */
	public function removeAll() {}

	/**
	 * THIS METHOD IS NOT IMPLEMENTED.
	 * Removes this node/item from its parent node.
	 */
	public function removeTreeNode() {}

	/**
	 * THIS METHOD IS NOT IMPLEMENTED.
	 * Removes a child item at a specified position from this item.
	 */
	public function removeTreeNodeAt(index) {}

	/**
	 * THIS METHOD IS NOT IMPLEMENTED.
	 * Sets the data for the item.
	 */
	public function setData(data: Object) {}

	/**
	 * THIS METHOD IS NOT IMPLEMENTED.
	 * Sets a property of this item.
	 */
	public function setProperty(
		propertyName:String, propertyValue, broadcastChange: Boolean) {}
}