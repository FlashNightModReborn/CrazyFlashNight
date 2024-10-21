/*
 * Copyright the original author or authors.
 * 
 * Licensed under the MOZILLA PUBLIC LICENSE, Version 1.1 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *      http://www.mozilla.org/MPL/MPL-1.1.html
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import org.as2lib.core.BasicClass;

/**
 * {@code AccessPermission} adjusts the access permissions of members like methods
 * and properties in a specific context.
 * 
 * <p>You can hide methods from for..in loops and protect them from deletion and
 * from being overwritten.
 *
 * <p>Note that no matter what access permissions you set they can be overwritten.
 * 
 * <p>Also note that the access permissions are not applied to the object but to
 * the reference to the object. That means that the object can for example be
 * enumerable in one reference but not in another.
 * 
 * <p>Example:
 * <code>
 *   var object:Object = new Object();
 *   object.myProperty = new Object();
 *   object.mySecondReference = object.myProperty;
 *   trace("myProperty:          Value: " + object.myProperty);
 *   trace("mySecondReference:   Value: " + object.mySecondReference);
 *   AccessPermission.set(object, ["myProperty"], AccessPermission.PROTECT_DELETE);
 *   trace("myProperty:          Permission: " + AccessPermission.get(object, "myProperty"));
 *   trace("mySecondReference:   Permission: " + AccessPermission.get(object, "mySecondReference"));
 *   delete object.myProperty;
 *   delete object.mySecondReference;
 *   trace("myProperty:          Value: " + object.myProperty);
 *   trace("mySecondReference:   Value: " + object.mySecondReference);
 * </code>
 *
 * <p>Output:
 * <pre>
 *   myProperty:          Value: [object Object]
 *   mySecondReference:   Value: [object Object]
 *   myProperty:          Permission: 2
 *   mySecondReference:   Permission: 0
 *   myProperty:          Value: [object Object]
 *   mySecondReference:   Value: undefined
 * </pre>
 *
 * <p>As you can see, the above statement holds true. We have two references that
 * reference the same object. We set the access permission of one reference. We can
 * then not delete the reference the access permission was applied to, but the other
 * reference.
 * 
 * <p>Following is another example with a property in its normal state and another
 * protected property we applied the {@link #ALLOW_NOTHING} access permission to.
 *
 * <p>Example:
 * <code>
 *   var object:Object = new Object();
 *   object.myNormalProperty = "myNormalPropertyValue";
 *   object.myProtectedProperty = "myProtectedPropertyValue";
 *   trace("myNormalProperty:      Default Permission: " + AccessPermission.get(object, "myNormalProperty"));
 *   trace("myProtectedProperty:   Default Permission: " + AccessPermission.get(object, "myProtectedProperty"));
 *   AccessPermission.set(object, ["myProtectedProperty"], AccessPermission.ALLOW_NOTHING);
 *   trace("myProtectedProperty:   New Permission: " + AccessPermission.get(object, "myProtectedProperty"));
 *   object.myNormalProperty = "newMyNormalPropertyValue";
 *   object.myProtectedProperty = "newMyProtectedPropertyValue";
 *   trace("myNormalProperty:      Value After Overwriting: " + object.myNormalProperty);
 *   trace("myProtectedProperty:   Value After Overwriting: " + object.myProtectedProperty);
 *   for (var i:String in object) {
 *     trace(i + ":      Found In For..In Loop, Value: " + object[i]);
 *   }
 *   delete object.myNormalProperty;
 *   delete object.myProtectedProperty;
 *   trace("myNormalProperty:      Value After Deletion: " + object.myNormalProperty);
 *   trace("myProtectedProperty:   Value After Deletion: " + object.myProtectedProperty);
 * </code>
 *
 * <p>Output:
 * <pre>
 *   myNormalProperty:      Default Permission: 0
 *   myProtectedProperty:   Default Permission: 0
 *   myProtectedProperty:   New Permission: 7
 *   myNormalProperty:      Value After Overwriting: newMyNormalPropertyValue
 *   myProtectedProperty:   Value After Overwriting: myProtectedPropertyValue
 *   myNormalProperty:      Found In For..In Loop, Value: newMyNormalPropertyValue
 *   myNormalProperty:      Value After Deletion: undefined
 *   myProtectedProperty:   Value After Deletion: myProtectedPropertyValue
 * </pre>
 *
 * <p>As you can see the protected property cannot be deleted, overwritten and is
 * hidden from for..in loops, while the non-protected property can be deleted, can
 * be overwritten and can be enumerated.
 * 
 * <p>Besides the {@link #get} method you can check up on properties for specific
 * access permissions using the {@link #isEnumerable}, {@link #isDeletable} and
 * {@link #isOverwritable} methods.
 *
 * @author Simon Wacker
 */
class org.as2lib.util.AccessPermission extends BasicClass {
	
	/**
	 * Allow everything to be done with the object.
     */
	public static var ALLOW_ALL:Number = 0;
	
	/**
	 * Hide an object from for..in loops.
     */
	public static var HIDE:Number = 1;
	
