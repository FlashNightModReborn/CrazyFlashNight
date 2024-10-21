//****************************************************************************
//*																			 *
//*					  COPYRIGHT 2004 Scott Hyndman							 *
//*						 ALL RIGHTS RESERVED					   			 *
//*																			 *
//****************************************************************************


/**
 * Represents a box type. //! Not sure what this actually does.
 *
 * @author Scott Hyndman
 */
class org.actionstep.constants.NSBoxType 
{	
	public static var NSBoxPrimary:NSBoxType 	= new NSBoxType(0);
	public static var NSBoxSecondary:NSBoxType 	= new NSBoxType(1);
	public static var NSBoxSeparator:NSBoxType 	= new NSBoxType(2);
	public static var NSBoxOldStyle:NSBoxType 	= new NSBoxType(3);
	
	public var value:Number;
	
	private function NSBoxType(value:Number)
	{
		this.value = value;
	}
}
