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
import org.as2lib.env.except.IllegalArgumentException;
import org.as2lib.env.log.level.AbstractLogLevel;
import org.as2lib.env.log.LogConfigurationParser;
import org.as2lib.env.log.LogManager;
import org.as2lib.env.log.parser.LogConfigurationParseException;
import org.as2lib.env.reflect.ClassNotFoundException;
import org.as2lib.env.reflect.NoSuchMethodException;
import org.as2lib.util.StringUtil;

/**
 * {@code XmlLogConfigurationParser} parses log configuration files in XML format.
 * 
 * <p>The root node of the configuration file must be "&lt;logging&gt;". Its child
 * nodes must correspond to {@code set*} or {@code add*} methods on the given or
 * default log manager: {@link #XmlLogConfigurationParser}. There is one exception
 * to this rule.
 * 
 * <p>The register-node in the root-node is treated in a special way. It can be
 * used to register node names with specific classes. This way you do not have to
 * specify the class-attribute multiple times for nodes with the same name.
 * 
 * <p>Every node except the register- and root-nodes are beans. A bean is in this
 * case an instance defined in an XML format. To be able to instantiate a bean the
 * bean class must be set. It is thus necessary to either register node names with
 * bean classes:
 * <code>&lt;register name="logger" class="org.as2lib.env.log.logger.SimpleHierarchicalLogger"/&gt;</code>
 * 
 * <p>or to specify the class-attribute in beans:
 * <code>&lt;logger class="org.as2lib.env.log.logger.TraceLogger"/&gt;</code>
 * 
 * <p>It is also possible to set properties. Properties are basically methods that
 * follow a specific naming convention. If you specify an attribute named {@code "name"}
 * your bean class must provide a {@code setName} method. If you specify a child
 * node named {@code "handler"}, the bean class must provide a {@code addHandler}
 * or {@code setHandler} method. Child nodes can themselves be beans.
 * 
 * <p>The level-attribute is treated in a special way. The level corresponding to
 * the level name is resolved with the {@link AbstractLogLevel#forName} method.
 * 
 * <p>It is also possible to pass constructor arguments. You do this with the
 * constructor-arg-tag. Note that the order matters! As you can see in the
 * following example, the constructor-arg can itself be a bean.
 * 
 * <code>
 *   &lt;handler class="org.as2lib.env.log.handler.TraceHandler"&gt;
 *     &lt;constructor-arg class="org.as2lib.env.log.stringifier.SimpleLogMessageStringifier"/&gt;
 *   &lt;/handler&gt;
 * </code>
 * 
 * <p>If a node- or attribute-value is a primitive type it will automatically
 * be converted. This means the strings {@code "true"} and {@code "false"} are
 * converted to the booleans {@code true} and {@code false} respectively. The
 * strings {@code "1"}, {@code "2"}, ... are converted to numbers. Only if the
 * node- or attribute-value is non of the above 'special cases' it is used as
 * string.
 * 
 * <code>
 *   &lt;handler class="org.as2lib.env.log.handler.TraceHandler"&gt;
 *     &lt;constructor-arg class="org.as2lib.env.log.stringifier.PatternLogMessageStringifier"&gt;
 *       &lt;constructor-arg&gt;false&lt;/contructor-arg&gt;
 *       &lt;constructor-arg&gt;true&lt;/contructor-arg&gt;
 *       &lt;constructor-arg&gt;HH:nn:ss.S&lt;/contructor-arg&gt;
 *     &lt;/constructor-arg&gt;
 *   &lt;/handler&gt;
 * </code>
 * 
 * <p>Your complete log configuration may look something like this:
 * <code>
 *   &lt;logging&gt;
 *     &lt;register name="logger" class="org.as2lib.env.log.logger.SimpleHierarchicalLogger"/&gt;
 *     &lt;loggerRepository class="org.as2lib.env.log.repository.LoggerHierarchy"&gt;
 *       &lt;logger name="com.simonwacker" level="INFO"&gt;
 *         &lt;handler class="org.as2lib.env.log.handler.DebugItHandler"/&gt;
 *         &lt;handler class="org.as2lib.env.log.handler.TraceHandler"/&gt;
 *       &lt;/logger&gt;
 *       &lt;logger name="com.simonwacker.MyClass" level="ERROR"&gt;
 *         &lt;handler class="org.as2lib.env.log.handler.SosHandler"/&gt;
 *       &lt;/logger&gt;
 *     &lt;/repository&gt;
 *   &lt;/logging&gt;
 * </code>
 * 
 * <p>or this:
 * <code>
 *   &lt;logging&gt;
 *     &lt;logger level="INFO" class="org.as2lib.env.log.logger.TraceLogger"/&gt;
 *   &lt;/logging&gt;
 * </code>
 * 
 * @author Simon Wacker
 */
