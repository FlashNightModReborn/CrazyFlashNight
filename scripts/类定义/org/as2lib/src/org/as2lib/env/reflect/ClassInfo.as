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
import org.as2lib.util.StringUtil;
import org.as2lib.util.ClassUtil;
import org.as2lib.env.overload.Overload;
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.env.reflect.ClassNotFoundException;
import org.as2lib.env.reflect.ReflectConfig;
import org.as2lib.env.reflect.PackageInfo;
import org.as2lib.env.reflect.TypeInfo;
import org.as2lib.env.reflect.PropertyInfo;
import org.as2lib.env.reflect.MethodInfo;
import org.as2lib.env.reflect.ConstructorInfo;
import org.as2lib.env.reflect.TypeMemberFilter;
import org.as2lib.env.reflect.algorithm.ClassAlgorithm;
import org.as2lib.env.reflect.algorithm.MethodAlgorithm;
import org.as2lib.env.reflect.algorithm.PropertyAlgorithm;

/**
 * {@code ClassInfo} reflects a class and provides methods to get information about
 * that class.
 * 
 * <p>The static search methods {@link #forName}, {@link #forObject}, {@link #forInstance}
 * and {@link #forClass} can be used to get class infos for specific classes.
 * 
 * <p>If you for example want to get information about the class of a specific instance
 * you can retrieve the appropriate {@code ClassInfo} instance and you can then use
 * its methods to get the information you wanted.
 * 
 * <p>Example:
 * <code>
 *   var myInstance:MyClass = new MyClass();
 *   var classInfo:ClassInfo = ClassInfo.forInstance(myInstance);
 *   trace("Class Name: " + classInfo.getFullName());
 *   trace("Super Class Name: " + classInfo.getSuperType().getFullName());
 *   trace("Declared Methods: " + classInfo.getMethods(true));
 *   trace("Declared Properties: " + classInfo.getProperties(true));
 * </code>
 * 
 * <p>Note that right now it is not possible to distinguish between interfaces and
 * classes at run-time. Therefore are both classes and interfaces reflected by
 * {@code ClassInfo} instances. This is going to change as soon is the differentiation
 * is possible.
 * 
 * @author Simon Wacker
 */
class org.as2lib.env.reflect.ClassInfo extends BasicClass implements TypeInfo {
	
	/** The algorithm to find classes. */
	private static var classAlgorithm:ClassAlgorithm;
	
	/** The algorithm to find methods of classes. */
	private static var methodAlgorithm:MethodAlgorithm;
	
	/** The algorithm to find properties of classes. */
	private static var propertyAlgorithm:PropertyAlgorithm;
	
	/**
	 * Returns the class info corresponding to the passed-in fully qualified 
	 * {@code className}.
	 * 
	 * <p>Fully qualified means that {@code className} must consist of the class's 
	 * namespace (preceding package structure) as well as its name. For example
	 * {@code "org.as2lib.core.BasicClass"}.
	 *
	 * <p>This method first checks whether the class info for the class with the given
	 * {@code className} is already contained in the cache and adds it to the cache if
	 * not.
	 * 
	 * @param className the fully qualified class name
	 * @return the class info reflecting the class corresponding to the {@code className}
	 * @throws IllegalArgumentException if the passed-in {@code className} is {@code null},
	 * {@code undefined} or an empty string or if the object corresponding to the
	 * passed-in {@code className} is not of type {@code function}
	 * @throws ClassNotFoundException if a class with the passed-in {@code className}
	 * could not be found
	 */
	public static function forName(className:String):ClassInfo {
		return getClassAlgorithm().executeByName(className);
	}
	
