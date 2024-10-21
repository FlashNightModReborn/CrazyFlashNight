/*
 * Copyright the original author or authors.
 * 
 * Licensed under the MOZILLA PUBLIC LICENSE, Version 1.1 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *      http://www.mozilla.org/MPL/MPL-1.1.html
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import org.as2lib.core.BasicClass;
import org.as2lib.env.except.IllegalArgumentException;

/**
 * {@code DateFormatter} formats a given date with a specified pattern.
 * 
 * <p>Use the declared constants as placeholders for specific parts of the date-time.
 *
 * <p>All characters from 'A' to 'Z' and from 'a' to 'z' are reserved, although not
 * all of these characters are interpreted right now. If you want to include plain
 * text in the pattern put it into quotes (') to avoid interpretation. If you want
 * a quote in the formatted date-time, put two quotes directly after one another.
 * For example: {@code "hh 'o''clock'"}.
 * 
 * <p>Example:
 * <code>
 *   var formatter:DateFormatter = new DateFormatter("dd.mm.yyyy HH:nn:ss S");
 *   trace(formatter.format(new Date(2005, 2, 29, 18, 14, 3, 58)));
 * </code>
 *
 * <p>Output:
 * <pre>
 *   29.03.2005 18:14:03 58
 * </pre>
 *
 * @author Simon Wacker
 */
class org.as2lib.util.DateFormatter extends BasicClass {
	
	/** The default date format pattern. */
	public static var DEFAULT_DATE_FORMAT:String = "dd.mm.yyyy HH:nn:ss";
	
	/** Placeholder for year in date format. */
	public static var YEAR:String = "y";
	
	/** Placeholder for month in year as number in date format. */
	public static var MONTH_AS_NUMBER:String = "m";
	
	/** Placeholder for month in year as text in date format. */
	public static var MONTH_AS_TEXT:String = "M";
	
	/** Placeholder for day in month as number in date format. */
	public static var DAY_AS_NUMBER:String = "d";
	
	/** Placeholder for day in week as text in date format. */
	public static var DAY_AS_TEXT:String = "D";
	
	/** Placeholder for hour in am/pm (1 - 12) in date format. */
	public static var HOUR_IN_AM_PM:String = "h";
	
	/** Placeholder for hour in day (0 - 23) in date format. */
	public static var HOUR_IN_DAY:String = "H";
	
	/** Placeholder for minute in hour in date format. */
	public static var MINUTE:String = "n";
	
	/** Placeholder for second in minute in date format. */
	public static var SECOND:String = "s";
	
	/** Placeholder for millisecond in date format. */
	public static var MILLISECOND:String = "S";
	
	/** Quotation beginning and ending token. */
	public static var QUOTE:String = "'";
	
	/** Fully written out string for january. */
	public static var JANUARY:String = "January";
	
	/** Fully written out string for february. */
	public static var FEBRUARY:String = "February";
	
	/** Fully written out string for march. */
	public static var MARCH:String = "March";
	
	/** Fully written out string for april. */
	public static var APRIL:String = "April";
	
	/** Fully written out string for may. */
	public static var MAY:String = "May";
	
	/** Fully written out string for june. */
	public static var JUNE:String = "June";
	
	/** Fully written out string for july. */
	public static var JULY:String = "July";
	
	/** Fully written out string for august. */
	public static var AUGUST:String = "August";
	
	/** Fully written out string for september. */
	public static var SEPTEMBER:String = "September";
	
	/** Fully written out string for october. */
	public static var OCTOBER:String = "October";
	
	/** Fully written out string for november. */
	public static var NOVEMBER:String = "November";
	
	/** Fully written out string for december. */
	public static var DECEMBER:String = "December";
	
	/** Fully written out string for monday. */
	public static var MONDAY:String = "Monday";
	
	/** Fully written out string for tuesday. */
	public static var TUESDAY:String = "Tuesday";
	
	/** Fully written out string for wednesday. */
	public static var WEDNESDAY:String = "Wednesday";
	
