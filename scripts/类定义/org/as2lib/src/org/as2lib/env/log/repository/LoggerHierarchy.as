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
import org.as2lib.env.except.IllegalStateException;
import org.as2lib.env.log.LoggerRepository;
import org.as2lib.env.log.ConfigurableHierarchicalLogger;
import org.as2lib.env.log.Logger;
import org.as2lib.env.log.logger.SimpleHierarchicalLogger;
import org.as2lib.env.log.logger.RootLogger;
import org.as2lib.env.log.level.AbstractLogLevel;
import org.as2lib.env.log.repository.ConfigurableHierarchicalLoggerFactory;

/**
 * {@code LoggerHierarchy} organizes loggers in a hierarchical structure.
 *
 * <p>It works only with loggers that are capable of acting properly in a hierarchy.
 * These loggers must implement the {@link ConfigurableHierarchicalLogger}
 * interface.
 * 
 * <p>The names of the loggers must be fully qualified and the differnt parts of
 * the preceding structure/path must be separated by periods.
 *
 * <p>This repository takes care that the parents of all loggers are correct and
 * updates them if necessary. The hierarchical loggers themselves are responsible
 * of obtaining the level and handlers from its parents if necessary and desired.
 *
 * <p>Example:
 * <code>
 *   var repository:LoggerHierarchy = new LoggerHierarchy();
 *   LogManager.setLoggerRepository(repository);
 *   var traceLogger:SimpleHierarchicalLogger = new SimpleHierarchicalLogger("org.as2lib");
 *   traceLogger.addHandler(new TraceHandler());
 *   repository.addLogger(traceLogger);
 *   // in some other class or something
 *   var myLogger:Logger = LogManager.getLogger("org.as2lib.mypackage.MyClass");
 *   myLogger.warning("Someone did something he should not do.");
 * </code>
 * 
 * <p>The message is traced because the namespace of {@code myLogger} is the same
 * as the one of {@code traceLogger}. You can of course add multiple handlers to
 * one logger and also multiple loggers to different namespaces.
 *
 * @author Simon Wacker
 */
class org.as2lib.env.log.repository.LoggerHierarchy extends BasicClass implements LoggerRepository {
	
	/** Stores the root of this hierarchy. */
	private var root:ConfigurableHierarchicalLogger;
	
	/** Stores added loggers. */
	private var loggers:Array;
	
	/** This factory is used when no custom factory is specified. */
	private var defaultLoggerFactory:ConfigurableHierarchicalLoggerFactory;
	
	/**
	 * Constructs a new {@code LoggerHierarchy} instance.
	 *
	 * <p>Registers the root logger with name {@code "root"} if the {@code root}'s
	 * {@code getName} method returns {@code null} or {@code undefined}. Otherwise it
	 * will be registered with the name returned by the {@code root}'s {@code getName}
	 * method.
	 *
	 * <p>If the passed-in {@code root} is {@code null} or {@code undefined} an
	 * instance of type {@link RootLogger} with name {@code "root"} and log level
	 * {@code ALL} will be used instead.
	 *
	 * @param root the root of the hierarchy
	 */
	public function LoggerHierarchy(root:ConfigurableHierarchicalLogger) {
		if (!root) root = new RootLogger(AbstractLogLevel.ALL);
		this.root = root;
		loggers = new Array();
		if (root.getName() == null) {
			loggers["root"] = root;
		} else {
			loggers[root.getName()] = root;
		}
	}
	
	/**
	 * Returns either the factory set via {@link #setDefaultLoggerFactory} or the
	 * default one.
	 *
	 * <p>The default factory returns instances of type
	 * {@link SimpleHierarchicalLogger}.
	 *
	 * @return the factory used as default
	 */
	public function getDefaultLoggerFactory(Void):ConfigurableHierarchicalLoggerFactory {
		if (!defaultLoggerFactory) defaultLoggerFactory = getNormalLoggerFactory();
		return defaultLoggerFactory;
	}
	
	/**
	 * Returns the normal factory that returns instances of class
	 * {@link SimpleHierarchicalLogger}.
	 *
	 * @return the normal factory
	 */
	private function getNormalLoggerFactory(Void):ConfigurableHierarchicalLoggerFactory {
		var result:ConfigurableHierarchicalLoggerFactory = getBlankConfigurableHierarchicalLoggerFactory();
		// Not function(Void) because mtasc compiler complains with the following message:
		// type error Local variable redefinition : Void
		result.getLogger = function():ConfigurableHierarchicalLogger {
			return new SimpleHierarchicalLogger();
		};
		return result;
	}
	
	/**
	 * Sets the factory used to obtain loggers that have not been set manually before.
	 *
	 * @param defaultLoggerFactory the factory to use as default
	 */
	public function setDefaultLoggerFactory(defaultLoggerFactory:ConfigurableHierarchicalLoggerFactory):Void {
		this.defaultLoggerFactory = defaultLoggerFactory;
	}
	
	/**
	 * Returns the root logger of this hierarchy.
	 *
	 * @return the root logger of this hierarchy
	 */
	public function getRootLogger(Void):Logger {
		return root;
	}
	
