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

/**
 * {@code AbstractServerServiceProxy} offers default implementations of some methods
 * needed when implementing the {@link ServerServiceProxy} interface.
 * 
 * @author Simon Wacker
 */
class org.as2lib.io.conn.core.server.AbstractServerServiceProxy extends BasicClass {
	
	/**
	 * Generates a service url with passed-in {@code host} and service {@code path}.
	 * 
	 * <p>If the passed-in {@code host} is {@code null}, {@code undefined} or an empty
	 * string the passed-in {@code path} will be returned unchanged.
	 *
	 * @param host the host of the required service
	 * @param path the path of the required service
	 * @return the generated service url
	 */
	public static function generateServiceUrl(host:String, path:String):String {
		if (!host) return path;
		return host + "/" + path;
	}
	
	/**
	 * Private constructor.
	 */
	private function AbstractServerServiceProxy(Void) {
	}
	
	/**
	 * @overload invokeMethodByNameAndArguments
	 * @overload invokeMethodByNameAndArgumentsAndResponseService
	 * @see ServerServiceProxy#invokeMethod
	 */
	public function invokeMethod():Void {
		var o:Overload = new Overload(this);
		o.addHandler([String, Array], this["invokeMethodByNameAndArguments"]);
		o.addHandler([String, Array, String], this["invokeMethodByNameAndArgumentsAndResponseService"]);
		o.forward(arguments);
	}
	
}