	/** Fully written out string for thursday. */
	public static var THURSDAY:String = "Thursday";
	
	/** Fully written out string for friday. */
	public static var FRIDAY:String = "Friday";
	
	/** Fully written out string for saturday. */
	public static var SATURDAY:String = "Saturday";
	
	/** Fully written out string for sunday. */
	public static var SUNDAY:String = "Sunday";
	
	/** The pattern to format the date with. */
	private var dateFormat:String;
	
	/**
	 * Constructs a new {@code DateFormatter} instance.
	 *
	 * <p>If you do not pass-in a {@code dateFormat} or if the passed-in one is
	 * {@code null} or {@code undefined} the {@code DEFAULT_DATE_FORMAT} is used.
	 * 
	 * @param dateFormat (optional) the pattern describing the date and time format
	 */
	public function DateFormatter(dateFormat:String) {
		this.dateFormat = dateFormat == null ? DEFAULT_DATE_FORMAT : dateFormat;
	}
	
	/**
	 * Formats the passed-in {@code date} with the specified date format pattern into a
	 * date-time string and returns the resulting string.
	 * 
	 * <p>If the passed-in {@code date} is {@code null} or {@code undefined}, the current
	 * date-time will be used instead.
	 *
	 * @param date the date-time value to format into a date-time string
	 * @return the formatted date-time string
	 */
	public function format(date:Date):String {
		if (!date) date = new Date();
		var result:String = "";
		for (var i:Number = 0; i < dateFormat.length; i++) {
			if (dateFormat.substr(i, 1) == YEAR) {
				var tokenCount:Number = getTokenCount(dateFormat.substr(i));
				result += formatYear(date.getFullYear(), tokenCount);
				i += tokenCount - 1;
				continue;
			}
			if (dateFormat.substr(i, 1) == MONTH_AS_NUMBER) {
				var tokenCount:Number = getTokenCount(dateFormat.substr(i));
				result += formatMonthAsNumber(date.getMonth(), tokenCount);
				i += tokenCount - 1;
				continue;
			}
			if (dateFormat.substr(i, 1) == MONTH_AS_TEXT) {
				var tokenCount:Number = getTokenCount(dateFormat.substr(i));
				result += formatMonthAsText(date.getMonth(), tokenCount);
				i += tokenCount - 1;
				continue;
			}
			if (dateFormat.substr(i, 1) == DAY_AS_NUMBER) {
				var tokenCount:Number = getTokenCount(dateFormat.substr(i));
				result += formatDayAsNumber(date.getDate(), tokenCount);
				i += tokenCount - 1;
				continue;
			}
			if (dateFormat.substr(i, 1) == DAY_AS_TEXT) {
				var tokenCount:Number = getTokenCount(dateFormat.substr(i));
				result += formatDayAsText(date.getDay(), tokenCount);
				i += tokenCount - 1;
				continue;
			}
			if (dateFormat.substr(i, 1) == HOUR_IN_AM_PM) {
				var tokenCount:Number = getTokenCount(dateFormat.substr(i));
				result += formatHourInAmPm(date.getHours(), tokenCount);
				i += tokenCount - 1;
				continue;
			}
			if (dateFormat.substr(i, 1) == HOUR_IN_DAY) {
				var tokenCount:Number = getTokenCount(dateFormat.substr(i));
				result += formatHourInDay(date.getHours(), tokenCount);
				i += tokenCount - 1;
				continue;
			}
			if (dateFormat.substr(i, 1) == MINUTE) {
				var tokenCount:Number = getTokenCount(dateFormat.substr(i));
				result += formatMinute(date.getMinutes(), tokenCount);
				i += tokenCount - 1;
				continue;
			}
			if (dateFormat.substr(i, 1) == SECOND) {
				var tokenCount:Number = getTokenCount(dateFormat.substr(i));
				result += formatSecond(date.getSeconds(), tokenCount);
				i += tokenCount - 1;
				continue;
			}
			if (dateFormat.substr(i, 1) == MILLISECOND) {
				var tokenCount:Number = getTokenCount(dateFormat.substr(i));
				result += formatMillisecond(date.getMilliseconds(), tokenCount);
				i += tokenCount - 1;
				continue;
			}
			if (dateFormat.substr(i, 1) == QUOTE) {
				if (dateFormat.substr(i + 1, 1) == QUOTE) {
					result += "'";
					i++;
					continue;
				}
				var nextQuote:Number = i;
				var oldQuote:Number;
				while (true) {
					oldQuote = nextQuote;
					nextQuote = dateFormat.indexOf("'", nextQuote + 1);
					if (dateFormat.substr(nextQuote + 1, 1) != QUOTE) {
						break;
					}
					result += dateFormat.substring(oldQuote + 1, nextQuote + 1);
					nextQuote++;
				}
				result += dateFormat.substring(oldQuote + 1, nextQuote);
				i = nextQuote;
				continue;
			}
			result += dateFormat.substr(i, 1);
		}
		return result;
	}
	
