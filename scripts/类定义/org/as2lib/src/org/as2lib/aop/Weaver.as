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

import org.as2lib.core.BasicInterface;

/**
 * {@code Weaver} is responsible for weaving the aspect-oriented code into the affected
 * join points.
 * 
 * @author Simon Wacker
 * @see <a href="http://www.simonwacker.com/blog/archives/000040.php">AOP - Aspect-Oriented Programming</a>
 */
interface org.as2lib.aop.Weaver extends BasicInterface {
	
	/**
	 * Weaves the aspect-oriented code into the affected join points.
	 */
	public function weave(Void):Void;
	
}