	/**
	 * Returns the class info corresponding to the passed-in {@code object}.
	 * 
	 * <p>If the passed-in {@code object} is of type {@code function} it is supposed
	 * that it is the class you want to get the class info for. Otherwise it is supposed
	 * that the object is an instance of the class you want to get the class info for.
	 *
	 * <p>This method first checks whether the class info for the given class or for the
	 * class of the given instance is already contained in the cache and adds it to the
	 * cache if not.
	 *
	 * @param object the object you want to get the class info for
	 * @return the class info corresponding to the passed-in {@code object}
	 * @throws IllegalArgumentException if the passed-in {@code object} is {@code null}
	 * or {@code undefined}
	 * @throws ClassNotFoundException if the class corresponding to the passed-in
	 * {@code object} could not be found
	 * @see #forClass
	 * @see #forInstance
	 */
	public static function forObject(object):ClassInfo {
		// not '!object' because parameter 'object' could be an empty string
		// 'valueOf' method of 'object' may return 'null' or 'undefined' because of that strict eval is used
		if (object === null || object === undefined) {
			throw new IllegalArgumentException("Argument 'object' [" + object + "] must not be 'null' or 'undefined'.", eval("th" + "is"), arguments);
		}
		var classInfo:ClassInfo = ReflectConfig.getCache().getClass(object);
		if (classInfo) return classInfo;
		// not 'object instanceof Function' because that would include instances
		// of type Function that were created using the new keyword 'new Function()'.
		if (typeof(object) == "function") {
			return forClass(object);
		}
		return forInstance(object);
	}
	
	/**
	 * Returns the class info corresponding to the class of the passed-in
	 * {@code instance}
	 *
	 * <p>This method first checks whether the class info for the class of the given
	 * {@code instance} is already contained in the cache and adds it to the cache if
	 * not.
	 *
	 * @param instance the instance you want to get the class info for
	 * @return the class info reflecting the class of the passed-in {@code instance}
	 * @throws IllegalArgumentException if the passed-in {@code instance} is 
	 * {@code null} or {@code undefined}
	 * @throws ClassNotFoundException if the class corresponding to the passed-in
	 * {@code instance} could not be found
	 */
	public static function forInstance(instance):ClassInfo {
		// not '!instance' because parameter 'instance' could be a blank string
		if (instance === null || instance === undefined) {
			throw new IllegalArgumentException("Argument 'instance' [" + instance + "] must not be 'null' or 'undefined'.", eval("th" + "is"), arguments);
		}
		var classInfo:ClassInfo = ReflectConfig.getCache().getClassByInstance(instance);
		if (classInfo) return classInfo;
		// if the __constructor__ is defined it most probably references the correct class
		if (instance.__constructor__) {
			// check if it really is the correct one
			// it may be incorrect if the __proto__ property was set manually like myInstance.__proto__ = MyClass.prototype
			if (instance.__constructor__.prototype == instance.__proto__) {
				return ReflectConfig.getCache().addClass(new ClassInfo(instance.__constructor__));
			}
		}
		// if the __constructor__ is not defined or is not the correct one the constructor may be correct
		// this is most probably true for MovieClips, TextFields etc. that have been put on the stage without
		// linkage to any other class
		if (instance.constructor) {
			// check if it really is the correct one
			// it may be incorrect if the __proto__ property was set manually like myInstance.__proto__ = MyClass.prototype
			if (instance.constructor.prototype == instance.__proto__) {
				return ReflectConfig.getCache().addClass(new ClassInfo(instance.constructor));
			}
		}
		// if all the above tests do not hold true we must search for the class using the instance
		var info = getClassAlgorithm().executeByInstance(instance);
		// info is null if the class algorithm could not find the appropriate class
		if (info) {
			// Would throwing an exception be more appropriate if any of the following
			// if-statements holds true?
			if (info.name == null) info.name = null;
			if (!info.clazz) info.clazz = null;
			if (!info.package) info.package = null;
			return ReflectConfig.getCache().addClass(new ClassInfo(info.clazz, info.name, info.package));
		}
		throw new ClassNotFoundException("The class corresponding to the passed-in instance '" + instance + "' could not be found.", eval("th" + "is"), arguments);
	}
	