	/**
	 * Returns the number of tokens that occur in a succession from the beginning of the
	 * passed-in {@code string}.
	 * 
	 * <p>If the passed-in {@code string} is {@code null}, {@code undefined} or empty,
	 * 0 is returned.
	 *
	 * @param string the string to search through
	 * @return the number of tokens that occur in a succession
	 */
	private function getTokenCount(string:String):Number {
		if (!string) return 0;
		var result:Number = 0;
		var token:String = string.substr(0, 1);
		while (string.substr(result, 1) == token) {
			result++;
		}
		return result;
	}
	
	/**
	 * Returns a string that contains the specified number of 0s.
	 *
	 * <p>A {@code count} less or equal than 0 or a {@code count} of value {@code null}
	 * or {@code undefined} results in en empty string.
	 * 
	 * @param count the number of 0s
	 * @return the specified number of 0s
	 */
	private function getZeros(count:Number):String {
		if (count < 1 || count == null) return "";
		if (count < 2) return "0";
		var result:String = "00";
		count -= 2;
		while (count) {
			result += "0";
			count--;
		}
		return result;
	}
	
	/**
	 * Formats the passed-in {@code year} into a year string with the specified
	 * {@code digitCount}.
	 * 
	 * <p>A {@code digitCount} less or equal than three results in a year string with
	 * two digits. A {@code digitCount} greater or equal than four results in a year
	 * string with four digits plus preceding 0s if the {@code digitCount} is greater
	 * than four.
	 *
	 * <p>If the passed-in {@code digitCount} is {@code null} or {@code undefined}, 0
	 * is used instead.
	 *
	 * @param year the year to format to a string
	 * @param digitCount the number of favored digits
	 * @return the string representation of the year
	 * @throws IllegalArgumentException if the passed-in {@code year} is
	 * {@code null} or {@code undefined}
	 */
	private function formatYear(year:Number, digitCount:Number):String {
		if (year == null) {
			throw new IllegalArgumentException("Argument 'year' [" + year + "] must not be 'null' nor 'undefined'.", this, arguments);
		}
		if (digitCount == null) digitCount = 0;
		if (digitCount < 4) {
			return year.toString().substr(2);
		}
		return (getZeros(digitCount - 4) + year.toString());
	}
	
	/**
	 * Formats the passed-in {@code month} into a month as number string with the
	 * specified {@code digitCount}.
	 * 
	 * <p>A {@code digitCount} less or equal than one results in a month with one digit,
	 * if the month is less or equal than nine. Otherwise the month is represented by a
	 * two digit number. A {@code digitCount} greater or equal than two results in a
	 * month with preceding 0s.
	 *
	 * <p>If the passed-in {@code digitCount} is {@code null} or {@code undefined}, 0 
	 * is used instead.
	 * 
	 * @param month the month to format to a number string
	 * @param digitCount the number of favored digits
	 * @return the number representation of the month
	 * @throws IllegalArgumentException if the passed-in {@code month} is
	 * less than 0 or greater than 11 or {@code null} or {@code undefined}
	 */
	private function formatMonthAsNumber(month:Number, digitCount:Number):String {
		if (month < 0 || month > 11 || month == null) {
			throw new IllegalArgumentException("Argument 'month' [" + month + "] must not be less than 0 nor greater than 11 nor 'null' nor 'undefined'.", this, arguments);
		}
		if (digitCount == null) digitCount = 0;
		var string:String = (month + 1).toString();
		return (getZeros(digitCount - string.length) + string);
	}
	
