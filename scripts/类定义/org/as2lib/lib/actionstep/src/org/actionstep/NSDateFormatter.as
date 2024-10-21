/*
 * Copyright (c) 2005, InfoEther, Inc.
 * All rights reserved.
 *
 * Copyright (c) 2005, Affinity Systems
 * All rights reserved.
 * 
 * Redistribution and use in source and binary forms, with or without modification, 
 * are permitted provided that the following conditions are met:
 * 
 * 1) Redistributions of source code must retain the above copyright notice, 
 *    this list of conditions and the following disclaimer.
 *  
 * 2) Redistributions in binary form must reproduce the above copyright notice, 
 *    this list of conditions and the following disclaimer in the documentation 
 *    and/or other materials provided with the distribution. 
 * 
 * 3) The name InfoEther, Inc. and Affinity Systems may not be used to endorse or promote products  
 *    derived from this software without specific prior written permission. 
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" 
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE 
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE 
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE 
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN 
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) 
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE 
 * POSSIBILITY OF SUCH DAMAGE.
 */

import org.actionstep.NSArray;
import org.actionstep.NSCalendarDate;
import org.actionstep.NSDate;
import org.actionstep.NSDictionary;
import org.actionstep.NSUserDefaults;

/**
 *
 *
 * @author Scott Hyndman
 */
class org.actionstep.NSDateFormatter extends org.actionstep.NSFormatter
{	
	//
	// For parsing and formatting.
	//
	private static var ASFormatChar:Number = 0;
	private static var ASWord:Number = 1;
	private static var ASSpaceChar:Number = 2;
	
	private static var g_types:Object;
	
	//
	// Behaviour
	//	
	private var m_allowsNaturalLang:Boolean;
	private var m_genCalDates:Boolean;
	private var m_isLenient:Boolean;
	
	//
	// Attributes
	//
	private var m_format:String;
	private var m_attributes:NSDictionary;
	
	//******************************************************															 
	//*                   Construction
	//******************************************************
	
	/**
	 * Creates a new instance of NSDateFormatter.
	 */
	public function NSDateFormatter()
	{	
		m_allowsNaturalLang = false;
		m_attributes = (new NSDictionary()).initWithDictionaryCopyItems
			(NSUserDefaults.standardUserDefaults().
			dictionaryRepresentation(), true);
	}
	
	
	/**
	 * Initializes the date formatter with a format string and
	 * a flag that indicates whether or not to allow natural language.
	 */
	public function initWithDateFormatAllowNaturalLanguage(format:String, 
		flag:Boolean):NSDateFormatter
	{
		m_format = format;
		m_allowsNaturalLang = flag;
		return this;
	}
	
	//******************************************************															 
	//*                    Properties
	//******************************************************
	
	/** Returns the symbol used to represent AM. */
	public function AMSymbol():String
	{
		return m_attributes.objectForKey(NSUserDefaults.NSAMPMDesignation)
			.objectAtIndex(0);
	}
	
	
	/** Sets the symbol used to represent AM. */
	public function setAMSymbol(symbol:String):Void
	{
		m_attributes.objectForKey(NSUserDefaults.NSAMPMDesignation)
			.replaceObjectAtIndexWithObject(0, symbol);
	}
	
	
	/**
	 * Returns the format string used to convert dates to strings and strings
	 * to dates.
	 */
	public function dateFormat():String
	{
		return m_format;
	}
	
	
	/**
	 * Sets the format string used to convert between dates and strings and 
	 * strings and dates.
	 */
	public function setDateFormat(format:String):Void
	{
		m_format = format;
	}
	
	
	/** Returns the symbol used to represent PM. */
	public function PMSymbol():String
	{
		return m_attributes.objectForKey(NSUserDefaults.NSAMPMDesignation)
			.objectAtIndex(1);
	}
	
	
	/** Sets the symbol used to represent PM. */
	public function setPMSymbol(symbol:String):Void
	{
		m_attributes.objectForKey(NSUserDefaults.NSAMPMDesignation)
			.replaceObjectAtIndexWithObject(1, symbol);
	}
	
	
	/**
	 * @see org.actionstep.NSObject#description
	 */
	public function description():String 
	{
		return "NSDateFormatter()";
	}
	
	//******************************************************															 
	//*               Behaviour Properties
	//******************************************************
	
	/**
	 * Returns TRUE if the formatter supports natural language strings
	 * ("now", "yesterday", "tomorrow", ect.) when generating dates from 
	 * strings.
	 */
	public function allowsNaturalLanguage():Boolean
	{
		return m_allowsNaturalLang;
	}


