import logging.events.PropertyChangeEvent;

/**
*	@author Ralf Siegel
*	@deprecated will use standard classes if available
*/
interface logging.events.IPropertyChangeListener {
	
	public function onPropertyChanged(event:PropertyChangeEvent):Void;
}