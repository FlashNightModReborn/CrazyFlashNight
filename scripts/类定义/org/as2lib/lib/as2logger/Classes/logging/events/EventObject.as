/**
*	@author Ralf Siegel
*	@deprecated will use standard classes if available
*/
class logging.events.EventObject
{
	private var source:Object;
	
	public function EventObject(source:Object) 
	{
		this.source = source;
	}
	
	public function getSource():Object
	{
		return this.source;
	}
}
