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
import org.log4f.logging.LogRecord;

/**
*	A Filter can be used to provide fine grain control over what is logged, beyond the control provided by log levels.
*
*	@author Ralf Siegel
*/
interface org.log4f.logging.IFilter
{
	/**
	*	Check if a given log record should be published. 
	*
	*	@param logRecord A LogRecord
	*	@return true if the log record should be published.
	*/
	public function isLoggable(logRecord:LogRecord):Boolean;
}