	/**
	 * Protect an object from deletion.
     */
	public static var PROTECT_DELETE:Number = 2;
	
	/**
	 * Protect an object from overwriting.
     */
	public static var PROTECT_OVERWRITE:Number = 4;
	
	/**
	 * Allow nothing to be done with the object.
     */
	public static var ALLOW_NOTHING:Number = 7;
	
	/**
	 * Sets the access permission of a reference by an access code.
	 * 
	 * <p>The following access codes are applicable:
	 * <table>
	 *   <tr>
	 *     <th>{@link #HIDE}</th>
	 *     <td>Hides the reference from for-in loops.</td>
	 *   </tr>
	 *   <tr>
	 *     <th>{@link #PROTECT_DELETE}</th>
	 *     <td>Protects the reference from deletion</td>
	 *   </tr>
	 *   <tr>
	 *     <th>{@link #PROTECT_OVERWRITE}</th>
	 *     <td>Protects the reference from overwriting</td>
	 *   </tr>
	 *   <tr>
	 *     <th>{@link #ALLOW_ALL}</th>
	 *     <td>Allows everything to be done with the reference.</td>
	 *   </tr>
	 *   <tr>
	 *     <th>{@link #ALLOW_NOTHING}</th>
	 *     <td>Allows nothing to be done with the reference.</td>
	 *   </tr>
	 * </table>
	 * 
	 * <p>These access codes can be combined as follows to apply multiple access
	 * permissions.
	 * <code>
	 *   AccessPermission.PROTECT_DELETE | AccessPermission.PROTECT_OVERWRITE
	 * </code>
	 *
	 * <p>Note that every new invocation of this method simply overwrites the old access
	 * permissions of the reference.
	 * 
	 * @param target the object that holds references to the objects the access permissions
	 * shall be applied to
	 * @param referenceNames the names of the references to apply the access permission to
	 * @param access the access permissions to apply
	 */
	public static function set(target, referenceNames:Array, access:Number):Void {
		_global.ASSetPropFlags(target, referenceNames, access, true);
	}
	
	/**
	 * Returns the current access permission of the reference.
	 *
	 * <p>The permission is represented by a {@code Number}. This number is a bitwise
	 * combination of the three access specifier {@link #HIDE}, {@link #PROTECT_DELETE}
	 * and {@link #PROTECT_OVERWRITE}. You can find out what the returned access
	 * permission number means using these constants.
	 * 
	 * @param target the target object that holds the reference
	 * @param referenceName the name of the reference to return the access permission for
	 * @return a number representing the access permission of the reference
	 */
	public static function get(target, referenceName:String):Number {
		var result:Number = 0;
		if (!isEnumerable(target, referenceName)) result |= HIDE;
		if (!isOverwritable(target, referenceName)) result |= PROTECT_OVERWRITE;
		if (!isDeletable(target, referenceName)) result |= PROTECT_DELETE;
		return result;
	}
	
	/**
	 * Returns whether the reference is enumerable.
	 * 
	 * @param target the target object that holds the reference
	 * @param referenceName the name of the reference to return whether it is enumerable
	 * @return {@code true} if the reference is enumerable else {@code false}
	 * @link http://chattyfig.figleaf.com/flashcoders-wiki/index.php?ASSetPropFlags
	 */
	public static function isEnumerable(target, referenceName:String):Boolean {
		// Why not use target.isPropertyEnumerable(referenceName)?
		for (var i:String in target){
			if (i == referenceName) return true;
		}
		return false;
	}
	
	/**
	 * Returns whether the reference is overwritable.
	 * 
	 * @param target the target object that holds the reference
	 * @param referenceName the name of the reference to return whether it is overwritable
	 * @return {@code true} if the reference is overwritable else {@code false}
	 * @link http://chattyfig.figleaf.com/flashcoders-wiki/index.php?ASSetPropFlags
	 */
	public static function isOverwritable(target, referenceName:String):Boolean {
		var tmp = target[referenceName];
		var newVal = (tmp == 0) ? 1 : 0;
		target[referenceName] = newVal;
		if(target[referenceName] == newVal){
			target[referenceName] = tmp;
			return true;
		}else{
			return false;
		}
	}
	
	/**
	 * Returns whether the reference is deletable.
	 * 
	 * @param target the target object that holds the reference
	 * @param referenceName the name of the reference to return whether it is deletable
	 * @return {@code true} if the reference is deletable else {@code false}
	 * @link http://chattyfig.figleaf.com/flashcoders-wiki/index.php?ASSetPropFlags
	 */
	public static function isDeletable(target, referenceName:String):Boolean {
		var tmp = target[referenceName];
		if (tmp === undefined) return false;
		var enumerable:Boolean = isEnumerable(target, referenceName);
		delete target[referenceName];
		if(target[referenceName] === undefined){
			target[referenceName] = tmp;
			_global.ASSetPropFlags(target, referenceName, !enumerable, 1);
			return true;
		}
		return false;
	}
	
	/**
	 * Private constructor.
	 */
	private function AccessPermission(Void) {
	}
	
}