	/**
	 * Returns whether the date formatter returns generates calendar dates
	 * instead of dates.
	 */
	public function generatesCalendarDates():Boolean
	{
		return m_genCalDates;
	}
	
	
	/**
	 * Sets whether the date formatter generates calendar dates. If flag is
	 * TRUE, it will. If FALSE, NSDates will be generated.
	 *
	 * @see org.actionstep.NSDateFormatter#dateFromString()
	 */
	public function setGeneratesCalendarDates(flag:Boolean):Void
	{
		m_genCalDates = flag;
	}
	
	
	public function isLenient():Boolean
	{
		return m_isLenient;
	}
	
	
	public function setLenient(flag:Boolean):Void
	{
		m_isLenient = flag;
	}
	
	//******************************************************															 
	//*             Date to String Conversion
	//******************************************************
	
	/**
	 * Calls stringFromDate if value is an NSDate.
	 *
	 * @see org.actionstep.NSFormatter#stringForObjectValue
	 * @see org.actionstep.NSDateFormatter#stringFromDate
	 */
	public function stringForObjectValue(value:Object):String 
	{
		if (!(value instanceof NSDate))
		{
			return null;
		}
		
		return stringFromDate(NSDate(value));
	}
	
		
	/**
	 * Returns a string representation of date based on this formatter's 
	 * current settings.
	 */
	public function stringFromDate(date:NSDate):String
	{
		return formatDate(dateFormat(), date, null);
	}
		
	//******************************************************															 
	//*             String to Date Conversion
	//******************************************************
	
	/**
	 * Calls dateFromString().
	 *
	 * @see org.actionstep.NSFormatter#getObjectValueForStringErrorDescription
	 * @see org.actionstep.NSDateFormatter#dateFromString
	 */
	public function getObjectValueForStringErrorDescription(string:String):Object
	{
		var ret:Object = new Object();
		var dt:NSDate = dateFromString(string);
		
		if (dt == null)
		{
			ret.obj = null;
			ret.success = false;
			ret.error = "There was a problem during the conversion process.";
		}
		else
		{
			ret.success = true;
			ret.obj = dt;
			ret.error = "";
		}
		
		return ret;
	}
	
	
	/**
	 * Returns a date constructed from a string based on this formatter's
	 * current settings.
	 */
	public function dateFromString(string:String):NSDate
	{
		return NSDate.date();
	}
	
	//******************************************************															 
	//*                  Private Methods
	//******************************************************
	

	
	//******************************************************															 
	//*             Public Static Properties
	//******************************************************
	//******************************************************															 
	//*                String Formatting
	//******************************************************	
	
	/**
	 * Parses the format string into an intermediate format.
	 *
	 * Format description:
	 *	The format consists of an array of simple objects. These objects can
	 *	represent one of three things:
	 *
	 * <ol>
	 *		<li>A format character.</li>
	 *		<li>A word (not a format character or whitespace.</li>
	 *		<li>A space.</li>
	 * </ol>
	 *
	 * Each object is formatted as follows:
	 *		{type: ASFormatChar|ASWord|ASSpaceChar, 
	 *		 value: The value (without % for format characters)}
	 */
	private static function parseFormatString(format:String):Array
	{
		var ret:Array;
		var char:String; // the current character
		var isFormatChar:Boolean = false;
		var onWord:Boolean = false;
		var wasOnWord:Boolean = false;
		var wordStartIdx:Number;
		var len:Number = format.length;
		var curObj:Object;
		
		ret = new Array();
		
		//
		// Move through the format string's characters.
		//
		for (var i:Number = 0; i < len; i++)
		{
			char = format.charAt(i);
			wasOnWord = onWord;
						
			if (isFormatChar)
			{
				if (isTypeCharacter(char)) // output format
				{
					ret.push({type: ASFormatChar, value: char});
				}
				else
				{
					//! error?
				}
				
				isFormatChar = false;
				continue;
			}
			
			switch (char)
			{
				case "%":
					onWord = false;
					isFormatChar = true;
					break;
					
				case " ": // space handling
				case "\t":
				case "\n":
				case "\r":
					onWord = false;
					ret.push({type: ASSpaceChar, value:char});
					break;
					
				default:
					onWord = true;
					break;
					
			}
			
			//
			// Word collection
			//
			if (!onWord && wasOnWord)
			{
				var top:Object = ret.pop();
				
				if (top != null && top.type != ASSpaceChar)
					ret.push(top);				
				
				ret.push({type: ASWord, value: format.slice(wordStartIdx, i)});
				
				if (top.type == ASSpaceChar)
					ret.push(top);
			}
			else if (onWord && !wasOnWord)
			{
				wordStartIdx = i;
			}
		}
		
		return ret;
	}
	
	
	/**
	 * Formats the date date according to the calendar format format, and
	 * returns the resulting string.
	 */
	private static function formatDate(format:String, date:NSDate, 
		locale:NSDictionary):String
	{		
		var parts:Array = parseFormatString(format);
		var formatted:Array = new Array();
		var len:Number = parts.length;
		var obj:Object;
		
		if (locale == null)
		{
			locale = NSUserDefaults.standardUserDefaults(
				).dictionaryRepresentation();
		}
		
		for (var i:Number = 0; i < len; i++)
		{
			obj = parts[i];
			
			switch (obj.type)
			{
				case ASWord:
				case ASSpaceChar:
					formatted.push(obj.value);
					break;
				
				case ASFormatChar:
					formatted.push(g_types[obj.value](obj.value, date, locale));
					break;
					
			}
		}
		
		return formatted.join("");
	}
	
	
	private static function buildDateFromString(format:String, 
		locale:NSDictionary):NSDate
	{
		var parts:Array = parseFormatString(format);
		
		return null;
	}
	
	
	/**
	 * Returns whether a character should be handled by one of the handlers or not.
	 */
	private static function isTypeCharacter(char:String):Boolean
	{		
		return (g_types[char] != undefined);
	}
		
	
	private static function traceCompiledFormat(format:Array):Void
	{
		trace("**** BEGIN COMPILED FORMAT trace ****");
		
		for (var i:Number = 0; i < format.length; i++)
		{
			var type:String;
			
			switch (format[i].type)
			{
				case ASWord:
					type = "ASWord";
					break;
					
				case NSDateFormatter.ASFormatChar:
					type = "ASFormatChar";
					break;
					
				case NSDateFormatter.ASSpaceChar:
					type = "ASSpaceChar";
					break;
					
			}
			
			trace("** " + i + ": (type=" + type + ", value=" + format[i].value + ")");
		}
		
		trace("**** END COMPILED FORMAT trace ****");
	}
	
