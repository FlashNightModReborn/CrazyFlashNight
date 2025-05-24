import org.as2lib.core.BasicInterface;
import org.as2lib.data.type.Byte;

/**
 * {@code File} represents any file.
 * 
 * <p>Any {@code File} has to have a location and a size.
 * 
 * <p>{@link FileLoader} contains the functionality to load a certain
 * file.
 * 
 * @author Martin Heidegger
 * @version 1.0
 */
interface org.as2lib.io.file.File extends BasicInterface {
	
	/**
	 * Returns the location of the {@code File} corresponding to the content.
	 * 
	 * <p>Note: Might be the URI of the resource or null if its not requestable
	 * or the internal location corresponding to the instance path (if its without
	 * any connection to a real file).
	 * 
	 * @return location of the resource related to the content
	 */
	public function getLocation(Void):String;
	
	/**
	 * Returns the size of the {@code File} in bytes.
	 * 
	 * @return size of the {@code File} in bytes
	 */
	public function getSize(Void):Byte;
}