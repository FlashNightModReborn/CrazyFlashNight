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

import org.as2lib.data.holder.Map;
import org.as2lib.data.type.Bit;
import org.as2lib.data.type.Byte;
import org.as2lib.env.event.distributor.CompositeEventDistributorControl;
import org.as2lib.io.file.LoadStartListener;
import org.as2lib.io.file.LoadCompleteListener;
import org.as2lib.io.file.LoadProgressListener;
import org.as2lib.io.file.LoadErrorListener;
import org.as2lib.io.file.FileLoader;
import org.as2lib.io.file.File;
import org.as2lib.app.exec.Executable;
import org.as2lib.app.exec.AbstractTimeConsumer;
import org.as2lib.env.except.IllegalArgumentException;

/**
 * {@code AbstractFileLoader} is a abstract implementation for a {@code FileLoader}.
 * 
 * <p>Extend {@code AbstractFileLoader} to implement most methods required
 * for a {@code ResourceLoader}.
 * 
 * @author Martin Heidegger
 * @version 1.0
 */
class org.as2lib.io.file.AbstractFileLoader extends AbstractTimeConsumer implements FileLoader {
	
	/** Error code if a certain file could not be found. */
	public static var FILE_NOT_FOUND_ERROR:String = "File not found";
	
	/** URI for the request. */
	private var uri:String;
	
	/** Method to pass resource request parameters. */
	private var method:String = "POST";
	
	/** Parameters to be used for the resource request. */
	private var parameters:Map;
	
	/** Faster access to internal event handling. */
	private var dC:CompositeEventDistributorControl;
	
	/** {@link Executable} to be executed on finish of loading. */
	private var callBack:Executable;
	
	/**
	 * Constructs a new {@code AbstractFileLoader}
	 * 
	 * <p>Pass all arguments from the extended constructor by using super to 
	 * add the parameters to the instance.
	 */
	function AbstractFileLoader(Void) {
		super();
		dC = distributorControl;
		acceptListenerType(LoadStartListener);
		acceptListenerType(LoadCompleteListener);
		acceptListenerType(LoadProgressListener);
		acceptListenerType(LoadErrorListener);
	}
	
	/**
	 * Returns for the location of the resource that was requested to load.
	 * 
	 * @return location of the resource to load
	 */
	public function getUri(Void):String {
		return uri;
	}
	
	/**
	 * Returns the pecentage of the file that has been loaded.
	 * 
	 * <p>Evaluates the current percentage of the execution by using
	 * {@code getBytesTotal} and {@code getBytesLoaded}.
	 * 
	 * <p>Returns {@code null} if the percentage is not evaluable
	 * 
	 * @return percentage of the file that has been loaded
	 */
	public function getPercentage(Void):Number {
		if (hasStarted() || hasFinished()) {
			var percentage:Number = (
				100  
				/ getBytesTotal().getBytes()
				* getBytesLoaded().getBytes()
				);
			if (percentage >= 100) {
				percentage = 100;
			}
			return percentage;
		} else {
			return null;
		}
	}
	/**
	 * Returns the current transfer rate for the execution.
	 * 
	 * <p>Evalutes the transfer rate by using {@code getBytesLoaded} and
	 * {@code getDuration}.
	 * 
	 * @return transfer rate in bit (per second)
	 */
	public function getTransferRate(Void):Bit {
		return new Bit(getBytesLoaded().getBit()/getDuration().inSeconds());
	}

	/**
	 * Stub implementation for the amount of bytes that were loaded.
	 * 
	 * @return {@code null} for not evaluable
	 */
	public function getBytesTotal(Void):Byte {
		return null;
	}
	
	/**
	 * Stub implementation for the amount of bytes to be loaded.
	 * 
	 * @return {@code null} for not evaluable
	 */
	public function getBytesLoaded(Void):Byte {
		return null;
	}
	
	/**
	 * Prepares the loading of a certain file.
	 * 
	 * <p>To be overwritten with the concrete load implentation. Do not forget 
	 * to apply super.load().
	 * 
	 * @param uri location of the resource to load
	 * @param parameters (optional) parameters for loading the resource
	 * @param method (optional) POST/GET as method for submitting the parameters,
	 *        default method used if {@code method} was not passed-in is POST.
	 * @param callBack (optional) {@link Executable} to be executed after the
	 *        the resource was loaded.
	 */
	public function load(uri:String, method:String, parameters:Map, callBack:Executable):Void {
		if (!uri) {
			throw new IllegalArgumentException("Url has to be set for starting the process.", this, arguments);
		}
		this.uri = uri;
		this.parameters = parameters;
		this.callBack = callBack;
		this.method = (method.toUpperCase() == "GET") ? "GET" : "POST";
		started = true;
		finished = false;
		startTime = getTimer();
	}
	
	/**
	 * Returns the {@code method} to pass request parameters for request.
	 * 
	 * @return method to pass request parameters
	 */
	public function getParameterSubmitMethod(Void):String {
		return method;
	}

	/**
	 * Sets the {@code parameters} for the request to the resource.
	 * 
	 * <p>Returns {@code null} if no parameters has been set.
	 * 
	 * @return parameters to be passed with the resource request
	 */
	public function getParameters(Void):Map {
		return parameters;
	}

	/**
	 * Returns the loaded resource.
	 * 
	 * @return the loaded resource
	 * @throws org.as2lib.io.file.ResourceNotLoadedException if the resource has
	 *         not been loaded yet
	 */
	public function getFile(Void):File {
		return null;
	}
	
	/**
	 * Internal helper to send the start event.
	 */
	private function sendStartEvent(Void):Void {
		var startDistributor:LoadStartListener
			= dC.getDistributor(LoadStartListener);
		startDistributor.onLoadStart(this);
	}
	
	/**
	 * Internal helper to send the error event.
	 * 
	 * @param code errorcode for the certain error
	 * @param error information to the certain error
	 */
	private function sendErrorEvent(code:String, error):Void {
		var errorDistributor:LoadErrorListener
			= dC.getDistributor(LoadErrorListener);
		errorDistributor.onLoadError(this, code, error);
	}
	
	/**
	 * Internal helper to send the complete event.
	 * 
	 * <p>Event to be sent if the file was completly loaded.
	 */
	private function sendCompleteEvent(Void):Void {
		var completeDistributor:LoadCompleteListener
			= dC.getDistributor(LoadCompleteListener);
		completeDistributor.onLoadComplete(this);
		callBack.execute(this);
	}
	
	/**
	 * Internal helper to send the progress event.
	 */
	private function sendProgressEvent(Void):Void {
		var completeDistributor:LoadProgressListener
			= dC.getDistributor(LoadProgressListener);
		completeDistributor.onLoadProgress(this);
	}

}