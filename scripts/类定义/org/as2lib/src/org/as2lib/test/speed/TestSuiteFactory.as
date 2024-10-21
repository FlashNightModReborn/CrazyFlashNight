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
import org.as2lib.env.overload.Overload;
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.env.reflect.PackageInfo;
import org.as2lib.env.reflect.ClassInfo;
import org.as2lib.env.reflect.MethodInfo;
import org.as2lib.test.speed.TestSuite;
import org.as2lib.test.speed.MethodTestCase;

/**
 * {@code TestSuiteFactory} collects test suites.
 * 
 * @author Simon Wacker */
class org.as2lib.test.speed.TestSuiteFactory extends BasicClass {
	
	/**
	 * Constructs a new {@code TestSuiteFactory} instance.	 */
	public function TestSuiteFactory(Void) {
	}
	
	/**
	 * @overload #collectAllTestCases
	 * @overload #collectTestCasesByPackage
	 * @overload #collectTestCasesByClass	 */
	public function collectTestCases():TestSuite {
		var o:Overload = new Overload(this);
		o.addHandler([], collectAllTestCases);
		o.addHandler([PackageInfo], collectTestCasesByPackage);
		o.addHandler([ClassInfo], collectTestCasesByClass);
		return o.forward(arguments);
	}
	
	/**
	 * Collects all methods and properties as test cases except the ones declared by
	 * {@code Object}.
	 * 
	 * @return a test suite that contains all tests	 */
	public function collectAllTestCases(Void):TestSuite {
		return collectTestCases(PackageInfo.getRootPackage());
	}
	
	/**
	 * Collects all methods and properties of the given {@code package} and all
	 * sub-packages as test cases except the ones declared by {@code Object}.
	 * 
	 * @param package the package to begin the collection at
	 * @return a test suite that contains all collected tests	 */
	public function collectTestCasesByPackage(package:PackageInfo):TestSuite {
		if (!package) throw new IllegalArgumentException("Argument 'package' [" + package + "] must not be 'null' nor 'undefined'.", this, arguments);
		var r:TestSuite = new TestSuite(package.getFullName());
		var ca:Array = package.getMemberClasses();
		for (var i:Number = 0; i < ca.length; i++) {
			r.addTest(collectTestCasesByClass(ca[i]));
		}
		var pa:Array = package.getMemberPackages();
		for (var i:Number = 0; i < pa.length; i++) {
			r.addTest(collectTestCasesByPackage(pa[i]));
		}
		return r;
	}
	
	/**
	 * Collects all methods and properties of the given class as test cases.
	 * Methods and properties of super-classes are not included.
	 * 
	 * @param clazz the class to collect the methods and properties of
	 * @return a test suite that contains all collected tests	 */
	public function collectTestCasesByClass(clazz:ClassInfo):TestSuite {
		var r:TestSuite = new TestSuite(clazz.getFullName());
		r.addTest(clazz.getConstructor());
		var p = clazz.getType().prototype;
		if (p.__constructor__) {
			var c:Function = p.__constructor__;
			var m:MethodInfo = ClassInfo(clazz.getSuperType()).getConstructor();
			if (c != m.getMethod()) {
				p.__constructor__ = m.getMethod();
			}
			// this does actually collect a refernce to the super-type's constructor that is needed for super calls
			// this is thus not actually part of the class
			r.addTest(new MethodTestCase(m, p, "__constructor__"));
		}
		var ma:Array = clazz.getMethods(true);
		for (var k:Number = 0; k < ma.length; k++) {
			r.addTestByMethod(ma[k]);
		}
		var pa:Array = clazz.getProperties(true);
		for (var k:Number = 0; k < pa.length; k++) {
			r.addTestByProperty(pa[k]);
		}
		return r;
	}
	
}