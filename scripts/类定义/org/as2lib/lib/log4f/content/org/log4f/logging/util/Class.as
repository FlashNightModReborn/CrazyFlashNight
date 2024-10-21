/*
   Copyright 2004 Ralf Siegel

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*/
import org.log4f.logging.errors.ClassNotFoundError;
import org.log4f.logging.errors.IllegalArgumentError;

/**
*	@author Ralf Siegel
*	@deprecated will use standard classes if available
*/
class org.log4f.logging.util.Class 
{
	/**
	*	Returns the Function object associated with the class with the given string name.
	*
	*	@return the Function object
	*/
	public static function forName(className:String):Function
	{
		if (className == undefined || className == null) {
			throw new IllegalArgumentError("'" + className + "' is not allowed.");
		}
		var c:Function = eval("_global." + className);
		if ( c == undefined ) {
			throw new ClassNotFoundError(className);
		}
		return c;
	}
}