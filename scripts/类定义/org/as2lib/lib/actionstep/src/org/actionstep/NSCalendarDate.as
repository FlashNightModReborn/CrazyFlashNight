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

//import org.actionstep.NSArray;
import org.actionstep.NSDate;
import org.actionstep.NSDateFormatter;
import org.actionstep.NSDictionary;
//import org.actionstep.NSException;
//import org.actionstep.NSObject;
//import org.actionstep.NSUserDefaults;

/**
 * NSCalendarDate is a public subclass of NSDate that represents concrete date
 * objects and performs date computations based on the Gregorian calendar.
 *
 * @author Scott Hyndman
 */
class org.actionstep.NSCalendarDate extends NSDate
{		
	/** The number of milliseconds in a day. */
	private static var MSPERDAY:Number 		= 86400000;
	/** The number of milliseconds in an hour. */
	private static var MSPERHOUR:Number		= 3600000;
	/** The number of milliseconds in a minute. */
	private static var MSPERMINUTE:Number	= 60000;
	/** The number of milliseconds in a second. */
	private static var MSPERSECOND:Number	= 1000;
	
	
	/** Format specifier character to function map. */
	private static var g_types:Object;
	private static var g_firstDayInCommonEra:Date;
	private var m_calendarFormat:String;
	private var m_timeZone:Number; //! should be NSTimeZone at some point
	
	//******************************************************															 
	//*                    Construction
	//******************************************************
	
	/**
	 * Creates an instance of the NSCalendarDate class.
	 */
	public function NSCalendarDate()
	{
	}
	
	
	/**
	 * Creates a date from a string. The string must adhere to the format 
	 * “%Y-%m-%d %H:%M:%S %z” exactly, or null will be returned.
	 */
	public function initWithString(description:String):NSCalendarDate
	{
		return initWithStringCalendarFormat(description, "%Y-%m-%d %H:%M:%S %z");
	}

	
	/**
	 * Creates a date from a string using the calendar format format to interpret
	 * the string.
	 */
	public function initWithStringCalendarFormat(description:String, 
		format:String):NSCalendarDate
	{
		return initWithStringCalendarFormatLocale(description, format, null); //! last param
	}
	
	
	
	public function initWithStringCalendarFormatLocale(description:String,
		format:String, locale:NSDictionary):NSCalendarDate
	{
		super.init();
		
		NSCalendarDate.reverseFormatWithDescriptionFormatLocale(description, format, locale);
		
		m_calendarFormat = format;
		
		return this;		
	}
		
	
	/**
	 * Inits a caledar date using the specified values.
	 *
	 * @param year 		The year. Must include a century (1999, not 99).
	 * @param month 	The month. A value from 1 to 12.
	 * @param day 		The day. A value from 1 to 31.
	 * @param hour		The hour. A value from 0 to 23.
	 * @param minute	The minute. A value from 0 to 59.
	 * @param second	The second. A value from 0 to 59.
	 * @param timezone	The timezone offset. From -12 to 12.
	 */
	public function initWithYearMonthDayHourMinuteSecondTimeZone(
		year:Number, month:Number, day:Number, hour:Number, 
		minute:Number, second:Number, 
		timezone:Number //! should be NSTimeZone
		):NSCalendarDate 
	{
		super.init();
		
		m_dt.setFullYear(year);
		m_dt.setMonth(month - 1);
		m_dt.setDate(day);
		m_dt.setHours(hour);
		m_dt.setMinutes(minute);
		m_dt.setSeconds(second);
		
		m_timeZone = timezone;
		
		return this;
	}
	
	
	/**
	 * Inits a calendar date using an instance of ActionScript's Date class.
	 *
	 * ActionStep only.
	 */
	public function initWithDate(date:Date):NSCalendarDate
	{
		super.init();
		
		m_dt.setTime(date.getTime());
		return this;
	}
	
	//******************************************************															 
	//*                    Properties
	//******************************************************
	
