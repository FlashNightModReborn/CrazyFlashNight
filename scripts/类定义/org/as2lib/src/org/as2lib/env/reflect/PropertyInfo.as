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
import org.as2lib.util.Stringifier;
import org.as2lib.env.reflect.TypeInfo;
import org.as2lib.env.reflect.MethodInfo;
import org.as2lib.env.reflect.TypeMemberInfo;
import org.as2lib.env.reflect.stringifier.PropertyInfoStringifier;

/**
 * {@code PropertyInfo} represents a property.
 * 
 * <p>The term property means only properties added via {@code Object.addProperty}
 * or the ones added with the {@code get} and {@code set} keywords, that are implicit
 * getters and setters, not variables.
 * 
 * <p>{@code PropertyInfo} instances for specific properties can be obtained using
 * the methods {@link ClassInfo#getProperties} or {@link ClassInfo#getProperty}.
 * That means you first have to get a class info for the class that declares or
 * inherits the property. You can therefor use the {@link ClassInfo#forObject},
 * {@link ClassInfo#forClass}, {@link ClassInfo#forInstance} and {@link ClassInfo#forName}
 * methods.
 * 
 * <p>When you have obtained the property info you can use it to get information
 * about the property.
 *
 * <code>
 *   trace("Property name: " + propertyInfo.getName());
 *   trace("Declaring type: " + propertyInfo.getDeclaringType().getFullName());
 *   trace("Is Static?: " + propertyInfo.isStatic());
 *   trace("Is Writable?: " + propertyInfo.isWritable());
 *   trace("Is Readable?: " + propertyInfo.isReadable());
 * </code>
 *
 * @author Simon Wacker
 */
class org.as2lib.env.reflect.PropertyInfo extends BasicClass implements TypeMemberInfo {
	
	/** The property info stringifier. */
	private static var stringifier:Stringifier;
	
	/**
	 * Returns the stringifier used to stringify property infos.
	 *
	 * <p>If no custom stringifier has been set via the {@link #setStringifier} method,
	 * an instance of the default {@link PropertyInfoStringifier} class is returned.
	 * 
	 * @return the stringifier that stringifies property infos
	 */
	public static function getStringifier(Void):Stringifier {
		if (!stringifier) stringifier = new PropertyInfoStringifier();
		return stringifier;
	}
	
	/**
	 * Sets the stringifier used to stringify property infos.
	 *
	 * <p>If {@code propertyInfoStringifier} is {@code null} or {@code undefined} the
	 * {@link #getStringifier} method will return the default stringifier.
	 * 
	 * @param propertyInfoStringifier the stringifier that stringifies property infos
	 */
	public static function setStringifier(propertyInfoStringifier:PropertyInfoStringifier):Void {
		stringifier = propertyInfoStringifier;
	}
	
	/** The name of this property. */
	private var name:String;
	
	/** The setter method of this property. */
	private var setter:MethodInfo;
	
	/** The getter method of this property. */
	private var getter:MethodInfo;
	
	/** The type that declares this property. */
	private var declaringType:TypeInfo;
	
	/** A flag representing whether this property is static. */
	private var staticFlag:Boolean;
	
	/**
	 * Constructs a new {@code PropertyInfo} instance.
	 *
	 * <p>All arguments are allowed to be {@code null}. But keep in mind that not all
	 * methods will function properly if one is.
	 * 
	 * <p>If arguments {@code setter} or {@code getter} are not specified they will be
	 * resolved at run-time everytime asked for. Making use of this functionality you
	 * will always get the up-to-date setter or getter.
	 * 
	 * @param name the name of the property
	 * @param declaringType the type declaring the property
	 * @param staticFlag determines whether the property is static
	 * @param setter (optional) the setter method of the property
	 * @param getter (optional) the getter method of the property
	 */
	public function PropertyInfo(name:String,
								 declaringType:TypeInfo,
								 staticFlag:Boolean,
								 setter:Function,
								 getter:Function) {
		this.name = name;
		this.declaringType = declaringType;
		this.staticFlag = staticFlag;
		this.setter = new MethodInfo("__set__" + name, declaringType, staticFlag, setter);
		this.getter = new MethodInfo("__get__" + name, declaringType, staticFlag, getter);
	}
	
