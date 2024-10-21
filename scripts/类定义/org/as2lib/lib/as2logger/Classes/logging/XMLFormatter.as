import logging.IFormatter;
import logging.LogRecord;

/**
*	A XML formatter implementation.
*
*	@author Ralf Siegel
*/
class logging.XMLFormatter implements IFormatter
{
	/**
	*	@see logging.IFormatter
	*/
	public function format(logRecord:LogRecord):String
	{
		var node:XMLNode = new XMLNode(1, "logRecord");
		
		node.attributes.date = formatDateTime(logRecord.getDate());
		node.attributes.name = logRecord.getLoggerName();
		node.attributes.level = logRecord.getLevel().getName();
		node.appendChild(new XMLNode(4, logRecord.getMessage()));		
		
		return node.toString();
	}
	
	/**
	*	Formats a given date according to the W3C-Standard dateTime 
	*
	*	@see http://www.w3.org/TR/xmlschema-2/#isoformats
	*
	*	@param the Date object
	*	@return the formatted datetime string
	*/
	private static function formatDateTime(date:Date):String 
	{
		var dateString:String = new String();
		
		dateString += date.getFullYear() + "-" + formatData(date.getMonth() + 1) + "-" + formatData(date.getDate());
		dateString += "T" + formatData(date.getHours()) + ":" + formatData(date.getMinutes()) + ":" + formatData(date.getSeconds());		
		
		return dateString;		
	}
	
	/**
	*	Decorates number with a trailing 0 if needed
	*	
	*	@param the number to be checked
	*	@return the formatted number string 
	*/
	private static function formatData(data:Number):String
	{
		return (data < 10) ? "0" + data : "" + data;
	}
}