	/**
	 * Formats the passed-in {@code month} into a string with the specified 
	 * {@code tokenCount}.
	 * 
	 * <p>A {@code tokenCount} less or equal than three results in a month with three
	 * tokens. A {@code tokenCount} greater or equal than four results in a fully written
	 * out month.
	 *
	 * <p>If the passed-in {@code tokenCount} is {@code null} or {@code undefined}, 0
	 * is used instead.
	 *
	 * @param month the month to format to a string
	 * @param tokenCount the number of favored tokens
	 * @return the string representation of the month
	 * @throws IllegalArgumentException if the passed-in {@code month} is
	 * less than 0 or greater than 11 or {@code null} or {@code undefined}
	 */
	private function formatMonthAsText(month:Number, tokenCount:Number):String {
		if (month < 0 || month > 11 || month == null) {
			throw new IllegalArgumentException("Argument 'month' [" + month + "] must not be less than 0 nor greater than 11 nor 'null' nor 'undefined'.", this, arguments);
		}
		if (tokenCount == null) tokenCount = 0;
		var result:String;
		switch (month) {
			case 0:
				result = JANUARY;
				break;
			case 1:
				result = FEBRUARY;
				break;
			case 2:
				result = MARCH;
				break;
			case 3:
				result = APRIL;
				break;
			case 4:
				result = MAY;
				break;
			case 5:
				result = JUNE;
				break;
			case 6:
				result = JULY;
				break;
			case 7:
				result = AUGUST;
				break;
			case 8:
				result = SEPTEMBER;
				break;
			case 9:
				result = OCTOBER;
				break;
			case 10:
				result = NOVEMBER;
				break;
			case 11:
				result = DECEMBER;
				break;
		}
		if (tokenCount < 4) {
			return result.substr(0, 3);
		}
		return result;
	}
	
	/**
	 * Formats the passed-in {@code day} into a day as number string with the specified 
	 * {@code digitCount}.
	 * 
	 * <p>A {@code digitCount} less or equal than one results in a day with one digit,
	 * if the day is less or equal than nine. Otherwise the day is represented by a two
	 * digit number. A {@code digitCount} greater or equal than two results in a day with
	 * preceding 0s.
	 *
	 * <p>If the passed-in {@code digitCount} is {@code null} or {@code undefined}, 0
	 * is used instead.
	 *
	 * @param day the day of month to format to a number string
	 * @param digitCount the number of digits
	 * @return the number representation of the day
	 * @throws IllegalArgumentException if the passed-in {@code day} is less
	 * than 1 or greater than 31 or {@code null} or {@code undefined}
	 */
	private function formatDayAsNumber(day:Number, digitCount:Number):String {
		if (day < 1 || day > 31 || day == null) {
			throw new IllegalArgumentException("Argument 'day' [" + day + "] must not be less than 1 nor greater than 31 nor 'null' nor 'undefined'.", this, arguments);
		}
		if (digitCount == null) digitCount = 0;
		var string:String = day.toString();
		return (getZeros(digitCount - string.length) + string);
	}
	