	/**
	 * Returns the date's default calendar format. This format is used
	 * for description() strings.
	 */	
	public function calendarFormat():String
	{
		return m_calendarFormat;
	}
	
	
	/**
	 * Sets the date's default calendar format. This format is used
	 * for description() strings.
	 */
	public function setCalendarFormat(format:String):Void
	{
		m_calendarFormat = format;
	}
	
	
	/**
	 * Returns the number of days since the beginning of the Common Era.
	 * The base year of the Common Era is 1 C.E. (which is the same as 1 A.D.).
	 */
	public function dayOfCommonEra():Number
	{
		var ms:Number = m_dt.getTime();
		ms += -1 * g_firstDayInCommonEra.getTime();
		
		return Math.floor(ms / MSPERDAY);
	}
	
	
	/**
	 * Returns the day of the month (1 through 31).
	 */
	public function dayOfMonth():Number
	{
		return m_dt.getDate();
	}
	
	
	/**
	 * Returns the day of the week (0 through 6).
	 */
	public function dayOfWeek():Number
	{
		return m_dt.getDay();
	}
	
	
	/**
	 * Returns the day of the year (1 through 366).
	 */
	public function dayOfYear():Number
	{
		var delta:Number;
		var calcDate:Date;
		
		calcDate = NSDate(super.copy()).internalDate();
		calcDate.setMonth(0);
		calcDate.setDate(1);
		calcDate.setHours(0);
		calcDate.setMinutes(0);
		calcDate.setSeconds(0);
		calcDate.setMilliseconds(0);
		
		delta = m_dt.getTime() - calcDate.getTime();
		return Math.ceil(delta / MSPERDAY);
	}
	
	
	/**
	 * Returns the hour of the day (0 through 23).
	 */
	public function hourOfDay():Number
	{
		return m_dt.getHours();
	}
	
	
	/** 
	 * Returns the minute of the hour (0 through 59).
	 */
	public function minuteOfHour():Number
	{
		return m_dt.getMinutes();
	}
	
	
	/**
	 * Returns the month of the year (1 through 12).
	 */
	public function monthOfYear():Number
	{
		return m_dt.getMonth() + 1;
	}
	
	
	/**
	 * Returns the second of the current minute (0 through 59).
	 */
	public function secondOfMinute():Number
	{
		return m_dt.getSeconds();
	}
	

	/** 
	 * Returns this date's timezone.
	 */	
	public function timeZone():Number //! should be NSTimeZone
	{
		return m_timeZone;
	}
	
	
	/**
	 * Sets the time zone of this date.
	 */
	public function setTimeZone(timeZone:Number):Void //! should be NSTimeZone
	{
		m_timeZone = timeZone;
	}
	
	
	/**
	 * Returns a number that indicates the year (ie. 2005).
	 */
	public function yearOfCommonEra():Number
	{
		return m_dt.getFullYear();
	}


	//******************************************************															 
	//*                Formatted Dates
	//******************************************************

	/**
	 * Returns a string representing the date using the default calendar
	 * format. This format can be seen by accessing this date's
	 * calendarFormat() method.
	 */
	public function description():String 
	{
		return descriptionWithCalendarFormat(m_calendarFormat);
	}
	
	
	/**
	 * Returns a string representation of the date using the provided
	 * format string.
	 */
	public function descriptionWithCalendarFormat(format:String):String
	{
		return descriptionWithCalendarFormatLocale(format, null);
	}
	
	
	/**
	 * Returns a string representation of the receiver. The string is formatted
	 * according to the conversion specifiers in format and represented
	 * according to the locale information in locale.
	 */
	public function descriptionWithCalendarFormatLocale(format:String, 
		locale:NSDictionary):String
	{
		var dtf:NSDateFormatter = (new NSDateFormatter()
			).initWithDateFormatAllowNaturalLanguage(format, true);
		return dtf.stringFromDate(this); //! locale
	}
	
	
	/**
	 * Returns a string representation of the receiver. The string is formatted
	 * according to the default format and represented according to the 
	 * locale information in locale.
	 *
	 * This method is used to print the NSCalendarDate when the %@ conversion
	 * specifier is used.
	 */
	public function descriptionWithLocale(locale:NSDictionary):String
	{
		return descriptionWithCalendarFormatLocale(m_calendarFormat, locale);
	}
	
	
	//******************************************************															 
	//*                 Public Methods
	//******************************************************
	
