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

import org.as2lib.io.file.AbstractFileLoader;
import org.as2lib.data.type.Byte;
import org.as2lib.data.holder.Iterator;
import org.as2lib.env.event.impulse.FrameImpulse;
import org.as2lib.env.event.impulse.FrameImpulseListener;
import org.as2lib.io.file.FileLoader;
import org.as2lib.io.file.FileNotLoadedException;
import org.as2lib.data.type.Time;
import org.as2lib.app.exec.Executable;
import org.as2lib.data.holder.Map;
import org.as2lib.io.file.File;
import org.as2lib.io.file.SwfFile;

/**
 * {@code SwfLoader} is a implementation of {@link FileLoader} to load
 * files with {@code loadMovie} (usually {@code .swf} files}.
 * 
 * <p>Any content to be loaded with {@code MovieClip#loadMovie} can be load with
 * {@code SwfLoader} to a concrete {@code MovieClip} instance that has to be
 * passed-in with the constructor.
 *
 * <p>{@code SwfLoader} represents the time consuming part of accessing external
 * {@code .swf}' ({@code SwfFile} is the handleable part} and therefore
 * contains a event system to add listeners to listen to the concrete events.
 * It is possible to add listeners using {@code addListener}.
 * 
 * <p>Example listener:
 * <code>
 *   import org.as2lib.io.file.AbstractFileLoader;
 *   import org.as2lib.io.file.LoadProgressListener;
 *   import org.as2lib.io.file.LoadStartListener;
 *   import org.as2lib.io.file.LoadCompleteListener;
 *   import org.as2lib.io.file.LoadErrorListener;
 *   import org.as2lib.io.file.FileLoader;
 *   import org.as2lib.io.file.SwfFile;
 *   
 *   class MySwfListener implements 
 *        LoadProgressListener, LoadStartListener,
 *        LoadCompleteListener, LoadErrorListener {
 *        
 *     public function onLoadComplete(fileLoader:FileLoader):Void {
 *       var swf:SwfFile = SwfFile(fileLoader.getFile());
 *       if (swf != null) {
 *         // Proper swf available
 *       } else {
 *         // Wrong event handled
 *       }
 *     }
 *     
 *     public function onLoadError(fileLoader:FileLoader, errorCode:String, error):Void {
 *       if (errorCode == AbstractFileLoader.FILE_NOT_FOUND) {
 *         var notExistantUrl = error;
 *         // Use that url
 *       }
 *     }
 *     
 *     public function onLoadStart(fileLoader:FileLoader) {
 *       // show that this file just gets loaded
 *     }
 *     
 *     public function onLoadProgress(fileLoader:FileLoader) {
 *       // update the percentage display with fileLoader.getPercentage();
 *     }
 *   }
 * </code>
 * 
 * <p>Example of the usage:
 * <code>
 *   import org.as2lib.io.file.SwfLoader;
 *   
 *   var swfLoader:SwfLoader = new SwfLoader();
 *   swfLoader.addListener(new MySwfListener());
 *   swfLoader.load("test.swf");
 * </code>
 * 
 * @author Martin Heidegger
 * @version 1.1
 */