	/**
	 * Returns the class info corresponding to the passed-in {@code clazz}.
	 *
	 * <p>This method first checks whether the class info for the given {@code clazz}
	 * is already contained in the cache and adds it to the cache if not.
	 *
	 * @param clazz the class you want to get the class info for
	 * @return the class info reflecting the passed-in {@code clazz}
	 * @throws IllegalArgumentException if the passed-in {@code clazz} is {@code null}
	 * or {@code undefined}
	 */
	public static function forClass(clazz:Function):ClassInfo {
		if (clazz === null || clazz === undefined) {
			throw new IllegalArgumentException("Argument 'clazz' [" + clazz + "] must not be 'null' or 'undefined'.", eval("th" + "is"), arguments);
		}
		var classInfo:ClassInfo = ReflectConfig.getCache().getClassByClass(clazz);
		if (classInfo) return classInfo;
		return ReflectConfig.getCache().addClass(new ClassInfo(clazz));
	}
	
	/**
	 * Sets the algorithm used to find classes. 
	 *
	 * <p>If the passed-in {@code newClassAlgorithm} is of value {@code null} or
	 * {@code undefined}, the {@link #getClassAlgorithm} method will return the default
	 * class algorithm.
	 *
	 * @param newClassAlgorithm the new class algorithm to find classes
	 * @see #getClassAlgorithm
	 */
	public static function setClassAlgorithm(newClassAlgorithm:ClassAlgorithm):Void {
		classAlgorithm = newClassAlgorithm;
	}
	
	/**
	 * Returns the class algorithm used to find classes.
	 *
	 * <p>Either the algorithm set via the {@link #setClassAlgorithm} method will be
	 * returned or the default one which is an instance of class {@link ClassAlgorithm}.
	 *
	 * @return the set or the default class algorithm
	 * @see #setClassAlgorithm
	 */
	public static function getClassAlgorithm(Void):ClassAlgorithm {
		if (!classAlgorithm) classAlgorithm = new ClassAlgorithm();
		return classAlgorithm;
	}
	
	/**
	 * Sets the algorithm used to find methods.
	 *
	 * <p>If the passed-in {@code newMethodAlgorithm} is of value {@code null} or
	 * {@code undefined}, the {@link #getMethodAlgorithm} method will return the
	 * default method algorithm.
	 *
	 * @param newMethodAlgorithm the new method algorithm to find methods
	 * @see #getMethodAlgorithm
	 */
	public static function setMethodAlgorithm(newMethodAlgorithm:MethodAlgorithm):Void {
		methodAlgorithm = newMethodAlgorithm;
	}
	
	/**
	 * Returns the method algorithm used to find methods.
	 *
	 * <p>Either the algorithm set via the {@link #setMethodAlgorithm} method will be
	 * returned or the default one which is an instance of class {@link MethodAlgorithm}.
	 *
	 * @return the set or the default method algorithm
	 * @see #setMethodAlgorithm
	 */
	public static function getMethodAlgorithm(Void):MethodAlgorithm {
		if (!methodAlgorithm) methodAlgorithm = new MethodAlgorithm();
		return methodAlgorithm;
	}
	
	/**
	 * Sets the algorithm used to find properties.
	 *
	 * <p>If the passed-in {@code newPropertyAlgorithm} is of value {@code null} or
	 * {@code undefined}, the {@link #getPropertyAlgorithm} method will return the
	 * default property algorithm.
	 *
	 * @param newPropertyAlgorithm the new property algorithm to find properties
	 * @see #getPropertyAlgorithm
	 */
	public static function setPropertyAlgorithm(newPropertyAlgorithm:PropertyAlgorithm):Void {
		propertyAlgorithm = newPropertyAlgorithm;
	}
	
	/**
	 * Returns the property algorithm used to find properties.
	 *
	 * <p>Either the algorithm set via the {@link #setPropertyAlgorithm} method will
	 * be returned or the default one which is an instance of class
	 * {@link PropertyAlgorithm}.
	 *
	 * @return the set or the default property algorithm
	 * @see #setPropertyAlgorithm
	 */
	public static function getPropertyAlgorithm(Void):PropertyAlgorithm {
		if (!propertyAlgorithm) propertyAlgorithm = new PropertyAlgorithm();
		return propertyAlgorithm;
	}
	