	/**
	 * Returns the name of this property.
	 *
	 * <p>If you want the getter or setter methods' name you must use the {@code getName}
	 * method of the {@code getGetter} or {@code getSetter} method respectively. The
	 * name of this getter or setter method is the prefix '__get__' or '__set__' plus
	 * the name of this property.
	 * 
	 * @return the name of this property
	 */
	public function getName(Void):String {
		return name;
	}
	
	/**
	 * Returns the full name of this property.
	 * 
	 * <p>The full name is the fully qualified name of the declaring type plus the name
	 * of this property.
	 *
	 * @return the full name of this property
	 */
	public function getFullName(Void):String {
		if (declaringType.getFullName()) {
			return declaringType.getFullName() + "." + name;
		}
		return name;
	}
	
	/**
	 * Returns the setter method of this property.
	 * 
	 * <p>The setter method of a property takes one argument, that is the new value that
	 * shall be assigned to the property. You can invoke it the same as every other method.
	 *
	 * <p>The name of this setter method is the prefix '__set__' plus the name of this
	 * property.
	 *
	 * <p>Property setter methods are also known under the name implicit setters.
	 * 
	 * @return the setter method of this property
	 */
	public function getSetter(Void):MethodInfo {
		if (setter.getMethod()) {
			return setter;
		}
		return null;
	}
	
	/**
	 * Returns the getter method of this property.
	 * 
	 * <p>The getter method of a property takes no arguments, but returns the value of
	 * the property. You can invoke it the same as every other method.
	 * 
	 * <p>The name of this getter method is the prefix '__get__' plus the name of this
	 * property.
	 *
	 * <p>Property getter methods are also known under the name implicit getters.
	 *
	 * @return the getter method of the property
	 */
	public function getGetter(Void):MethodInfo {
		if (getter.getMethod()) {
			return getter;
		}
		return null;
	}
	
	/**
	 * Returns the type that declares this property.
	 *
	 * <p>At this time interfaces are not allowed to declare properties. The declaring
	 * type is thus allways an instance of type {@link ClassInfo}, a class.
	 * 
	 * @return the type that declares this property
	 */
	public function getDeclaringType(Void):TypeInfo {
		return declaringType;
	}
	
	/**
	 * Returns whether this property is writable.
	 *
	 * <p>This property is writable when its setter is not {@code null}.
	 * 
	 * @return {@code true} if this property is writable else {@code false}
	 */
	public function isWritable(Void):Boolean {
		return (getSetter() != null);
	}
	
	/**
	 * Returns whether this property is readable.
	 *
	 * <p>This property is readable when its getter is not {@code null}.
	 *
	 * @return {@code true} when this property is readable else {@code false}
	 */
	public function isReadable(Void):Boolean {
		return (getGetter() != null);
	}
	
	/**
	 * Returns whether this property is static or not.
	 *
	 * <p>Static properties are properties per type.
	 *
	 * <p>Non-Static properties are properties per instance.
	 *
	 * @return {@code true} if this property is static else {@code false}
	 */
	public function isStatic(Void):Boolean {
		return staticFlag;
	}
	
	/**
	 * Returns a property info that reflects the current state of this property info.
	 * 
	 * @return a snapshot of this property info
	 */
	public function snapshot(Void):PropertyInfo {
		var setter:Function = null;
		if (getSetter()) setter = getSetter().getMethod();
		var getter:Function = null;
		if (getGetter()) getter = getGetter().getMethod();
		return new PropertyInfo(name, declaringType, staticFlag, setter, getter);
	}
	
	/**
	 * Returns the string representation of this property.
	 *
	 * <p>The string representation is obtained via the stringifier returned by the
	 * static {@link #getStringifier} method.
	 * 
	 * @return the string representation of this property
	 */
	public function toString():String {
		return getStringifier().execute(this);
	}
	
}