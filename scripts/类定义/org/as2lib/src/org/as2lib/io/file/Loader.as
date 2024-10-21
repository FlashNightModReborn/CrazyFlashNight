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

import org.as2lib.app.exec.Executable;
import org.as2lib.data.holder.Map;
import org.as2lib.env.event.EventSupport;
import org.as2lib.env.overload.Overload;
import org.as2lib.io.file.CompositeTextFileFactory;
import org.as2lib.io.file.FileLoader;
import org.as2lib.io.file.LoadCompleteListener;
import org.as2lib.io.file.LoadErrorListener;
import org.as2lib.io.file.LoadProgressListener;
import org.as2lib.io.file.LoadStartListener;
import org.as2lib.io.file.SwfFileLoader;
import org.as2lib.io.file.TextFileFactory;
import org.as2lib.io.file.TextFileLoader;
import org.as2lib.io.file.XmlFileFactory;

/**
 * {@code Loader} is a central distributor for loading files.
 * 
 * <p>{@code Loader} should be used for loading files if you do not like to
 * bother about the certain loading mechianism.
 * 
 * <p>If you want to reduces the occurences of {@code Loader} instances you can
 * use {@code Loader.getInstance} that contains a {@code Loader} instance.
 * 
 * <p>{@code Loader.getInstance().load("uri")} is available to load any common file.
 * 
 * <p>Loading a external {@code .swf} requires a {@code MovieClip} to load therefore
 * you should use {@code loadSwf} or use the overloaded {@code load} with passing
 * the {@code MovieClip} as second parameter.
 * 
 * <p>{@code Loader} uses paralell loading, this means it starts as much requests
 * as allowed paralell.
 * 
 * <p>{@code Loader} publishes the same event line {@link FileLoader}.
 * 
 * <p>Example for using {@code Loader.load}:
 * <code>
 *   import org.as2lib.io.file.Loader;
 *   
 *   var loader:Loader = Loader.getInstance();
 *   loader.addListener(...); // Add your listener for the file loading.
 *   loader.load("content.txt"); 
 *   loader.load("content.xml");
 *   loader.load("content.swf", _root.createEmptyMovieClip("content", _root.getNextHighestDepth());
 * </code>
 * 
 * @author Martin Heidegger
 * @version 1.0
 */