	/** The name of the reflected class. */
	private var name:String;
	
	/** The fully qualified name of the reflected class. */
	private var fullName:String;
	
	/** The reflected class. */
	private var clazz:Function;
	
	/** The super class of the reflected class. */
	private var superClass:ClassInfo;
	
	/** The package the reflected class is a member of. */
	private var package:PackageInfo;
	
	/** The methods the reflected class declares. */
	private var methods:Array;
	
	/** The properties the reflected class declares. */
	private var properties:Array;
	
	/** The constructor of the reflected class. */
	private var classConstructor:ConstructorInfo;
	
	/**
	 * Constructs a new {@code ClassInfo} instance.
	 *
	 * <p>Note that the argument {@code clazz} is not mandatorily necessary, although
	 * most of the methods cannot do their job correctly if it is {@code null} or
	 * {@code undefined}.
	 * 
	 * <p>If you do not pass-in the {@code name} or the {@code package} they will be
	 * resolved lazily when requested using the passed-in {@code clazz}.
	 *
	 * @param clazz the class this new class info reflects
	 * @param name (optional) the name of the reflected class
	 * @param package (optional) the package the reflected class is a member of
	 */
	public function ClassInfo(clazz:Function,
							  name:String,
							  package:PackageInfo) {
		this.clazz = clazz;
		this.name = name;
		this.package = package;
	}
	
	/**
	 * Returns the name of the represented class without its namespace.
	 *
	 * <p>The namespace is the package path to the class. The namespace of the class
	 * 'org.as2lib.core.BasicClass' is 'org.as2lib.core'. In this example this method
	 * would only return 'BasicClass'.
	 *
	 * @reutrn the name of the represented class
	 * @see #getFullName
	 */
	public function getName(Void):String {
		if (name === undefined) initNameAndPackage();
		return name;
	}
	
	/**
	 * Returns the fully qualified name of the represented class. That means the name
	 * of the class plus its package path, namespace.
	 * 
	 * <p>The path will not be included if:
	 * <ul>
	 *   <li>The {@link #getPackage} method returns {@code null} or {@code undefined}.</li>
	 *   <li>
	 *     The {@code isRoot} method of the package returned by {@link #getPackage}
	 *     returns {@code true}.
	 *   </li>
	 * </ul>
	 *
	 * @return the fully qualified name of the represented class
	 * @see #getName
	 */
	public function getFullName(Void):String {
		if (fullName === undefined) {
			if (getPackage().isRoot() || !getPackage()) {
				return (fullName = getName());
			}
			fullName = getPackage().getFullName() + "." + getName();
		}
		return fullName;
	}
	
	/**
	 * Returns the actual class this class info represents.
	 *
	 * @return the represented class
	 */
	public function getType(Void):Function {
		// TODO: find better way to keep concrete class up-to-date
		// problems are that package and name must be resolved event if no update was made
		// and that snapshots are not possible
		/*if (getPackage().getPackage() !== undefined
				&& getPackage().getPackage() !== null
				&& getName() != null) {
			return getPackage().getPackage()[getName()];
		}*/
		return clazz;
	}
	
	/**
	 * Returns the class's constructor representation.
	 * 
	 * <p>You can use the returned constructor info to get the actual 
	 * constructor. Note that the constructor in Flash is by default the same as the
	 * class. Thus the function returned by the {@link #getType} method and the
	 * {@code getMethod} method of the returned constructor is the same, if you did not
	 * overwrite the constructor manually after this instance was created.
	 *
	 * @return the constructor of the class
	 */
	public function getConstructor(Void):ConstructorInfo {
		if (classConstructor === undefined) {
			classConstructor = new ConstructorInfo(this);
		}
		return classConstructor;
	}
	
