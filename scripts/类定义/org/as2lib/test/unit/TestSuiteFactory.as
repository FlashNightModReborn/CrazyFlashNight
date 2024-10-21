/**
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
import org.as2lib.test.unit.Test;
import org.as2lib.test.unit.TestCaseHelper;
import org.as2lib.test.unit.TestSuite;
import org.as2lib.util.ClassUtil;
import org.as2lib.util.AccessPermission;
import org.as2lib.env.reflect.PackageInfo;
import org.as2lib.env.reflect.TypeInfo;

/**
 * Factory to create TestSuites.
 * This factory can be used to create TestSuites that contain all
 * TestCases that are available.
 * 
 * @author Martin Heidegger
 */
class org.as2lib.test.unit.TestSuiteFactory extends BasicClass {
	
	/**
	 * Constructs a new Factory.
	 */
	public function TestSuiteFactory() {}
	
	/**
	 * Collects all TestCases that are available.
	 * 
	 * @return TestSuite that contains all available TestCases.
	 */
	public function collectAllTestCases(Void):TestSuite {
		return collectTestCases(PackageInfo.getRootPackage(), true);
	}
	
	/**
	 * Collects all TestCases by a given package.
	 * 
	 * @param package Package to start with.
	 * @param recursive Recursive Flag.
	 * @return TestSuite that contains all available TestCases.
	 */
	public function collectTestCases(package:PackageInfo, recursive:Boolean):TestSuite {
		var result:TestSuite = new TestSuite("<Generated TestSuite>");
		AccessPermission.set(package, null, AccessPermission.ALLOW_ALL);
		collectAgent(package, result, recursive);
		return result;
	}

	/**
	 * Agent to collect TestCases within a package.
	 * <p>Note: If you want that a class gets blocked from collection simple add
	 * a static method "blockCollecting" that returns true.
	 * 
	 * <p>Example:
	 * <code>
	 *   import org.as2lib.test.unit.TestCase;
	 * 
	 *   class MyTest extends TestCase {
	 *     public static function blockCollecting(Void):Boolean {
	 *	     return true;
	 *     }
	 *   }  
	 * </code>
	 * 
	 * 
	 * @param package Package to search in.
	 * @param suite TestSuite to add the found TestCase.
	 * @param recursive Recursive Flag.
	 */
	private function collectAgent(package:PackageInfo, suite:TestSuite, recursive:Boolean):Void {

		var members:Array = package.getMemberClasses();
		for(var i:Number = 0; i < members.length; i++) {
			var childType:TypeInfo = members[i];
			var child:Function = childType.getType();
			if (
				   ClassUtil.isImplementationOf(child, Test)
				&& child != Test
				&& !child.blockCollecting()
				&& !ClassUtil.isSubClassOf(child, TestCaseHelper)
				&& !ClassUtil.isSubClassOf(child, TestSuite)
				) {
				suite.addTest(Test(ClassUtil.createCleanInstance(child)));
			}
		}
		
		var subPackages:Array = package.getMemberPackages();
		for(var j:Number = 0; j < subPackages.length && recursive; j++) {
			var subPackage:PackageInfo = subPackages[j];
			collectAgent(subPackage, suite, true);
		}
	}
}