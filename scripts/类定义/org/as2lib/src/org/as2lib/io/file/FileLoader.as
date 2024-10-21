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

import org.as2lib.data.type.Byte;
import org.as2lib.data.holder.Map;
import org.as2lib.data.type.Bit;
import org.as2lib.env.event.EventListenerSource;
import org.as2lib.app.exec.Executable;
import org.as2lib.io.file.File;
import org.as2lib.data.type.Time;

/**
 * {@code FileLoader} is built to handle the loading of a external files.
 * 
 * <p>A {@code FileLoader} allows to get a resource and create a representation
 * of the certain file to allow proper access.
 * 
 * <p>It is build to handle the loading of one file. But it can be executed 
 * twice or more often. This is because its possible to handle more than one
 * request parallel in any system.
 * 
 * <p>Example to handle the loading of a resource:
 * <code>
 *   import org.as2lib.io.file.AbstractFileLoader;
 *   import org.as2lib.io.file.FileLoader;
 *   import org.as2lib.io.file.LoadStartListener;
 *   import org.as2lib.io.file.LoadCompleteListener;
 *   import org.as2lib.io.file.LoadProgressListener;
 *   import org.as2lib.io.file.LoadErrorListener;
 *   
 *   class Main implements
 *   	LoadStartListener,
 *   	LoadCompleteListener,
 *   	LoadErrorListener,
 *   	LoadProgressListener {
 *   
 *     public function main(loader:FileLoader):Void {
 *       loader.addListener(this);
 *       loader.load("test.txt");
 *     }
 *     
 *     public function onLoadComplete(loader:FileLoader):Void {
 *       var resource = loader.getFile();
 *       // Do anything you like....
 *     }
 *     
 *     public function onLoadError(loader:FileLoader, errorCode:String, error):Boolean {
 *       if (errorCode == AbstractFileLoader.FILE_NOT_FOUND_ERROR) {
 *       	trace("Resource could not be found"+error);
 *       }
 *       return false
 *     }
 *     
 *     public function onLoadProgress(loader:FileLoader):Void {
 *       trace("loaded: "+loader.getPercentage()+"% of "+loader.getUri());
 *     }
 *     
 *     public function onLoadStart(loader:FileLoader):Void {
 *     	 trace("started loading: "+loader.getUri());
 *     }
 *   }
 * </code>
 * 
 * @author Martin Heidegger
 * @version 2.0
 */
interface org.as2lib.io.file.FileLoader extends EventListenerSource {
	
	/**
	 * Loads a certain resource.
	 * 
	 * <p>It sends http request by using the passed-in {@code uri}, {@code method}
	 * and {@code parameters}.
	 * 
	 * <p>If you only need to listen if the {@code File} finished loading you can
	 * apply a {@code callBack} that gets called if the {@code File} is loaded.
	 * 
	 * <p>Example of using the callback:
	 * <code>
	 *   import org.as2lib.io.file.FileLoader;
	 *   import org.as2lib.app.exec.Call;
	 *   
	 *   class Main {
	 *     public function main(loader:FileLoader) {
	 *       loader.load("test.txt", null, null, new Call(this, resource); 
	 *     }
	 *     
	 *     public function finish(resource:Resource):Void {
	 *       // Processing the resource ...
	 *     }
	 *   }
	 *   
	 * </code>
	 * 
	 * @param uri location of the resource to load
	 * @param parameters (optional) parameters for loading the resource
	 * @param method (optional) POST/GET as method for submitting the parameters,
	 *        default method used if {@code method} was not passed-in is POST.
	 * @param callBack (optional) {@link Executable} to be executed after the
	 *        the resource was loaded.
	 */
	public function load(uri:String, method:String, params:Map, callBack:Executable):Void;
	
	/**
	 * Returns the URI of the resource that was requested to load.
	 * 
	 * @return URI of the resource to load
	 */
	public function getUri(Void):String;
	
	/**
	 * Returns the {@code method} to pass request parameters for request.
	 * 
	 * @return method to pass request parameters
	 */
	public function getParameterSubmitMethod(Void):String;
	
	/**
	 * Sets the {@code parameters} for the request to the resource.
	 * 
	 * <p>Returns {@code null} if no parameters has been set.
	 * 
	 * @return parameters to be passed with the resource request
	 */
	public function getParameters(Void):Map;
	
	/**
	 * Returns the loaded file.
	 * 
	 * @return the loaded file
	 * @throws org.as2lib.io.file.ResourceNotLoadedException if the resource has
	 *         not been loaded yet
	 */
	public function getFile(Void):File;
	
	/**
	 * Returns the percentage of the execution of {@code null} if its not evaluable.
	 * 
	 * @returns the percentage of the execution or {@code null} if its not evaluable
	 */
	public function getPercentage(Void):Number;
	
	/**
	 * Returns the total amount of bytes that has been loaded.
	 * 
	 * <p>Returns {@code null} if its not possible to get the loaded bytes.
	 * 
	 * @return amount of bytes that has been loaded
	 */
	public function getBytesLoaded(Void):Byte;
	
	/**
	 * Returns the total amount of bytes that will approximately be loaded.
	 * 
	 * <p>Returns {@code null} if its not possible to get the total amount of bytes.
	 * 
	 * @return amount of bytes to load
	 */
	public function getBytesTotal(Void):Byte;
	
	/**
	 * Returns the current transfer rate for the execution.
	 * 
	 * @return transfer rate in bit (per second)
	 */
	public function getTransferRate(Void):Bit;
	
	
	/**
	 * Estimates the approximate time until the resource was loaded.
	 * 
	 * @return estimated time until finish of loading
	 */
	public function getEstimatedRestTime(Void):Time;
	
	/**
	 * Estimates the approximate time for the complete loading.
	 * 
	 * @return estimated duration at the end of the loading
	 */
	public function getEstimatedTotalTime(Void):Time;
	
	/**
	 * Returns the duration it loads the certain resource.
	 * 
	 * @return time difference between start time and end time/current time.
	 */
	public function getDuration(Void):Time;
}