	/**
	 * Formats the passed-in {@code day} into a string with the specified 
	 * {@code tokenCount}.
	 * 
	 * <p>A {@code tokenCount} less or equal than three results in a day with two 
	 * tokens. A {@code tokenCount} greater or equal than four results in a fully written
	 * out day.
	 *
	 * <p>If the passed-in {@code tokenCount} is {@code null} or {@code undefined}, 0 
	 * is used instead.
	 *
	 * @param day the day to format to a string
	 * @param tokenCount the number of favored tokens
	 * @return the string representation of the day
	 * @throws IllegalArgumentException if the passed-in {@code day} is less
	 * than 0 or greater than 6 or {@code null} or {@code undefined}
	 */
	private function formatDayAsText(day:Number, tokenCount:Number):String {
		if (day < 0 || day > 6 || day == null) {
			throw new IllegalArgumentException("Argument 'day' [" + day + "] must not be less than 0 nor greater than 6 nor 'null' nor 'undefined'.", this, arguments);
		}
		if (tokenCount == null) tokenCount = 0;
		var result:String;
		switch (day) {
			case 0:
				result = SUNDAY;
				break;
			case 1:
				result = MONDAY;
				break;
			case 2:
				result = TUESDAY;
				break;
			case 3:
				result = WEDNESDAY;
				break;
			case 4:
				result = THURSDAY;
				break;
			case 5:
				result = FRIDAY;
				break;
			case 6:
				result = SATURDAY;
				break;
		}
		if (tokenCount < 4) {
			return result.substr(0, 2);
		}
		return result;
	}
	
	/**
	 * Formats the passed-in {@code hour} into a number string from range 1 to 12.
	 * 
	 * <p>The resulting string contains only the specified {@code digitCount} if
	 * possible. This means if the hour is 3 and the {@code digitCount} 1 the resulting
	 * string contains one digit. But this is not possible with the hour 12. So in this
	 * case the resulting string contains 2 digits. If {@code digitCount} is greater
	 * than the actual number of digits, preceding 0s are added.
	 *
	 * <p>If the passed-in {@code digitCount} is {@code null} or {@code undefined}, 0
	 * is used instead.
	 *
	 * @param hour the hour to format
	 * @param digitCount the number of favored digits
	 * @return the string representation of {@code hour}
	 * @throws IllegalArgumentException if the passed-in {@code hour} is less
	 * than 0 or greater than 23 or {@code null} or {@code undefined}
	 */
	private function formatHourInAmPm(hour:Number, digitCount:Number):String {
		if (hour < 0 || hour > 23 || hour == null) {
			throw new IllegalArgumentException("Argument 'hour' [" + hour + "] must not be less than 0 nor greater than 23 nor 'null' nor 'undefined'.", this, arguments);
		}
		if (digitCount == null) digitCount = 0;
		var string:String;
		if (hour == 0) {
			// 12.toString() causes a compiler error
			string = (12).toString();
		} else if (hour > 12) {
			string = (hour - 12).toString();
		} else {
			string = hour.toString();
		}
		return (getZeros(digitCount - string.length) + string);
	}
	
	/**
	 * Formats the passed-in {@code hour} into a number string from range 0 to 23.
	 * 
	 * <p>The resulting string contains only the specified {@code digitCount} if 
	 * possible. This means if the hour is 3 and the {@code digitCount} 1 the resulting
	 * string contains one digit. But this is not possible with the hour 18. So in this
	 * case the resulting string contains 2 digits. If {@code digitCount} is greater
	 * than the actual number of digits, preceding 0s are added.
	 *
	 * <p>If the passed-in {@code digitCount} is {@code null} or {@code undefined}, 0
	 * is used instead.
	 *
	 * @param hour the hour to format
	 * @param digitCount the number of favored digits
	 * @return the string representation of {@code hour}
	 * @throws IllegalArgumentException if the passed-in {@code hour} is less
	 * than 0 or greater than 23 or {@code null} or {@code undefined}
	 */
	private function formatHourInDay(hour:Number, digitCount:Number):String {
		if (hour < 0 || hour > 23 || hour == null) {
			throw new IllegalArgumentException("Argument 'hour' [" + hour + "] must not be less than 0 nor greater than 23 nor 'null' nor 'undefined'.", this, arguments);
		}
		if (digitCount == null) digitCount = 0;
		var string:String = hour.toString();
		return (getZeros(digitCount - string.length) + string);
	}
	