	/**
	 * Adds a new logger to this hierarchical repository.
	 *
	 * <p>The logger is automatically integrated into the hierarchy.
	 *
	 * @param logger the logger to add to this hierarchy
	 * @throws IllegalArgumentException if the passed-in {@code logger} is {@code null}
	 * or {@code undefined} or if the passed-in {@code logger}'s {@code getName} method
	 * returns {@code null} or {@code undefined} or if a logger with the {@code logger}'s
	 * name is already in use
	 */
	public function addLogger(logger:ConfigurableHierarchicalLogger):Void {
		if (!logger) throw new IllegalArgumentException("Logger to add is not allowed to be null or undefined.", this, arguments);
		var name:String = logger.getName();
		if (name == null || name == "") throw new IllegalArgumentException("Name is not allowed to be null, undefined or a blank string.", this, arguments);
		if (loggers[name] && loggers[name] instanceof ConfigurableHierarchicalLogger) {
			throw new IllegalArgumentException("Name [" + name + "] is already in use.", this, arguments);
		}
		getLoggerByFactory(name, getSingletonFactory(logger));
	}
	
	/**
	 * Returns the factory used to obtain the passed-in {@code logger}.
	 *
	 * @param logger the logger to be returned by the returned factory
	 * @return a factory that returns the passed-in {@code logger}
	 */
	private function getSingletonFactory(logger:ConfigurableHierarchicalLogger):ConfigurableHierarchicalLoggerFactory {
		var result:ConfigurableHierarchicalLoggerFactory = getBlankConfigurableHierarchicalLoggerFactory();
		result.getLogger = function(Void):ConfigurableHierarchicalLogger {
			return logger;
		};
		return result;
	}
	
	/**
	 * Returns the logger appropriate to the given {@code name}.
	 *
	 * <p>The {@code name} can exist of a path as well as the actual specifier, for
	 * example {@code org.as2lib.core.BasicClass}. In case no logger instance has been
	 * put for the passed-in {@code name} a new will be created by the set factory,
	 * that by default obtains all its configuration from the parent logger.
	 *
	 * <p>{@code null} will be returned if passed-in {@code name} is {@code null} or
	 * {@code undefined}.
	 *
	 * @param name the name of the logger to obtain
	 * @return the logger corresponding to the {@code name}
	 */
	public function getLogger(name:String):Logger {
		if (name == null) return null;
		return getLoggerByFactory(name, null);
	}
	
	/**
	 * Returns the logger corresponding to the passed-in {@code name}.
	 *
	 * <p>If a logger with the passed-in name is not explicitely registered the logger
	 * returned by the factory is registered with the passed-in {@code name},
	 * integrated in the hierarchy and returned.
	 *
	 * <p>The {@code name} can exist of a path as well as the actual specifier, for
	 * example {@code org.as2lib.core.BasicClass}. In case no logger instance has been
	 * put for the passed-in {@code name} a new will be created by the set factory,
	 * that by default obtains all its configuration from the parent logger.
	 * 
	 * <p>{@code null} will be returned if the passed-in {@code name} is {@code null}
	 * or {@code undefined}.
	 *
	 * <p>If the passed-in {@code factory} is {@code null} or {@code undefined} the
	 * default one will be used.
	 *
	 * @param name the name of the logger to return
	 * @return the logger appropriate to the passed-in {@code name}
	 */
	public function getLoggerByFactory(name:String, factory:ConfigurableHierarchicalLoggerFactory):Logger {
		if (name == null) return null;
		if (!factory) factory = getDefaultLoggerFactory();
		var result = loggers[name];
		if (!result) {
			result = factory.getLogger();
			result.setName(name);
			loggers[name] = result;
			updateParents(result);
		} else if (result instanceof Array) {
			var children:Array = result;
			result = factory.getLogger();
			result.setName(name);
			loggers[name] = result;
			updateChildren(children, result);
			updateParents(result);
		}
		return result;
	}
	
	/**
	 * Updates the affected parents.
	 *
	 * @param l the newly added logger
	 */
	private function updateParents(l:ConfigurableHierarchicalLogger):Void {
		var n:String = l.getName();
		var f:Boolean = false;
		var s:Number = n.length;
		for (var i:Number = n.lastIndexOf(".", s-1); i >= 0; i = n.lastIndexOf(".", i-1)) {
			var t:String = n.substring(0, i);
			var o = loggers[t];
			if (!o) {
				loggers[t] = [l];
			} else if (o instanceof Logger) {
				f = true;
				l.setParent(o);
				break;
			} else if (o instanceof Array) {
				o.push(l);
			} else {
				throw new IllegalStateException("Obtained object [" + o + "] is of an unexpected type.", this, arguments);
			}
		}
		if (!f) l.setParent(root);
	}
	
	/**
	 * Updates the affected children of the node.
	 *
	 * @param c the children to update
	 * @param l the logger that now replaces the node
	 */
	private function updateChildren(c:Array, l:ConfigurableHierarchicalLogger):Void {
		var s:Number = c.length;
		for (var i:Number = 0; i < s; i++) {
			var z:ConfigurableHierarchicalLogger = c[i];
			if (z.getParent().getName().indexOf(l.getName()) != 0) {
				l.setParent(z.getParent());
				z.setParent(l);
			}
		}
	}
	
	/**
	 * Returns a blank configurable hierarchical logger factory. That is a logger
	 * factory with no implemented methods.
	 *
	 * @return a blank configurable hierarchical logger factory
	 */
	private function getBlankConfigurableHierarchicalLoggerFactory(Void):ConfigurableHierarchicalLoggerFactory {
		var result = new Object();
		result.__proto__ = ConfigurableHierarchicalLoggerFactory["prototype"];
		result.__constructor__ = ConfigurableHierarchicalLoggerFactory;
		return result;
	}
	
}