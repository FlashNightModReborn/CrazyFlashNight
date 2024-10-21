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
import org.log4f.logging.IFilter;
import org.log4f.logging.IPublisher;
import org.log4f.logging.Level;
import org.log4f.logging.LogRecord;
import org.log4f.logging.IFormatter;
import org.log4f.logging.DefaultFormatter;

/**
 * Standard implementation of the Logger's framework IPublisher interface.
 * By default the DefaultFormatter is used (this can be overridden by calling
 * setFormatter) to format incoming logging messages, the output of which
 * is passed to the trace() function.  This behavior can be changed in one
 * of two ways: (1) by subclass this class and overriding the publish method;
 * (2) by calling setPublishDelegate() with the Function you wish to use.
 * Note that the Function passed to setPublishDelegate gets the result of
 * the call to the Formatter's format(logRecord) method; if you need to have
 * access to the raw logRecord itself you must choose the subclass-and-override
 * approach.
 *
 * @author Ralf Siegel
 * @author Peter Armstrong
 */
class org.log4f.logging.DefaultPublisher implements IPublisher {
	/**
	 * The IFilter used to filter the results.
	 */
	private var _filter:IFilter;
	
	/**
	 * The IFormatter used to format the results.
	 */
	private var _formatter:IFormatter;
	
	private var _level:Level;
	
	/**
	 * The custom Function to use to publish the LogRecord passed to publish().
	 */
	private var _publishDelegate:Function;
	
	/**
	 * Constructs a new DefaultPublisher with the DefaultFormatter
	 */
	public function DefaultPublisher(Void) {
		setFormatter(new DefaultFormatter());
		_publishDelegate = null;
	}
	
	/**
	 * @param publishDelegate The custom Function to use to publish the
	 * LogRecord passed to publish()
	 */
	public function setPublishDelegate(publishDelegate:Function):Void {
		_publishDelegate = publishDelegate;
	}
	
	/**
	 * @return publishDelegate The custom Function to use to publish the
	 * LogRecord passed to publish()
	 */
	public function getPublishDelegate():Function {
		return _publishDelegate;
	}
		
	/**
	 * @see org.log4f.logging.IPublisher
	 */
	public function publish(logRecord:LogRecord):Void {
		if (isLoggable(logRecord)) {
			var formattedRecord:String = getFormatter().format(logRecord);
			if (_publishDelegate == null) {
				trace(formattedRecord);
			} else {
				_publishDelegate(formattedRecord);
			}
		}
	}
	
	/**
	 * @see org.log4f.logging.IPublisher
	 */
	public function setFilter(filter:IFilter):Void {
		_filter = filter;
	}
	
	/**
	 * @see org.log4f.logging.IPublisher
	 */
	public function getFilter():IFilter {
		return _filter;
	}
	
	/**
	 * @see org.log4f.logging.IPublisher
	 */
	public function setFormatter(formatter:IFormatter):Void {
		_formatter = formatter;
	}

	/**
	 * @see org.log4f.logging.IPublisher
	 */	
	public function getFormatter():IFormatter {
		return _formatter;
	}
	
	/**
	 * @see org.log4f.logging.IPublisher
	 */
	public function setLevel(level:Level):Void {
		_level = level;
	}
	
	/**
	 * @see org.log4f.logging.IPublisher
	 */
	public function getLevel():Level {
		return _level;
	}
	
	/**
	 * @see org.log4f.logging.IPublisher
	 */
	public function isLoggable(logRecord:LogRecord):Boolean {
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