	//******************************************************															 
	//*                  Format Handlers
	//******************************************************	
	
	/**
	 * Handles a percentage symbol.
	 */
	private static function handlePercentage(char:String, date:NSDate,
		locale:NSDictionary):String
	{
		return "%";
	}
	

	/**
	 * Handles a formatted weekday.
	 */
	private static function handleWeekDay(char:String, date:NSDate,
		locale:NSDictionary):String
	{		
		var calDt:NSCalendarDate = (new NSCalendarDate()).initWithDate(date.internalDate());
		var str:String;
		var arr:NSArray;
		var dayOfWeek:Number = calDt.dayOfWeek();
		
		switch (char)
		{
			case "a":
				arr = NSArray(locale.objectForKey(
					NSUserDefaults.NSShortWeekDayNameArray));
				str = String(arr.objectAtIndex(dayOfWeek));
				break;
				
			case "A":
				arr = NSArray(locale.objectForKey(
					NSUserDefaults.NSWeekDayNameArray));
				str = String(arr.objectAtIndex(dayOfWeek));
				break;
				
			case "w":
				str = dayOfWeek.toString();
				break;
				
		}
		
		return str;
	}
	
	
	/**
	 * Handles a formatted month.
	 */
	private static function handleMonth(char:String, date:NSDate, 
		locale:NSDictionary):String
	{
		var str:String;
		var arr:NSArray;
		var month:Number = date.internalDate().getMonth();
		
		switch (char)
		{
			case "b":
				arr = NSArray(locale.objectForKey(
					NSUserDefaults.NSShortMonthNameArray));
				str = String(arr.objectAtIndex(month));
				break;
				
			case "B":
				arr = NSArray(locale.objectForKey(
					NSUserDefaults.NSMonthNameArray));
				str = String(arr.objectAtIndex(month));
				break;
				
			case "m":
				str = month.toString();
				
				if (str.length == 1)
					str = "0" + str;
					
				break;
				
		}
		
		return str;
	}
	
	
	/**
	 * Handles the locale default (%c = %x %x).
	 */
	private static function handleLocaleDefault(char:String, date:NSDate, 
		locale:NSDictionary):String
	{
		var str:String = "";
		
		str += handleDefaultDate(char, date, locale) + " ";
		str += handleDefaultTime(char, date, locale);
		
		return str;
	}
	
	
	/**
	 * Handles the day of the month.
	 */
	private static function handleDay(char:String, date:NSDate, 
		locale:NSDictionary):String
	{
		var calDt:NSCalendarDate = (new NSCalendarDate()).initWithDate(
			date.internalDate());
		var str:String;
		
		switch (char)
		{
			case "d":
				str = calDt.dayOfMonth().toString();
				
				if (str.length == 1)
					str = "0" + str;
					
				break;
				
			case "e":
				str = calDt.dayOfMonth().toString();
				break;
				
			case "j":
				str = calDt.dayOfYear().toString();
				break;
				
		}
		
		return str;
	}
	
	
	/**
	 * Returns the number of milliseconds (0 - 999).
	 */
	private static function handleMilliseconds(char:String, date:NSDate, 
		locale:NSDictionary):String
	{
		return date.internalDate().getMilliseconds().toString();
	}
	
	
	/**
	 * Handles the hour.
	 */
	private static function handleHour(char:String, date:NSDate, 
		locale:NSDictionary):String
	{
		var calDt:NSCalendarDate = (new NSCalendarDate()).initWithDate(
			date.internalDate());
		var str:String;
		
		switch (char)
		{
			case "H":
				str = calDt.hourOfDay().toString();
				break;
				
			case "I":
				str = ((calDt.hourOfDay() % 12) + 1).toString();
				break;
				
		}
		
		if (str.length == 1)
			str = "0" + str;
			
		return str;
	}
	
	
	/**
	 * Handles the timezone.
	 */
	private static function handleTimeZone(char:String, date:NSDate, 
		locale:NSDictionary):String
	{
		var calDt:NSCalendarDate = (new NSCalendarDate()).initWithDate(
			date.internalDate());
		var str:String;
		
		switch (char)
		{
			case "z":
				var hr:String = Math.floor(calDt.timeZone()).toString();
				var mn:String = ((calDt.timeZone() % 1) * 60).toString();
				
				if (hr.length == 1)
					hr = "0" + hr;
					
				if (mn.length == 1)
					mn = "0" + mn;
					
				str = hr + mn;				
				break;
				
			case "Z":
				str = "time zone name"; //! implement
				break;
				
		}
		
		return str;		
	}
	
	
	/**
	 * Handles the minute.
	 */
	private static function handleMinute(char:String, date:NSDate, 
		locale:NSDictionary):String
	{
		var calDt:NSCalendarDate = (new NSCalendarDate()).initWithDate(
			date.internalDate());
		var str:String = calDt.minuteOfHour().toString();
		
		if (str.length == 1)
			str = "0" + str;
			
		return str;
	}
	
	
	/**
	 * Returns AM / PM.
	 */
	private static function handleAmPm(char:String, date:NSDate, 
		locale:NSDictionary):String
	{
		var str:String;
		var arr:NSArray = NSArray(locale.objectForKey(
			NSUserDefaults.NSAMPMDesignation));
				
		if (date.internalDate().getHours() % 12 < 12)
			str = String(arr.objectAtIndex(0));
		else
			str = String(arr.objectAtIndex(1));
			
		return str;
	}
	
	
	/**
	 * Handles second representation.
	 */
	private static function handleSecond(char:String, date:NSDate, 
		locale:NSDictionary):String
	{
		var calDt:NSCalendarDate = (new NSCalendarDate()).initWithDate(
			date.internalDate());
		var str:String = calDt.secondOfMinute().toString();
		
		if (str.length == 1)
			str = "0" + str;
			
		return str;
	}
	
	
	/**
	 * Handles years.
	 */
	private static function handleYear(char:String, date:NSDate, 
		locale:NSDictionary):String
	{
		var str:String;
		
		switch (char)
		{
			case "y":
				str = date.internalDate().getYear().toString();
				break;
				
			case "Y":
				str = date.internalDate().getFullYear().toString();
				break;
				
		}
		
		return str;
	}
	

