/*
   Copyright 2004 Peter Armstrong

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
import org.log4f.logging.console.DebugModel;

/**
 * This implementation of the Logger's framework IPublisher interface sends
 * incoming logging messages to our debug console.
 * @author Peter Armstrong
 */
class org.log4f.logging.console.DebugModelPublisher implements IPublisher {
	private var filter:IFilter;
	private var level:Level;

	/**
	 * Construct a new DebugModelPublisher.
	 */
	public function DebugModelPublisher() {
	}

	/**
	 * @see logging.IPublisher
	 */	
	public function publish(logRecord:LogRecord):Void {
		if (this.isLoggable(logRecord)) {
			DebugModel.getSharedInstance().addMessage(logRecord);
		}
	}
	
	/**
	 * @see logging.IPublisher
	 */
	public function setFilter(filter:IFilter):Void {
		this.filter = filter;
	}
	
	/**
	 * @see logging.IPublisher
	 */
	public function getFilter():IFilter {
		return this.filter;
	}

	/**
	 * THIS METHOD IS NOT IMPLEMENTED.
	 * @see logging.IPublisher
	 */		
	public function setFormatter(formatter:IFormatter):Void {
	}

	/**
	 * THIS METHOD IS NOT IMPLEMENTED.
	 * @see logging.IPublisher
	 */	
	public function getFormatter():IFormatter {
		return null;
	}
	
	/**
	 * @see logging.IPublisher
	 */
	public function setLevel(level:Level):Void {
		this.level = level;
	}
	
	/**
	 * @see logging.IPublisher
	 */
	public function getLevel():Level {
		return this.level;
	}
	
	/**
	 * @see logging.IPublisher
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