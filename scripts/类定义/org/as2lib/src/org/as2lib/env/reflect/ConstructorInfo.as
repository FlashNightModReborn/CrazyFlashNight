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

import org.as2lib.env.reflect.ClassInfo;
import org.as2lib.env.reflect.MethodInfo;

/**
 * {@code ConstructorInfo} represents the constrcutor of a class.
 *
 * <p>The name of a constructor is always {@code "new"}. This name can be obtained
 * through the constant {@link #NAME}.
 * 
 * <p>Constructors are also not static.
 *
 * @author Simon Wacker
 */
class org.as2lib.env.reflect.ConstructorInfo extends MethodInfo {
	
	/** The name of constructors. */
	public static var NAME:String = "new";
	
	/**
	 * Constructs a new {@code ConstructorInfo} instance.
	 * 
	 * <p>If {@code constructor} is not specified, what means {@code undefined}, it
	 * will be resolved at run-time everytime requested.
	 *
	 * @param declaringClass the class that declares the {@code constructor}
	 * @param constructor (optional) the concrete constructor
	 */
	public function ConstructorInfo(declaringClass:ClassInfo, constructor:Function) {
		//super (NAME, constructor, declaringClass, false);
		// there is a cyclic import: ClassInfo imports ConstructorInfo and ConstructorInfo ClassInfo
		this.__proto__.__proto__ = MethodInfo.prototype;
		this.name = NAME;
		this.method = constructor;
		this.declaringType = declaringClass;
		this.staticFlag = false;
	}
	
	/**
	 * Returns the concrete constructor this instance represents.
	 *
	 * <p>If the concrete constructor was not specified on construction it will be
	 * resolved at run-time by this method everytime asked for. The returned
	 * constructor is thus always the current constructor of the declaring type.
	 * Resolving the class's constructor at run-time does only work if the declaring
	 * type returns a not-{@code null} package and a not-{@code null} name. If these
	 * two are {@code null} or {@code undefined} the function returned by the
	 * {@code getType} method of the declaring type is returned.
	 *
	 * @return the concrete constructor
	 */
	public function getMethod(Void):Function {
		if (method !== undefined) {
			return method;
		}
		if (declaringType.getPackage().getPackage() == null
				|| declaringType.getName() == null) {
			return declaringType.getType();		
		}
		return declaringType.getPackage().getPackage()[declaringType.getName()];
	}
	
	/**
	 * Returns a {@link ConstructorInfo} instance that reflects the current state of
	 * this constructor info.
	 * 
	 * @return a snapshot of this constructor info
	 */
	public function snapshot(Void):MethodInfo {
		return new ConstructorInfo(ClassInfo(declaringType), getMethod());
	}
	
}