/*
   Copyright 2004 Ralf Siegel and Peter Armstrong

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

/**
 * LogRecord value objects are used to pass logging requests between the
 * logging framework and individual publishers. 
 *
 * @author Ralf Siegel
 * @author Peter Armstrong
 */
class org.log4f.logging.LogRecord
{
	private var date:Date;
	private var loggerName:String;
	private var level:Level;
	private var message:String;
	private var provider:Object;
	
	/**
	*	Construct a LogRecord with the given date, source's logger name, level and message values. 
	*	@param provider An object which is the provider of the debug message
	*/
	public function LogRecord(date:Date, loggerName:String, level:Level,
		message:String, provider:Object)
	{
		this.date = date;
		this.loggerName = loggerName;
		this.level = level;
		this.message = message;
		this.provider = provider;
	}
	
	/**
	*	Get the provider.
	*
	*	@return an object
	*/
	public function getProvider():Object
	{
		return this.provider;
	}

	/**
	*	Get the event date.
	*
	*	@return a Date object
	*/
	public function getDate():Date
	{
		return this.date;
	}
	
	/**
	*	Get the source's logger name
	*
	*	@return the logger name string
	*/
	public function getLoggerName():String
	{
		return this.loggerName;
	}
	
	/**
	*	Get the logging message level, for example Level.SEVERE.
	*
	*	@return the logging message level object
	*/
	public function getLevel():Level
	{
		return this.level;
	}
	
	/**
	*	Get the "raw" log message before formatting. 
	*
	*	@return the raw message string
	*/
	public function getMessage():String
	{
		return this.message;
	}

	/**
	 * Return a String XML fragment of the LogRecord.
	 */	
	public function toString(Void):String {
		return "<logRecord" +
			"\" date=\"" + date.toString() +
			"\" loggerName=\"" + loggerName +
			"\" level=\"" + level +
			"\" message=\"" + message +
			"\" provider=\"" + provider.toString() + "\"/>";
	}	
}