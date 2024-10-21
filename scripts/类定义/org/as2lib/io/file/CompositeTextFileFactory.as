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

import org.as2lib.core.BasicClass;
import org.as2lib.data.holder.Map;
import org.as2lib.data.holder.map.HashMap;
import org.as2lib.data.type.Byte;
import org.as2lib.env.overload.Overload;
import org.as2lib.io.file.SimpleTextFileFactory;
import org.as2lib.io.file.TextFile;
import org.as2lib.io.file.TextFileFactory;

/**
 * {@code CompositeTextFileFactory} uses different {@code TextFileFactory}
 * implementations depending to the extension of the passed-in {@code uri} in
 * {@code FileFactory.createTextFile}.
 * 
 * <p>Its a common case that different file extensions are used for different
 * kinds of file formats. {@code CompositeTextFileFactory} allows different processing
 * of resources depending to the extension of the loaded file.
 * 
 * <p>If a certain extension has not been specially set it uses the {@code defaultTextFileFactory}
 * to be set with {@code setDefaultTextFileFactory}.
 * 
 * <p>It uses {@link SimpleTextFileFactory} as default if no other has been set.
 * 
 * @author Martin Heidegger
 * @version 1.1
 */
class org.as2lib.io.file.CompositeTextFileFactory extends BasicClass
	implements TextFileFactory {

	/** 
	 * {@code TextFileFactory} to be used if no other {@code TextFileFactory} 
	 * is available.
	 */
    private var defaultTextFileFactory:TextFileFactory;
    
    /** Maps {@code TextFileFactory}s to file extensions. */
    private var extensionFactories:Map;
    
    /**
     * Constructs a new {@code CompositeTextFileFactory}.
     */
    public function CompositeTextFileFactory(Void) {
    	defaultTextFileFactory = new SimpleTextFileFactory();
    	extensionFactories = new HashMap();
    }

	/**
	 * Creates a {@code TextFile} implementation depending to the set {@code TextFileFactory}s.
	 * 
	 * @param source content of the {@code TextFile} to create
	 * @param size size in {@link Byte} of the loaded resource
	 * @param uri location of the loaded resource
	 * @return {@code TextFile} that represents the resource
	 */
	public function createTextFile(source:String, size:Byte, uri:String):TextFile {
		var factory:TextFileFactory = 
			extensionFactories.get(uri.substr(uri.lastIndexOf(".")));
		if (!factory) {
			factory = defaultTextFileFactory;
		}
		return factory.createTextFile(source, size, uri);
	}
	
	/**
	 * Sets the default {@code TextFileFactory} to be used in default case.
	 * 
	 * <p>If no other set {@code TextFileFactory} applies to the requested
	 * {@code uri} the passed-in {@code textFileFactory} will be used.
	 * 
	 * @param textFileFactory {@code TextFileFactory} to be used in default case
	 */
	public function setDefaultTextFileFactory(textFileFactory:TextFileFactory):Void {
		defaultTextFileFactory = textFileFactory;
	}
	
	/**
	 * @overload #putTextFileFactoryByExtension
	 * @overload #putTextFileFactoryByExtensions
	 */
	public function putTextFileFactory() {
		var o:Overload = new Overload(this);
		o.addHandler(String, putTextFileFactoryByExtension);
		o.addHandler(Array, putTextFileFactoryByExtensions);
		return o.forward(arguments);
	}
	
	/**
	 * Sets a certain {@code TextFileFactory} to be used for files with the
	 * passed-in {@code extension}.
	 * 
	 * <p>The passed-in extension should not contain a leading ".".
	 * 
	 * <p>Proper example:
	 * <code>
	 *   var textFileFactory:CompositeFileFactory = new CompositeTextFileFactory();
	 *   textFileFactory.putTextFileFactoryByExtension("txt", new SimpleTextFileFactory());
	 * </code>
	 * 
	 * @param extension extension of the file that should be recognized by the
	 * 		  passed-in {@code textFileFactory}
	 * @param textFileFactory {@code TextFileFactory} that creates the files
	 */
	public function putTextFileFactoryByExtension(extension:String,
			fileFactory:TextFileFactory):Void {
		extensionFactories.put(extension, fileFactory);
	}
	
	/**
	 * Sets a certain {@code TextFileFactory} to be used for files with one extension
	 * of the passed-in {@code extensions}.
	 * 
	 * <p>Any of the passed-in extension should not contain a leading ".".
	 * 
	 * <p>Proper example:
	 * <code>
	 *   var textFileFactory:CompositeTextFileFactory = new CompositeTextFileFactory();
	 *   textFileFactory.putTextFileFactoryByExtensions(["txt", "prop"],
	 *   	new SimpleTextFileFactory());
	 * </code>
	 * 
	 * @param extensions list of extensions of files that should be recognized
	 *        by the passed-in {@code textFileFactory}
	 * @param fileFactory {@code TextFileFactory} that creates the files
	 */
	public function putTextFileFactoryByExtensions(extensions:Array,
			fileFactory:TextFileFactory):Void {
		var i:Number;
		for( i=0; i<extensions.length; i++) {
			putTextFileFactoryByExtension(extensions[i], fileFactory);
		}
	}
}