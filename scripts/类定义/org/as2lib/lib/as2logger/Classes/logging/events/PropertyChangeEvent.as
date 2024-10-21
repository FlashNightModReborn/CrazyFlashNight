import logging.events.EventObject;

/**
*	@author Ralf Siegel
*	@deprecated will use standard classes if available
*/
class logging.events.PropertyChangeEvent extends EventObject
{
	public function PropertyChangeEvent(source:Object)
	{
		super(source);
	}
}