	/**
	 * Returns the super class of the class this instance represents.
	 *
	 * <p>The returned instance is of type {@code ClassInfo} and can thus be casted to
	 * this type.
	 *
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The represented class is {@code Object}.</li>
	 *   <li>The represented class has no prototype.</li>
	 *   <li>The static {@link #forInstance} method returns {@code null}.</li>
	 * </ul>
	 *
	 * @return the super class of the class this instance represents or {@code null}
	 */
	public function getSuperType(Void):TypeInfo {
		if (superClass === undefined) {
			if (clazz.prototype.__proto__) {
				superClass = forInstance(clazz.prototype);
			} else {
				superClass = null;
			}
		}
		return superClass;
	}
	
	/**
	 * Creates a new instance of the represented class passing the constructor
	 * arguments.
	 *
	 * <p>{@code null} will be returned if the {@link #getType} method returns
	 * {@code null} or {@code undefined}.
	 *
	 * @param .. any number of arguments to pass-to the constructor on creation
	 * @return a new instance of this class
	 */
	public function newInstance() {
		return ClassUtil.createInstance(getConstructor().getMethod(), arguments);
	}
	
	/**
	 * Returns the package the represented class is a member of.
	 *
	 * <p>The package of the class {@code org.as2lib.core.BasicClass} is
	 * {@code org.as2lib.core}.
	 *
	 * @return the package the represented class is a member of
	 */
	public function getPackage(Void):PackageInfo {
		if (package === undefined) initNameAndPackage();
		return package;
	}
	
	/**
	 * Initializes the name and the package of the represented class.
	 *
	 * <p>This is done using the result of an execution of the class algorithm returned
	 * by the static {@link #getClassAlgorithm} method.
	 */
	private function initNameAndPackage(Void):Void {
		var info = getClassAlgorithm().executeByClass(clazz);
		if (name === undefined) name = info.name == null ? null : info.name;
		if (package === undefined) package = info.package == null ? null : info.package;
	}
	
	/**
	 * Returns whether this class or any super-class implements a method with the
	 * passed-in {@code methodName}.
	 *
	 * <p>Static methods are not filtered by default. That means {@code filterStaticMethods}
	 * is by default set to {@code false}.
	 *
	 * <p>If the passed-in {@code methodName} is {@code null} or {@code undefined},
	 * {@code false} will be returned.
	 *
	 * @param methodName the name of the method to search for
	 * @param filterStaticMethods (optional) determines whether static methods are
	 * filtered, that means excluded from the search
	 * @return {@code true} if the method exists else {@code false}
	 */
	public function hasMethod(methodName:String, filterStaticMethods:Boolean):Boolean {
		if (methodName == null) return false;
		if (filterStaticMethods == null) filterStaticMethods = false;
		if (clazz.prototype[methodName]) return true;
		if (filterStaticMethods) return false;
		if (clazz[methodName]) return true;
		var superClass:TypeInfo = getSuperType();
		while (superClass) {
			if (superClass.getType()[methodName]) {
				return true;
			}
			superClass = superClass.getSuperType();
		}
		return false;
	}
	
	/**
	 * @overload #getMethodsByFlag
	 * @overload #getMethodsByFilter
	 */
	public function getMethods():Array {
		var o:Overload = new Overload(this);
		o.addHandler([], getMethodsByFlag);
		o.addHandler([Boolean], getMethodsByFlag);
		o.addHandler([TypeMemberFilter], getMethodsByFilter);
		return o.forward(arguments);
	}
	
	/**
	 * Returns an array containing the methods represented by {@link MethodInfo}
	 * instances this type declares and maybe the ones of the super-classes.
	 *
	 * <p>The super-classes' methods are included if you {@code filterSuperTypes} is
	 * {@code false}, {@code null} or {@code undefined} and excluded/filtered if it is
	 * {@code true}. This means that by default super-classes are not filtered.
	 *
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The {@link #getType} method returns {@code null} or {@code undefined}.</li>
	 *   <li>The method algorithm returns {@code null} or {@code undefined}.</li>
	 * </ul>
	 *
	 * @param filterSuperClasses (optional) determines whether the super classes' methods
	 * shall be excluded/filtered
	 * @return an array containing the methods
	 */
	public function getMethodsByFlag(filterSuperClasses:Boolean):Array {
		if (!clazz) return null;
		if (methods === undefined) {
			methods = getMethodAlgorithm().execute(this);
		}
		var result:Array = methods.concat();
		if (!filterSuperClasses) {
			if (getSuperType() != null) {
				result = result.concat(getSuperType().getMethodsByFlag(filterSuperClasses));
			}
		}
		return result;
	}
	