	/**
	 * Formats the passed-in {@code minute} into a number string with range 0 to 59.
	 * 
	 * <p>The resulting string contains only the specified {@code digitCount} if
	 * possible. This means if the minute is 3 and the {@code digitCount} 1, the
	 * resulting string contains only one digit. But this is not possible with the
	 * minute 46. So in this case the resulting string contains 2 digits. If
	 * {@code digitCount} is greater than the actual number of digits, preceding 0s are
	 * added.
	 *
	 * <p>If the passed-in {@code digitCount} is {@code null} or {@code undefined}, 0
	 * is used instead.
	 *
	 * @param minute the minute to format
	 * @param digitCount the number of favored digits
	 * @return the string representation of the {@code minute}
	 * @throws IllegalArgumentException if the passed-in {@code minute} is
	 * less than 0 or greater than 59 or {@code null} or {@code undefined}
	 */
	private function formatMinute(minute:Number, digitCount:Number):String {
		if (minute < 0 || minute > 59 || minute == null) {
			throw new IllegalArgumentException("Argument 'minute' [" + minute + "] must not be less than 0 nor greater than 59 nor 'null' nor 'undefined'.", this, arguments);
		}
		if (digitCount == null) digitCount = 0;
		var string:String = minute.toString();
		return (getZeros(digitCount - string.length) + string);
	}
	
	/**
	 * Formats the passed-in {@code second} into a number string with range 0 to 59.
	 * 
	 * <p>The resulting string contains only the specified {@code digitCount} if
	 * possible. This means if the second is 3 and the {@code digitCount} 1, the
	 * resulting string contains only one digit. But this is not possible with the
	 * second 46. So in this case the resulting string contains 2 digits. If
	 * {@code digitCount} is greater than the actual number of digits, preceding 0s are
	 * added.
	 *
	 * <p>If the passed-in {@code digitCount} is {@code null} or {@code undefined}, 0
	 * is used instead.
	 *
	 * @param second the second to format
	 * @param digitCount the number of favored digits
	 * @return the string representation of the {@code second}
	 * @throws IllegalArgumentException if the passed-in {@code second} is
	 * less than 0 or greater than 59 or {@code null} or {@code undefined}
	 */
	private function formatSecond(second:Number, digitCount:Number):String {
		if (second < 0 || second > 59 || second == null) {
			throw new IllegalArgumentException("Argument 'second' [" + second + "] must not be less than 0 nor greater than 59 nor 'null' nor 'undefined'.", this, arguments);
		}
		if (digitCount == null) digitCount = 0;
		var string:String = second.toString();
		return (getZeros(digitCount - string.length) + string);
	}
	
	/**
	 * Formats the passed-in {@code millisecond} into a number string with range 0 to
	 * 999.
	 * 
	 * <p>The resulting string contains only the specified {@code digitCount} if
	 * possible. This means if the millisecond is 7 and the {@code digitCount} 1, the
	 * resulting string contains only one digit. But this is not possible with the
	 * millisecond 588. So in this case the resulting string contains 3 digits. If
	 * {@code digitCount} is greater than the actual number of digits, preceding 0s are
	 * added.
	 *
	 * <p>If the passed-in {@code digitCount} is {@code null} or {@code undefined}, 0
	 * is used instead.
	 *
	 * @param millisecond the millisecond to format
	 * @param digitCount the number of favored digits
	 * @return the string representation of the {@code millisecond}
	 * @throws IllegalArgumentException if the passed-in {@code millisecond}
	 * is less than 0 or greater than 999 or {@code null} or {@code undefined}
	 */
	private function formatMillisecond(millisecond:Number, digitCount:Number):String {
		if (millisecond < 0 || millisecond > 999 || millisecond == null) {
			throw new IllegalArgumentException("Argument 'millisecond' [" + millisecond + "] must not be less than 0 nor greater than 999 nor 'null' nor 'undefined'.", this, arguments);
		}
		if (digitCount == null) digitCount = 0;
		var string:String = millisecond.toString();
		return (getZeros(digitCount - string.length) + string);
	}
	
}