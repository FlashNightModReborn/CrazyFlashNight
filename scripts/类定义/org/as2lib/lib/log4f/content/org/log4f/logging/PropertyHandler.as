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
import org.log4f.logging.IFilter;
import org.log4f.logging.IPublisher;
import org.log4f.logging.Level;
import org.log4f.logging.Logger;
import org.log4f.logging.LogManager;

import org.log4f.logging.util.Class;

import org.log4f.logging.errors.InvalidLevelError;
import org.log4f.logging.errors.IllegalArgumentError;
import org.log4f.logging.errors.ClassNotFoundError;
import org.log4f.logging.errors.InvalidFormatterError;
import org.log4f.logging.errors.InvalidFilterError;
import org.log4f.logging.errors.InvalidPublisherError;

/**
 * The property handler takes various logging properties and assigns them to
 * the suitable loggers.
 *
 *	@author Ralf Siegel
 */
class org.log4f.logging.PropertyHandler
{
	private static var logger:Logger =
		Logger.getLogger("org.log4f.logging.PropertyHandler");
	
	/**
     * Handles appliable properties for loggers. 
     *
     * Important: If a filter is specified, make sure to import and reference
     * the given class so it can be accessed by the Logger framework
     *
     * @param name the Logger's name string, e.g. "a.b.c"
     * @param level the logging level, e.g. "WARN"
     * @param filter the filter class name, e.g. "com.domain.CustomFilter"
     */
	public function handleLoggerProperties(name:String, level:String, filter:String):Void
	{
		try {		
			Logger.getLogger(name).setLevel(Level.forName(level));
		} catch (e:InvalidLevelError) {
			logger.warn(e.toString());
		} catch (e:IllegalArgumentError) {
			// silently ignore
		}
		
		try {
			Logger.getLogger(name).setFilter(
				LogManager.getNewFilterInstanceByName(filter));
		} catch (e:ClassNotFoundError) {
			logger.warn(e.toString());
		} catch (e:InvalidFilterError) {
			logger.warn(e.toString());
		} catch (e:IllegalArgumentError) {
			// silently ignore
		}
	}
	
	/**
     * Handles appliable properties for publishers. 
	*
	* Important: If a publisher or formatter is specified, make sure to import
	* and reference the given class so it can be accessed by the Logger framework
	*
	*	@param name the Logger's name string, e.g. "a.b.c"
	*	@param publisher the publisher class name, e.g. "com.domain.CustomPublisher"
	*	@param filter the formatter class name, e.g. "com.domain.CustomFormatter"
	*/
	public function handlePublisherProperties(name:String, publisher:String,
		formatter:String, level:String):Void
	{
		var p:IPublisher;
		try {
			p = LogManager.getNewPublisherInstanceByName(publisher);
			Logger.getLogger(name).addPublisher(p);
		} catch (e:ClassNotFoundError) {
			logger.warn(e.toString());
			return;
		} catch (e:InvalidPublisherError) {
			logger.warn(e.toString());
			return;
		} catch (e:IllegalArgumentError) {
			return;
		}
		try {		
			p.setLevel(Level.forName(level));
		} catch (e:InvalidLevelError) {
			logger.warn(e.toString());
		} catch (e:IllegalArgumentError) {
			// silently ignore
		}
		try {
			p.setFormatter(LogManager.getNewFormatterInstanceByName(formatter));
		} catch (e:ClassNotFoundError) {
			logger.warn(e.toString());
		} catch (e:InvalidFormatterError) {
			logger.warn(e.toString());
		} catch (e:IllegalArgumentError) {
			// silently ignore
		}
	}
}