	/**
	 * Creates a new calendar date by adding the arguments to the this
	 * dates values, and returns the new date.
	 *
	 * Arguments can be both negative and positive.
	 */
	public function dateByAddingYearsMonthsDaysHoursMinutesSeconds(
		years:Number, months:Number, days:Number, hours:Number,
		minutes:Number, seconds:Number):NSCalendarDate
	{
		var currentTime:Number;
		var offset:Number;
		var calcDate:Date;
		var totalMonths:Number;
		var remainingMonths:Number;
		var monthsInYears:Number;
		
		//
		// Add years.
		//
		calcDate = NSDate(super.copy()).internalDate();
		calcDate.setFullYear(calcDate.getFullYear() + years);
		
		//
		// Add months.
		//
		totalMonths = months + calcDate.getMonth() + 1;
		remainingMonths = totalMonths % 12;
		monthsInYears = Math.floor(totalMonths / 12);
		calcDate.setFullYear(calcDate.getFullYear() + monthsInYears);
		calcDate.setMonth(remainingMonths);
		
		//
		// Calc offset using days, hours, minutes, and seconds (always constant milliseconds)
		//
		offset = 0;
		offset += MSPERDAY * days;
		offset += MSPERHOUR * hours;
		offset += MSPERMINUTE * minutes;
		offset += MSPERSECOND * seconds;
		calcDate.setTime(calcDate.getTime() + offset);
		
		//
		// Return the new date.
		//
		return (new NSCalendarDate()).initWithYearMonthDayHourMinuteSecondTimeZone(
			calcDate.getFullYear(), calcDate.getMonth(), calcDate.getDate(),
			calcDate.getHours(), calcDate.getMinutes(), calcDate.getSeconds(),
			m_timeZone);
	}
		
	
	/**
	 * @see org.actionstep.NSObject#toString()
	 */
	public function toString():String
	{
		return description();
	}
	
	
	/**
	 * Returns an object containing the number of years, months, days, hours, minutes
	 * and seconds between this and the date date.
	 *
	 * The object is formatted as follows:
	 * {years:Number, months:Number, days:Number, hours:Number, minutes:Number,
	 * 		seconds:Number}
	 *
	 * This differs from Cocoa because we don't have access to pointers in
	 * ActionScript, so we return an object containing multiple values instead.
	 */
	public function yearsMonthsDaysHoursMinutesSecondsSinceDate(calDate:NSCalendarDate):Object
	{
		var delta:Number;
		var dayBeforeShift:Number, dayOffset:Number;
		var dt:Date, date:Date;
		var years:Number, months:Number, days:Number, hours:Number, 
			minutes:Number, seconds:Number;
		var ms:Number;
		
		//
		// Account for timezones
		//	
		dt = NSDate(super.copy()).internalDate();
		dt.setTime(dt.getTime() - timeZone() * MSPERHOUR);
		date = NSDate(calDate.copy()).internalDate();
		date.setTime(date.getTime() - calDate.timeZone() * MSPERHOUR);
			
		//
		// Find years
		//
		years = m_dt.getFullYear() - date.getFullYear();
		
		//
		// Decrease if necessary
		//
		dt.setFullYear(date.getFullYear());
		
		if (dt < date)
			years--;
			
		//
		// Find months
		//
		months = dt.getMonth() - date.getMonth();
		
		if (months < 0)
			months += 12;
			
		//
		// Find days
		//
		dayBeforeShift = date.getDate();
		date.setMonth(dt.getMonth());
		dayOffset = dayBeforeShift - date.getDate();
		
		days = dt.getDate() - date.getDate();
		
		if (days < 0)
		{
			trace("negative day");
			months--;
			days *= -1;
		}
		
		days += dayOffset; //! This might be wrong sometimes. Think about it.
				
		//
		// Find hours
		//
		date.setDate(dt.getDate());
		hours = dt.getHours() - date.getHours();
		
		if (hours < 0)
		{
			trace("negative hour");
			days--;
			hours *= -1;
		}
		
		//
		// Find minutes
		//
		minutes = dt.getMinutes() - date.getMinutes();
		
		if (minutes < 0)
		{
			trace("negative minute");
			hours--;
			minutes *= -1;
		}
		
		//
		// Find seconds
		//
		seconds = dt.getSeconds() - date.getSeconds();
		
		if (seconds < 0)
		{
			minutes--;
			seconds *= -1;
		}
		
		//
		// Use milliseconds to properly adjust seconds
		//
		ms = dt.getMilliseconds() - date.getMilliseconds();
		
		if (ms < 0)
			seconds--;
		
		return {years: years, months: months, days: days, hours: hours, 
			minutes: minutes, seconds: seconds};
	}
	
	//******************************************************															 
	//*              Date Formatting Stuff
	//******************************************************
	
	/**
	 * Uses a string representation of a date and the format string
	 * originally used to output the date, and returns the date described.
	 */
	private static function reverseFormatWithDescriptionFormatLocale(
		date:String, format:String, locale:NSDictionary):NSCalendarDate
	{
		var ret:NSCalendarDate;
		
		ret = new NSCalendarDate();
		
		return ret;
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
				
		g_firstDayInCommonEra = new Date(1, 0, 1, 0, 0, 0, 0);
		
		return true;
	}
	
	private static var classConstructed:Boolean = classConstruct();
}