	/**
	 * Returns an array that contains the methods represented by {@link MethodInfo}
	 * instances, this class and super classes' declare, that are not filtered/excluded.
	 *
	 * <p>The {@link TypeMemberFilter#filter} method of the passed-in {@code methodFilter}
	 * is invoked for every method to determine whether it shall be contained in the
	 * result. The passed-in argument is of type {@code MethodInfo}.
	 * 
	 * <p>If the passed-in {@code methodFilter} is {@code null} or {@code undefined}
	 * the result of an invocation of the {@link #getMethodsByFlag} method with
	 * argument {@code false} will be returned.
	 *
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The {@link #getType} method returns {@code null} or {@code undefined}.</li>
	 *   <li>
	 *     The {@link #getMethodsByFlag} method returns {@code null} or {@code undefined}.
	 *   </li>
	 * </ul>
	 *
	 * @param methodFilter the filter that filters unwanted methods out
	 * @return an array containing the declared methods that are not filtered, an empty
	 * array if no methods are declared or all were filtered or {@code null}
	 */
	public function getMethodsByFilter(methodFilter:TypeMemberFilter):Array {
		if (!clazz) return null;
		if (!methodFilter) return getMethodsByFlag(false);
		var result:Array = getMethodsByFlag(methodFilter.filterSuperTypes());
		for (var i:Number = 0; i < result.length; i++) {
			if (methodFilter.filter(result[i])) {
				result.splice(i, 1);
				i--;
			}
		}
		return result;
	}
	
	/**
	 * @overload #getMethodByName
	 * @overload #getMethodByMethod
	 */
	public function getMethod():MethodInfo {
		var overload:Overload = new Overload(this);
		overload.addHandler([String], getMethodByName);
		overload.addHandler([Function], getMethodByMethod);
		return overload.forward(arguments);
	}
	
	/**
	 * Returns the method info corresponding to the passed-in {@code methodName}.
	 *
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The passed-in {@code methodName} is {@code null} or {@code undefined}.</li>
	 *   <li>
	 *     A method with the given {@code methodName} is not declared in the represented
	 *     class or any super class.
	 *   </li>
	 * </ul>
	 * 
	 * <p>If this class overwrites a method of any super class the, {@code MethodInfo}
	 * instance of the overwriting method will be returned.
	 *
	 * <p>The declaring type of the returned method info is not always the one
	 * represented by this class. It can also be a super class of it.
	 *
	 * @param methodName the name of the method to return
	 * @return a method info representing the method corresponding to the {@code methodName}
	 */
	public function getMethodByName(methodName:String):MethodInfo {
		if (methodName == null) return null;
		if (getMethodsByFlag(true)) {
			if (methods[methodName]) return methods[methodName];
		}
		if (getSuperType()) return getSuperType().getMethodByName(methodName);
		return null;
	}
	
	/**
	 * Returns the method info corresponding to the passed-in {@code concreteMethod}.
	 *
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The passed-in {@code concreteMethod} is {@code null} or {@code undefined}.</li>
	 *   <li>
	 *     A method matching the given {@code concreteMethod} cannot be found on the
	 *     represented class or any super class.
	 *   </li>
	 * </ul>
	 *
	 * <p>The declaring class of the returned method info is not always the one
	 * represented by this class. It can also be a super class of it.
	 *
	 * @param concreteMethod the concrete method the method info shall be returned for
	 * @return the method info thate represents the passed-in {@code concreteMethod}
	 */
	public function getMethodByMethod(concreteMethod:Function):MethodInfo {
		if (!concreteMethod) return null;
		var methodArray:Array = getMethodsByFlag(true);
		if (methodArray) {
			var l:Number = methodArray.length;
			for (var i:Number = 0; i < l; i = i-(-1)) {
				var method:MethodInfo = methodArray[i];
				if (method.getMethod().valueOf() == concreteMethod.valueOf()) {
					return method;
				}
			}
		}
		if (getSuperType()) return getSuperType().getMethodByMethod(concreteMethod);
		return null;
	}
	
