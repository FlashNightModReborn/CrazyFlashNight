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

import org.as2lib.env.reflect.PackageMemberInfo;
import org.as2lib.env.reflect.MethodInfo;
import org.as2lib.env.reflect.TypeMemberFilter;
import org.as2lib.env.reflect.PackageInfo;

/**
 * {@code TypeInfo} represents a type a ActionScript type, that is either a class
 * or an interface.
 * 
 * <p>Note that it is not possible right now to distinguish between classes and
 * interfaces at run-time. Therefore are both classes and interfaces represented by
 * {@link ClassInfo} instances. This is going to change as soon is a differentiation
 * is possible.
 *
 * @author Simon Wacker
 */
interface org.as2lib.env.reflect.TypeInfo extends PackageMemberInfo {
	
	/**
	 * Returns the type this instance represents.
	 * 
	 * @return the type represented by this instance
	 */
	public function getType(Void):Function;
	
	/**
	 * Returns the super type of this type.
	 * 
	 * <p>Talking of classes the super-type is the class's super-class, that means the
	 * class it extends and with interfaces it is the interface's super-interface, that
	 * means the interface it extends.
	 *
	 * <p>A super-type is not an implemented interface. Note the difference between
	 * extending and implementing.
	 * 
	 * @return the super types of this type
	 */
	public function getSuperType(Void):TypeInfo;
	
	/**
	 * Returns the package this type is a member of.
	 * 
	 * @return the package this type is a member of
	 */
	public function getPackage(Void):PackageInfo;
	
	/**
	 * Returns whether this type or any super-type has a method with the passed-in
	 * {@code methodName}.
	 * 
	 * <p>Static methods are not filtered by default. This means {@code filterStaticMethods}
	 * is by default set to {@code false}.
	 *
	 * @param methodName the name of the method to search for
	 * @param filterStaticMethods (optional) determines whether static methods are
	 * filtered, this means excluded from the search
	 * @return {@code true} if the method exists else {@code false}
	 */
	public function hasMethod(methodName:String, filterStaticMethods:Boolean):Boolean;
	
	/**
	 * @overload #getMethodsByFlag
	 * @overload #getMethodsByFilter
	 */
	public function getMethods():Array;
	
	/**
	 * Returns an array containing the methods represented by {@code MethodInfo} instances
	 * this type declares and maybe the ones of the super types.
	 * 
	 * <p>The super types' methods are included if you pass-in {@code false}, {@code null}
	 * or {@code undefined} and excluded/filtered if you pass-in {@code true}. This means
	 * super-types are by default included.
	 * 
	 * <p>Note that methods of interfaces cannot be evaluated at run-time. They thus
	 * have no methods for the Reflection API.
	 * 
	 * @param filterSuperTypes (optional) determines whether to filter/exclude the super
	 * types' methods
	 * @return an array containing the methods represented by {@code MethodInfo} instances
	 */
	public function getMethodsByFlag(filterSuperTypes:Boolean):Array;
	
	/**
	 * Returns an array containing the methods represented by {@code MethodInfo} instances
	 * this type and super types' declare that are not filtered/excluded.
	 * 
	 * <p>The {@link TypeMemberFilter#filter} method of the passed-in {@code methodFilter}
	 * is invoked for every method to determine whether it shall be contained in the
	 * result.
	 *
	 * <p>If the passed-in {@code methodFilter} is {@code null} or {@code undefined} the
	 * result of an invocation of the {@link #getMethodsByFlag} method with argument
	 * {@code false} will be returned.
	 *
	 * <p>Note that methods of interfaces cannot be evaluated at run-time. They thus
	 * have no methods for the Reflection API.
	 * 
	 * @param methodFilter the filter that filters unwanted methods out
	 * @return an array containing the remaining methods represented by {@code MethodInfo}
	 * instances
	 */
	public function getMethodsByFilter(methodFilter:TypeMemberFilter):Array;
	
	/**
	 * @overload #getMethodByName
	 * @overload #getMethodByMethod
	 */
	public function getMethod():MethodInfo;
	
	/**
	 * Returns the method info corresponding to the passed-in {@code methodName}.
	 *
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The passed-in {@code methodName} is {@code null} or {@code undefined}.</li>
	 *   <li>The method does not exist in the represented type or any super-type.</li>
	 * </ul>
	 * 
	 * <p>Note that methods of interfaces cannot be evaluated at run-time. They thus
	 * have no methods for the Reflection API.
	 *
	 * @param methodName the name of the method you wanna obtain
	 * @return the method info correspoinding to the passed-in {@code methodName}
	 */
	public function getMethodByName(methodName:String):MethodInfo;
	
	/**
	 * Returns the method info corresponding to the passed-in {@code concreteMethod}.
	 * 
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The passed-in {@code concreteMethod} is {@code null} or {@code undefined}.</li>
	 *   <li>The method does not exist in the represented type or any super-type.</li>
	 * </ul>
	 *
	 * <p>Note that methods of interfaces cannot be evaluated at run-time. They thus
	 * have no methods for the Reflection API.
	 * 
	 * @param concreteMethod the method you wanna obtain the corresponding method info
	 * for
	 * @return the method info correspoinding to the passed-in {@code concreteMethod}
	 */
	public function getMethodByMethod(concreteMethod:Function):MethodInfo;
	
}