	/**
	 * Handles default dates according to the locale.
	 */	
	private static function handleDefaultDate(char:String, date:NSDate, 
		locale:NSDictionary):String
	{
		return formatDate(String(
			locale.objectForKey(NSUserDefaults.NSDateFormatString)),
			date, locale);
	}
	
	
	/**
	 * Handles default time according to the locale.
	 */
	private static function handleDefaultTime(char:String, date:NSDate, 
		locale:NSDictionary):String
	{
		return formatDate(String(
			locale.objectForKey(NSUserDefaults.NSTimeDateFormatString)),
			date, locale);
	}
	
	//******************************************************															 
	//*               Static Constructor
	//******************************************************
	
	/**
	 * Runs when the application begins.
	 */
	private static function classConstruct():Boolean
	{
		if (classConstructed)
			return true;
			
		//
		// Handler functions (for date formatting)
		//
		g_types = new Object();
		g_types["%"] = handlePercentage;
		g_types["a"] = g_types["A"] = g_types["w"] = handleWeekDay;
		g_types["b"] = g_types["B"] = g_types["m"] = handleMonth;
		g_types["c"] = handleLocaleDefault;
		g_types["d"] = g_types["e"] = g_types["j"] = handleDay;
		g_types["F"] = handleMilliseconds;
		g_types["H"] = g_types["I"] = handleHour;
		g_types["M"] = handleMinute;
		g_types["p"] = handleAmPm;
		g_types["S"] = handleSecond;
		g_types["y"] = g_types["Y"] = handleYear;
		g_types["z"] = g_types["Z"] = handleTimeZone;
		g_types["x"] = handleDefaultDate;
		g_types["X"] = handleDefaultTime;
		
		return true;
	}
	
	private static var classConstructed:Boolean = classConstruct();
}