class org.as2lib.io.file.Loader extends EventSupport
	implements LoadStartListener,
		LoadCompleteListener,
		LoadErrorListener,
		LoadProgressListener {
	
	/** Instance of the Loader. */
	private static var instance:Loader;
	
	/**
	 * Returns a {@code Loader} instance.
	 * 
	 * @return {@code Loader} instance.
	 */
	public static function getInstance():Loader {
		if (!instance) {
			instance = new Loader();
		}
		return instance;
	}	
	
	/** Factory to create {@code TextFile} implementations, configurable. */
	private var textFileFactory:TextFileFactory;
	
	/**
	 * Constructs a new {@code Loader}.
	 */
	public function Loader(Void) {
		var factory:CompositeTextFileFactory = new CompositeTextFileFactory();
		factory.putTextFileFactoryByExtension("xml", new XmlFileFactory());
		textFileFactory = factory;
	}
	
	/**
	 * Loads a {@code .swf} to a {@code MovieClip} instance.
	 * 
	 * @param uri location of the resource to load
	 * @param mc {@code MovieClip} as container for the {@code .swf} content
	 * @param parameters (optional) parameters for loading the resource
	 * @param method (optional) POST/GET as method for submitting the parameters,
	 *        default method used if {@code method} was not passed-in is POST.
	 * @param callBack (optional) {@link Executable} to be executed if the resource
	 *        was complete loaded
	 * @return {@code SwfFileLoader} that loads the resource
	 */
	public function loadSwf(uri:String, mc:MovieClip, parameters:Map,
			method:String, callBack:Executable):SwfFileLoader {
		var fL:SwfFileLoader = new SwfFileLoader(mc);
		fL.addListener(this);
		fL.load(uri, method, parameters);
		return fL;
	}
	
	/**
	 * Loads a external text file.
	 * 
	 * @param uri location of the resource to load
	 * @param method (optional) POST/GET as method for submitting the parameters,
	 *        default method used if {@code method} was not passed-in is POST.
	 * @param parameters (optional) parameters for loading the resource
	 * @param callBack (optional) {@link Executable} to be executed if the resource
	 *        was complete loaded
	 * @return {@code TextFileLoader} that loads the certain file
	 */
	public function loadText(uri:String, method:String, parameters:Map,
			callBack:Executable):TextFileLoader {
		var fL:TextFileLoader = new TextFileLoader(textFileFactory);
		fL.addListener(this);
		fL.load(uri, method, parameters);
		return fL;
	}
	
	/**
	 * Defines the {@code TextFileFactory} to be used by {@code loadText}.
	 * 
	 * <p>{@code loadText} requires a {@code TextFileFactory} to generate the
	 * concrete {@code TextFile} instance that represents the resource. This 
	 * methods allows configuration of the supported file formats.
	 * 
	 * <p>The default configuration contains a {@link CompositeTextFileFactory} with
	 * {@link org.as2lib.io.file.SimpleTextFileFactory} as default
	 * {@code TextFileFactory} and {@link XmlFileFactory} for the extension "xml".
	 * 
	 * @param textFileFactory {@code TextFileFactory} to be used by {@code loadFile}
	 */
	public function setFileFactory(textFileFactory:TextFileFactory):Void {
		this.textFileFactory = textFileFactory;
	}
	
	/**
	 * @overload #loadSwf
	 * @overload #loadText
	 */
	public function load(url, target) {
		var overload:Overload = new Overload();
		overload.addHandler([String, MovieClip, String, Map, Executable], loadSwf);
		overload.addHandler([String, MovieClip, String, Map], loadSwf);
		overload.addHandler([String, MovieClip, String], loadSwf);
		overload.addHandler([String, MovieClip], loadSwf);
		overload.addHandler([String, String, Map, Executable], loadText);
		overload.addHandler([String, String, Map], loadText);
		overload.addHandler([String, Map], loadText);
		overload.addHandler([String], loadText);
		return overload.forward(arguments);
	}
	
	/**
	 * (implementation detail) Handles the response of a finished {@code FileLoader}.
	 * 
	 * @param fileLoader {@code FileLoader} that loaded the certain resource
	 */
	public function onLoadComplete(fileLoader:FileLoader):Void {
		var completeDistributor:LoadCompleteListener =
			distributorControl.getDistributor(LoadCompleteListener);
		completeDistributor.onLoadComplete(fileLoader);
	}

	/**
	 * (implementation detail) Handles the response if a {@code FileLoader}
	 * started working.
	 * 
	 * @param resourceLoader {@code FileLoader} that loaded the certain resource
	 */
	public function onLoadStart(resourceLoader:FileLoader):Void {
		var errorDistributor:LoadStartListener =
			distributorControl.getDistributor(LoadStartListener);
		errorDistributor.onLoadStart(resourceLoader);
	}

	/**
	 * (implementation detail) Handles the response if a {@code FileLoader}
	 * could not find a resource.
	 * 
	 * @param resourceLoader {@code FileLoader} that loaded the certain resource
	 */
	public function onLoadError(resourceLoader:FileLoader, errorCode:String, error):Boolean {
		var errorDistributor:LoadErrorListener =
			distributorControl.getDistributor(LoadErrorListener);
		return errorDistributor.onLoadError(resourceLoader, errorCode, error);
	}

	/**
	 * (implementation detail) Handles the response if a {@code FileLoader}
	 * progressed loading.
	 * 
	 * @param resourceLoader {@code FileLoader} that loaded the certain resource
	 */
	public function onLoadProgress(resourceLoader:FileLoader):Void {
		var progressDistributor:LoadProgressListener =
			distributorControl.getDistributor(LoadProgressListener);
		progressDistributor.onLoadProgress(resourceLoader);
	}
}