class org.as2lib.env.log.parser.XmlLogConfigurationParser extends BasicClass implements LogConfigurationParser {
	
	/** Node name class registrations. */
	private var nodes;
	
	/** The manager to configure. */
	private var manager;
	
	/**
	 * Constructs a new {@code XmlLogConfigurationParser} instance.
	 * 
	 * <p>If {@code logManager} is {@code null} or {@code undefined}, {@link LogManager}
	 * will be used by default.
	 * 
	 * @param logManager (optional) the manager to configure with the beans specified
	 * in the log configuration XML-file
	 */
	public function XmlLogConfigurationParser(logManager) {
		if (logManager) {
			this.manager = logManager;
		} else {
			this.manager = LogManager;
		}
	}
	
	/**
	 * Parses the given {@code xmlLogConfiguration}.
	 * 
	 * @param xmlLogConfiguration the XML log configuration to parse
	 * @throws IllegalArgumentException if argument {@code xmlLogConfiguration} is
	 * {@code null} or {@code undefined}
	 * @throws LogConfigurationParseException if the bean definition could not be parsed
	 * because of a malformed xml
	 * @throws ClassNotFoundException if a class corresponding to a given class name could
	 * not be found
	 * @throws NoSuchMethodException if a method with a given name does not exist on the
	 * bean to create
	 */
	public function parse(xmlLogConfiguration:String):Void {
		if (xmlLogConfiguration == null) {
			throw new IllegalArgumentException("Argument 'xmlLogConfiguration' [" + xmlLogConfiguration + "] must not be 'null' nor 'undefined'", this, arguments);
		}
		var xml:XML = new XML();
		xml.ignoreWhite = true;
		xml.parseXML(xmlLogConfiguration);
		if (xml.status != 0) {
			throw new LogConfigurationParseException("XML log configuration [" + xmlLogConfiguration + "] is syntactically malformed.", this, arguments);
		}
		nodes = new Object();
		if (xml.lastChild.nodeName != "logging") {
			throw new LogConfigurationParseException("There must be a root node named 'logging'.", this, arguments);
		}
		var childNodes:Array = xml.firstChild.childNodes;
		for (var i:Number = 0; i < childNodes.length; i++) {
			var childNode:XMLNode = childNodes[i];
			if (childNode.nodeName == "register") {
				var name:String = childNode.attributes.name;
				var clazz:String = childNode.attributes["class"];
				if (name != null && clazz != null) {
					nodes[name] = clazz;
				}
			} else {
				var childName:String = childNode.nodeName;
				var methodName:String = generateMethodName("set", childName);
				if (!existsMethod(manager, methodName)) {
					methodName = generateMethodName("add", childName);
				}
				if (!existsMethod(manager, methodName)) {
					throw new NoSuchMethodException("Neither a method with name [" + generateMethodName("set", childName) + "] nor [" + methodName + "] does exist on log manager [" + manager + "].", this, arguments);
				}
				var childBean = parseBeanDefinition(childNode);
				manager[methodName](childBean);
			}
		}
	}
	
