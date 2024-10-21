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
import org.log4f.logging.DefaultPublisher;
import org.log4f.logging.LogRecord;
import mx.controls.Alert;

/**
 * Publish to Alert.show.
 * @author Peter Armstrong
 */
class org.log4f.logging.AlertPublisher extends DefaultPublisher {
	/**
	 * Constructs a new AlertPublisher with the DefaultFormatter
	 */
	public function AlertPublisher(Void) {
		super();
	}
	
	/**
	 * @see org.log4f.logging.IPublisher
	 */
	public function publish(logRecord:LogRecord):Void {
		if (isLoggable(logRecord)) {
			var formattedRecord:String = getFormatter().format(logRecord);
			Alert.show(formattedRecord, logRecord.getLevel().getName());
		}
	}
}