class org.as2lib.io.file.SwfFileLoader extends AbstractFileLoader
	implements FileLoader, FrameImpulseListener {
	
	/** Time until the method breaks with "File not found". */
	public static var TIMEOUT:Time = new Time(3000);
	
	/** Helper for loading the {@code File}. */
	private var holder:MovieClip;
	
	/** Loaded {@code File}. */
	private var result:File;
	
	/**
	 * Constructs a new {@code SwfLoader} instance.
	 * 
	 * @param holder {@code MovieClip} instance to load the {@code .swf} into
	 */
	public function SwfFileLoader(holder:MovieClip) {
		this.holder = holder;
	}
	
	/**
	 * Loads a certain {@code .swf} by a http request.
	 * 
	 * <p>It sends http request by using the passed-in {@code uri}, {@code method}
	 * and {@code parameters} with {@code .loadMovie}. 
	 * 
	 * <p>If you only need to listen if the {@code SwfFile} finished loading
	 * you can apply a {@code callBack} that gets called if the {@code File} is loaded.
	 * 
	 * @param uri location of the file to load
	 * @param parameters (optional) parameters for loading the file
	 * @param method (optional) POST/GET as method for submitting the parameters,
	 *        default method used if {@code method} was not passed-in is POST.
	 * @param callBack (optional) {@link Executable} to be executed after the
	 *        the file was loaded.
	 */
	public function load(uri:String, method:String, parameters:Map, callBack:Executable):Void {
		super.load(uri, method, parameters, callBack);
		result = null;
		if(parameters) {
			var keys:Iterator = parameters.keyIterator();
			while (keys.hasNext()) {
				var key = keys.next();
				holder[key.toString()] = parameters.get(key);
			}
		}
		holder.loadMovie(uri, method);
		sendStartEvent();
		FrameImpulse.getInstance().addFrameImpulseListener(this);
	}
	
	/**
	 * Returns the loaded file.
	 * 
	 * @return file that has been loaded
	 * @throws FileNotLoadedException if the file has not been loaded yet
	 */
	public function getFile(Void):File {
		if (!result) {
			throw new FileNotLoadedException("No File has been loaded.", this, arguments);
		}
		return result;
	}
	
	/**
	 * Returns the total amount of bytes that has been loaded.
	 * 
	 * <p>Returns {@code null} if its not possible to get the loaded bytes.
	 * 
	 * @return amount of bytes that has been loaded
	 */
	public function getBytesLoaded(Void):Byte {
		var result:Number = holder.getBytesLoaded();
		if (result >= 0) {
			return new Byte(result);
		}
		return null;
	}
	
	/**
	 * Returns the total amount of bytes that will approximately be loaded.
	 * 
	 * <p>Returns {@code null} if its not possible to get the total amount of bytes.
	 * 
	 * @return amount of bytes to load
	 */
	public function getBytesTotal(Void):Byte {
		var total:Number = holder.getBytesTotal();
		if (total >= 0) {
			return new Byte(total);
		}
		return null;
	}
	
	/**
	 * Handles a {@code frame} execution.
	 * 
	 * <p>Helper that checks every frame if the {@code .swf} finished loading.
	 * 
	 * @param impulse {@code FrameImpulse} that sent the event
	 */
	public function onFrameImpulse(impulse:FrameImpulse):Void {
		if (checkFinished()) {
			successLoading();
			return;
		}
		if (checkTimeout()) {
			failLoading();
		}
	}
	
	/**
	 * Checks if the {@code .swf} finished loading.
	 * 
	 * @return {@code true} if the {@code .swf} finished loading
	 */
	private function checkFinished():Boolean {
		holder = eval(""+holder._target);
		if ( holder.getBytesTotal() > 10 
			&& holder.getBytesTotal() - holder.getBytesLoaded() < 10) { 
			return true;
		}
		return false;
	}
	
	/**
	 * Checks if the {@code TIMEOUT} has been exceeded by the durating.
	 * 
	 * @return {@code true} if the duration exceeded the {@code TIMEOUT} value
	 */
	private function checkTimeout():Boolean {
		if (holder.getBytesTotal() > 10) {
			return false;
		}
		return (getDuration().valueOf() > TIMEOUT);
	}
	
	/**
	 * Handles if the loading of file was successful.
	 */
	private function successLoading(Void):Void {
		finished = true;
		started = false;
		result = new SwfFile(holder, uri, getBytesTotal());
		endTime = getTimer();
		sendCompleteEvent();
		tearDown();
	}
	
	/**
	 * Handles if the loading of the file failed.
	 */
	private function failLoading(Void):Void {
		finished = true;
		started = false;
		endTime = getTimer();
		sendErrorEvent(FILE_NOT_FOUND_ERROR, uri);
		tearDown();
	}
	
	/**
	 * Removes instance from listening to {@code FrameImpulse}.
	 * 
	 * @see #onFrameImpulse
	 */
	private function tearDown(Void):Void {
		FrameImpulse.getInstance().removeListener(this);
	}

}