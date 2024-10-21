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
import org.log4f.logging.Level;
import org.log4f.logging.LogRecord;
import org.log4f.logging.IFilter;
import org.log4f.logging.IFormatter;

/**
*	A publisher takes log messages from a Logger and exports them. 
*	It might for example, write them to the Flash IDE output window or write them to a file, 
*	or send them to a network logging service, or forward them to an OS log, or whatever.
*
*	@author Ralf Siegel
*/
interface org.log4f.logging.IPublisher
{
	/**
	*	Publish a LogRecord. 
	*	The logging request was made initially to a Logger object, which initialized the LogRecord and forwarded it here. 
	*	The Handler is responsible for formatting the message.
	*
	*	@param logRecord The log record to be published
	*/
	public function publish(logRecord:LogRecord):Void;

	/**
	*	Set a filter to control output on this Publisher. 
	*	For each call of publish the Publisher will call this Filter (if it is non-null) to check if the LogRecord should be published or discarded.  
	*
	*	@param A filter object
	*/
	public function setFilter(filter:IFilter):Void;
	
	/**
	*	Get the current filter for this Publisher. 
	*
	*	@return A filter object or undefined.
	*/
	public function getFilter():IFilter;
	
	/**
	*	Set a formatter for this publisher
	*
	*	@param a suitable formatter object
	*/
	public function setFormatter(formatter:IFormatter):Void;

	/**
	*	Gets the formatter currently associated with this publisher
	*
	*	@return the formatter object
	*/	
	public function getFormatter():IFormatter;
	
	/**
	*	Set the log level specifying which message levels will be logged by this Publisher. 
	*	Message levels lower than this value will be discarded.
	*
	*	@param level the new value for the log level 
	*/
	public function setLevel(level:Level):Void;
	
	/**
	*	Get the log level specifying which messages will be logged by this Publisher. 
	*	Message levels lower than this level will be discarded.
	*
	*	@return the level of messages being logged. 
	*/
	public function getLevel():Level;

	/**
	*	Check if this Publisher would actually log a given LogRecord. 
	*	This method checks if the LogRecord has an appropriate Level and whether it satisfies any Filter. 
	*	It also may make other Publisher specific checks that might prevent a publisher from logging the LogRecord. 
	*
	*	@param the LogRecord to be checked
	*	@return true if loggable, otherwise false
	*/
	public function isLoggable(logRecord:LogRecord):Boolean;
}