	/**
	 * Parses the given {@code beanDefinition} and returns the resulting bean.
	 * 
	 * @param beanDefinition the definition to create a bean of
	 * @return the bean resulting from the given {@code beanDefinition}
	 * @throws LogConfigurationParseException if the bean definition could not be parsed
	 * because of for example missing information
	 * @throws ClassNotFoundException if a class corresponding to a given class name could
	 * not be found
	 * @throws NoSuchMethodException if a method with a given name does not exist on the
	 * bean to create
	 */
	private function parseBeanDefinition(beanDefinition:XMLNode) {
		if (!beanDefinition) {
			throw new IllegalArgumentException("Argument 'beanDefinition' [" + beanDefinition + "] must not be 'null' nor 'undefined'", this, arguments);
		}
		var result = new Object();
		var beanName:String = beanDefinition.attributes["class"];
		if (beanName == null) {
			beanName = nodes[beanDefinition.nodeName];
		}
		if (beanName == null) {
			throw new LogConfigurationParseException("Node [" + beanDefinition.nodeName + "] has no class. You must either specify the 'class' attribute or register it to a class.", this, arguments);
		}
		var beanClass:Function = resolveClass(beanName);
		if (!beanClass) {
			throw new ClassNotFoundException("A class corresponding to the class name [" + beanClass + "] of node [" + beanDefinition.nodeName + "] could not be found. You either misspelled the class name or forgot to import the class in your swf.", this, arguments);
		}
		result.__proto__ = beanClass.prototype;
		result.__constructor__ = beanClass;
		var constructorArguments:Array = new Array();
		var childNodes:Array = beanDefinition.childNodes;
		for (var i:Number = 0; i < childNodes.length; i++) {
			var childNode:XMLNode = childNodes[i];
			if (childNode.nodeName == "constructor-arg") {
				if (childNode.firstChild.nodeValue == null) {
					constructorArguments.push(parseBeanDefinition(childNode));
				} else {
					constructorArguments.push(convertValue(childNode.firstChild.nodeValue));
				}
				childNodes.splice(i, 1);
				i--;
			}
		}
		beanClass.apply(result, constructorArguments);
		for (var n:String in beanDefinition.attributes) {
			if (n == "class") continue;
			var methodName:String = generateMethodName("set", n);
			if (!existsMethod(result, methodName)) {
				throw new NoSuchMethodException("A method with name [" + methodName + "] does not exist on bean of class [" + beanName + "].", this, arguments);
			}
			var value:String = beanDefinition.attributes[n];
			if (n == "level") {
				result[methodName](AbstractLogLevel.forName(value));
			} else {
				result[methodName](convertValue(value));
			}
		}
		for (var i:Number = 0; i < childNodes.length; i++) {
			var childNode:XMLNode = childNodes[i];
			var childName:String = childNode.nodeName;
			var methodName:String = generateMethodName("add", childName);
			if (!existsMethod(result, methodName)) {
				methodName = generateMethodName("set", childName);
			}
			if (!existsMethod(result, methodName)) {
				throw new NoSuchMethodException("Neither a method with name [" + generateMethodName("add", childName) + "] nor [" + methodName + "] exists on bean of class [" + beanName + "].", this, arguments);
			}
			if (childNode.firstChild.nodeValue == null) {
				result[methodName](parseBeanDefinition(childNode));
			} else {
				result[methodName](convertValue(childNode.firstChild.nodeValue));
			}
		}
		return result;
	}
	
	/**
	 * Finds the class for the given {@code className}.
	 * 
	 * @param className the name of the class to find
	 * @return the concrete class corresponding to the given {@code className}
	 */
	private function resolveClass(className:String):Function {
		return eval("_global." + className);
	}
	
	/**
	 * Generates a method name given a {@code prefix} and a {@code body}.
	 * 
	 * @param prefix the prefix of the method name
	 * @param body the body of the method name
	 * @return the generated method name
	 */
	private function generateMethodName(prefix:String, body:String):String {
		return (prefix + StringUtil.ucFirst(body));
	}
	
	/**
	 * Checks whether a method with the given {@code methodName} exists on the given
	 * {@code object}.
	 * 
	 * @param object the object that may have a method with the given name
	 * @param methodName the name of the method
	 * @return {@code true} if the method exists on the object else {@code false}
	 */
	private function existsMethod(object, methodName:String):Boolean {
		try {
			if (object[methodName]) {
				return true;
			}
		} catch (e) {
		}
		return false;
	}
	
	/**
	 * Converts the given {@code value} into its actual type.
	 * 
	 * @param value the value to convert
	 * @return the converted value
	 */
	private function convertValue(value:String) {
		if (value == null) return value;
		if (value == "true") return true;
		if (value == "false") return false;
		if (!isNaN(Number(value))) return Number(value);
		return value;
	}
	
}