	/**
	 * Returns whether this class or any super-class implements a property with the
	 * passed-in {@code propertyName}.
	 *
	 * <p>Static properties are not filtered by default. That means {@code filterStaticProperties}
	 * is by default set to {@code false}.
	 *
	 * <p>If the passed-in {@code propertyName} is {@code null} or {@code undefined},
	 * {@code false} will be returned.
	 *
	 * @param propertyName the name of the property to search for
	 * @param filterStaticProperties (optional) determines whether static properties are
	 * filtered, that means excluded from the search
	 * @return {@code true} if the property exists else {@code false}
	 */
	public function hasProperty(propertyName:String, filterStaticProperties:Boolean):Boolean {
		if (propertyName == null) return false;
		if (filterStaticProperties == null) filterStaticProperties = false;
		if (clazz.prototype["__get__" + propertyName]) return true;
		if (clazz.prototype["__set__" + propertyName]) return true;
		if (filterStaticProperties) return false;
		if (clazz[propertyName]) return true;
		var superClass:TypeInfo = getSuperType();
		while (superClass) {
			if (superClass.getType()["__set__" + propertyName]
					|| superClass.getType()["__get__" + propertyName]) {
				return true;
			}
			superClass = superClass.getSuperType();
		}
		return false;
	}
	
	/**
	 * @overload #getPropertiesByFlag
	 * @overload #getPropertiesByFilter
	 */
	public function getProperties():Array {
		var o:Overload = new Overload(this);
		o.addHandler([], getPropertiesByFlag);
		o.addHandler([Boolean], getPropertiesByFlag);
		o.addHandler([TypeMemberFilter], getPropertiesByFilter);
		return o.forward(arguments);
	}
	
	/**
	 * Returns an array containing the properties represented by {@link PropertyInfo}
	 * instances this class declares and maybe the ones of the super-classes.
	 *
	 * <p>The super-classes' properties are included if {@code filterSuperClasses} is
	 * {@code false}, {@code null} or {@code undefined} and excluded/filtered if it is
	 * {@code true}. This means that super-classes are by default not filtered.
	 *
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The {@link #getType} method returns {@code null} or {@code undefined}.</li>
	 *   <li>The property algorithm returns {@code null} or {@code undefined}.</li>
	 * </ul>
	 *
	 * @param filterSuperClasses (optional) determines whether the super classes' 
	 * properties shall be excluded/filtered
	 * @return an array containing the properties
	 */
	public function getPropertiesByFlag(filterSuperClasses:Boolean):Array {
		if (!clazz) return null;
		if (properties === undefined) {
			properties = getPropertyAlgorithm().execute(this);
		}
		var result:Array = properties.concat();
		if (!filterSuperClasses) {
			if (getSuperType() != null) {
				result = result.concat(ClassInfo(getSuperType()).getPropertiesByFlag(filterSuperClasses));
			}
		}
		return result;
	}
	
	/**
	 * Returns an array containing the properties represented by {@link PropertyInfo}
	 * instances this class and super classes' declare that are not filtered/excluded.
	 *
	 * <p>The {@link TypeMemberFilter#filter} method of the passed-in {@code propertyFilter}
	 * is invoked for every property to determine whether it shall be contained in the
	 * result.
	 *
	 * <p>If the passed-in {@code propertyFilter} is {@code null} or {@code undefined}
	 * the result of the invocation of {@link #getPropertiesByFlag} with argument 
	 * {@code false} will be returned.
	 *
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The {@link #getType} method returns {@code null} or {@code undefined}.</li>
	 *   <li>The property algorithm returns {@code null} or {@code undefined}.</li>
	 * </ul>
	 *
	 * @param propertyFilter the filter that filters unwanted properties out
	 * @return an array containing the remaining properties
	 */
	public function getPropertiesByFilter(propertyFilter:TypeMemberFilter):Array {
		if (!clazz) return null;
		if (!propertyFilter) return getPropertiesByFlag(false);
		var result:Array = getPropertiesByFlag(propertyFilter.filterSuperTypes());
		for (var i:Number = 0; i < result.length; i++) {
			if (propertyFilter.filter(PropertyInfo(result[i]))) {
				result.splice(i, 1);
				i--;
			}
		}
		return result;
	}
	
