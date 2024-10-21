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
import org.log4f.logging.IFormatter;
import org.log4f.logging.LogRecord;

/**
*	A default formatter implementation.
*
*	@author Ralf Siegel
*/
class org.log4f.logging.DefaultFormatter implements IFormatter
{
	/**
	*	@see logging.IFormatter
	*/
	public function format(logRecord:LogRecord):String
	{
		var formatted:String = "";		
		formatted += logRecord.getDate() + " | " + logRecord.getLoggerName() + newline;
		formatted += "[" + logRecord.getLevel().getName() + "] " + logRecord.getMessage();
		return formatted;
	}
}