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
*	A Formatter provides support for formatting LogRecords.
*
*	Typically each Publisher will have a Formatter associated with it. The Formatter takes a LogRecord and converts it to a string. 
*
*	@author Ralf Siegel
*/
interface org.log4f.logging.IFormatter
{
	/**
	*	Format the given log record and return the formatted string. 
	*
	*	@param logRecord The log record to be formatted. 
	*	@return The formatted log record as string.
	*/
	public function format(logRecord:LogRecord):String;
}