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

import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.env.overload.Overload;
import org.as2lib.env.reflect.PropertyInfo;
import org.as2lib.env.reflect.ClassInfo;
import org.as2lib.test.speed.AbstractTest;
import org.as2lib.test.speed.Test;
import org.as2lib.test.speed.SimpleTestSuiteResult;
import org.as2lib.test.speed.MethodTestCase;

/**
 * {@code PropertyTestCase} profiles a property.
 * 
 * @author Simon Wacker */
class org.as2lib.test.speed.PropertyTestCase extends AbstractTest implements Test {
	
	/** The property to profile. */
	private var property:PropertyInfo;
	
	/** Test case for the getter method. */
	private var getter:MethodTestCase;
	
	/** Test case for the setter method. */
	private var setter:MethodTestCase;
	
	/**
	 * @overload #PropertyTestCaseByProperty
	 * @overload #PropertyTestCaseByObjectAndName	 */
	public function PropertyTestCase() {
		var o:Overload = new Overload(this);
		o.addHandler([PropertyInfo], PropertyTestCaseByProperty);
		o.addHandler([Object, String], PropertyTestCaseByObjectAndName);
		o.forward(arguments);
	}
	
	/**
	 * Constructs a new {@code PropertyTestCase} by property.
	 * 
	 * <p>If you want to profile a method, referenced from a different scope and with a
	 * different name you can specify thse with the last two arguments. Note that if
	 * specified the method declared on the class will not be profiled but its
	 * reference.
	 * 
	 * @param property the property to profile
	 * @param referenceScope (optional) the scope of the property reference to profile
	 * @param referenceName (optional) the name of the property reference to profile
	 * @throws IllegalArgumentException if the passed-in {@code property} is
	 * {@code null} or {@code undefined}	 */
	public function PropertyTestCaseByProperty(property:PropertyInfo, referenceScope, referenceName:String):Void {
		if (!property) {
			throw new IllegalArgumentException("Argument 'property' [" + property + "] must not be 'null' nor 'undefined'.", this, arguments);
		}
		this.property = property;
		setResult(new SimpleTestSuiteResult(property.getFullName()));
		if (property.getGetter()) {
			this.getter = new MethodTestCase(property.getGetter(), referenceScope, "__get__" + referenceName);
			this.result.addTestResult(this.getter.getResult(NONE));
		}
		if (property.getSetter()) {
			this.setter = new MethodTestCase(property.getSetter(), referenceScope, "__set__" + referenceName);
			this.result.addTestResult(this.getter.getResult(NONE));
		}
	}
	
	/**
	 * Constructs a new {@code PropertyTestCase} by object and property name.
	 * 
	 * @param object the object that declares the property to profile
	 * @param propertyName the name of the property to profile
	 * @throws IllegalArgumentException if there is no property with the given
	 * {@code propertyName} on the given {@code object}	 */
	public function PropertyTestCaseByObjectAndName(object, propertyName:String):Void {
		var c:ClassInfo = ClassInfo.forObject(object);
		if (c.hasProperty(propertyName)) {
			PropertyTestCaseByProperty(c.getPropertyByName(propertyName));
		} else {
			if (!object["__set__" + propertyName] && !object["__get__" + propertyName]) {
				throw new IllegalArgumentException("Property with name [" + propertyName + "] does not exist on object [" + object + "].", this, arguments);
			}
			var setter:Function = object["__set__" + propertyName];
			var getter:Function = object["__get__" + propertyName];
			var p:PropertyInfo = new PropertyInfo(propertyName, c, false, setter, getter);
			PropertyTestCaseByProperty(p, object, propertyName);
		}
	}
	
	/**
	 * Returns the profiled property.
	 * 
	 * @return the profiled property	 */
	public function getProperty(Void):PropertyInfo {
		return this.property;
	}
	
	/**
	 * Runs this property test case.	 */
	public function run(Void):Void {
		this.getter.run();
		this.setter.run();
	}
	
}