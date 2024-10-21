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
import org.log4f.logging.LogRecord;
import org.log4f.logging.IFormatter;
import org.log4f.logging.XMLFormatter;

/**
*	Standard implementation of the Logger's framework IPublisher interface.
*	XML formats incoming logging messages and sends them (traces) to the output window.
*
*	@author Ralf Siegel
*/
class org.log4f.logging.XMLOutput implements IPublisher
{
	private var filter:IFilter;
	private var formatter:IFormatter;
	private var level:Level;

	/**
	*	Constructs a new trace publisher with the standard XML formatter
	*/
	public function XMLOutput() 
	{
		this.setFormatter(new XMLFormatter());
	}

	/**
	*	@see org.log4f.logging.IPublisher
	*/	
	public function publish(logRecord:LogRecord):Void
	{
		if (this.isLoggable(logRecord)) {
			trace(this.getFormatter().format(logRecord));
		}
	}
	
	/**
	*	@see org.log4f.logging.IPublisher
	*/
	public function setFilter(filter:IFilter):Void
	{
		this.filter = filter;
	}
	
	/**
	*	@see org.log4f.logging.IPublisher
	*/
	public function getFilter():IFilter
	{
		return this.filter;
	}

	/**
	*	@see org.log4f.logging.IPublisher
	*/		
	public function setFormatter(formatter:IFormatter):Void
	{
		this.formatter = formatter;
	}

	/**
	*	@see org.log4f.logging.IPublisher
	*/	
	public function getFormatter():IFormatter
	{
		return this.formatter;
	}
	
	/**
	*	@see org.log4f.logging.IPublisher
	*/
	public function setLevel(level:Level):Void
	{
		this.level = level;
	}
	
	/**
	*	@see org.log4f.logging.IPublisher
	*/
	public function getLevel():Level
	{
		return this.level;
	}
	
	/**
	*	@see org.log4f.logging.IPublisher
	*/
	public function isLoggable(logRecord:LogRecord):Boolean
	{
		if (this.getLevel() > logRecord.getLevel()) {
			return false;
		}
		
		if (this.getFilter() == undefined || this.getFilter() == null) {
			return true;
		}
		
		if (this.getFilter().isLoggable(logRecord)) {
			return true;
		}
		
		return false;
	}	
}