	/**
	 * @overload #getPropertyByName
	 * @overload #getPropertyByProperty
	 */
	public function getProperty():PropertyInfo {
		var overload:Overload = new Overload(this);
		overload.addHandler([String], getPropertyByName);
		overload.addHandler([Function], getPropertyByProperty);
		return overload.forward(arguments);
	}
	
	/**
	 * Returns the property info corresponding to the passed-in {@code propertyName}.
	 *
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The passed-in {@code propertyName} is {@code null} or {@code undefined}.</li>
	 *   <li>
	 *     A property with the given {@code propertyName} does not exist on the
	 *     represented class or any super class.
	 *   </li>
	 * </ul>
	 *
	 * <p>If this class overwrites a property of any super class the {@code PropertyInfo}
	 * instance of the overwriting property will be returned.
	 *
	 * <p>The declaring class of the returned property info is not always the one
	 * represented by this class. It can also be a super class of it.
	 *
	 * @param propertyName the name of the property you wanna obtain
	 * @return the property info correspoinding to the passed-in {@code propertyName}
	 */
	public function getPropertyByName(propertyName:String):PropertyInfo {
		if (propertyName == null) return null;
		if (getPropertiesByFlag(true)) {
			if (properties[propertyName]) return properties[propertyName];
		}
		if (getSuperType()) return ClassInfo(getSuperType()).getPropertyByName(propertyName);
		return null;
	}
	
	/**
	 * Returns the property info corresponding to the passed-in {@code concreteProperty}.
	 *
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>The passed-in {@code concreteProperty} is {@code null} or {@code undefined}.</li>
	 *   <li>
	 *     A property corresponding to the passed-in {@code concreteProperty} cannot
	 *     be found on the represented class or any super class.
	 *   </li>
	 * </ul>
	 *
	 * <p>The declaring class of the returned property info is not always the one
	 * represented by this class. It can also be a super class of it.
	 *
	 * @param concreteProperty the concrete property to return the corresponding
	 * property info for
	 * @return the property info correspoinding to the passed-in {@code concreteProperty}
	 */
	public function getPropertyByProperty(concreteProperty:Function):PropertyInfo {
		if (concreteProperty == null) return null;
		var propertyArray:Array = getPropertiesByFlag(true);
		if (propertyArray) {
			var l:Number = propertyArray.length;
			for (var i:Number = 0; i < l; i++) {
				var property:PropertyInfo = propertyArray[i];
				if (property.getGetter().getMethod().valueOf() == concreteProperty.valueOf()
						|| property.getSetter().getMethod().valueOf() == concreteProperty.valueOf()) {
					return property;
				}
			}
		}
		if (getSuperType()) return ClassInfo(getSuperType()).getPropertyByProperty(concreteProperty);
		return null;
	}
	
	/**
	 * Returns the string representation of this instance.
	 * 
	 * <p>The string representation is constructed as follows:
	 * <pre>
	 *   [reflection fullyQualifiedNameOfReflectedType]
	 * </pre>
	 * 
	 * @param displayContent (optional) a {@code Boolean} that determines whether to
	 * render all methods {@code true} or not {@code false}
	 * @return this instance's string representation	 */
	public function toString():String {
		var result:String = "[reflection " + getFullName();
		if (arguments[0] == true) {
			var methods:Array = getMethods();
			for (var i:Number = 0; i < methods.length; i++) {
				result += "\n" + StringUtil.addSpaceIndent(methods[i].toString(), 2);
			}
			if (methods.length > 0) {
				result += "\n";
			}
		}
		return (result + "]");
	}
	
}