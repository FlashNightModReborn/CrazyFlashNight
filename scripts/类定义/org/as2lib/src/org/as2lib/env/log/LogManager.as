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
import org.as2lib.env.reflect.ReflectUtil;
import org.as2lib.env.log.Logger;
import org.as2lib.env.log.LoggerRepository;

/**
 * {@code LogManager} is the core access point of the As2lib Logging API.
 * 
 * <p>You use it to set the underlying repository that stores and releases loggers
 * and to obtain a logger according to a logger's name of the repository.
 * 
 * <p>The repository must be set before anything else when you are using this
 * class as access point to obtain loggers. There is no default repository. This
 * means that all messages sent to loggers obtained from the {@link #getLogger} method,
 * before the repository has been set will not be logged.
 * 
 * <p>This class could be used as follows with a non-singleton repository. Note
 * that you can of course also use any other kind of logger repository.
 *
 * <code>
 *   // configuration: when setting everything up
 *   var loggerHierarchy:LoggerHierarchy = new LoggerHierarchy();
 *   var traceLogger:SimpleHierarchicalLogger = new SimpleHierarchicalLogger("org.mydomain");
 *   traceLogger.addHandler(new TraceHandler());
 *   loggerHierarchy.addLogger(traceLogger);
 *   LogManager.setLoggerRepository(loggerHierarchy);
 *   // usage: in the class org.mydomain.MyClass
 *   var myLogger:Logger = LogManager.getLogger("org.mydomain.MyClass");
 *   if (myLogger.isInfoEnabled()) {
 *       myLogger.info("This is an informative log message.");
 *   }
 * </code>
 * 
 * <p>If you have one logger that shall always be returned you can use the
 * convenience method {@link #setLogger} that does all the work with the repository
 * for you.
 * 
 * <code>
 *   // configuration: when setting everything up
 *   var traceLogger:SimpleLogger = new SimpleLogger();
 *   traceLogger.addHandler(new TraceHandler());
 *   LogManager.setLogger(traceLogger);
 *   // usage: in the class org.mydomain.MyClass
 *   var myLogger:Logger = LogManager.getLogger("org.mydomain.MyClass");
 *   if (myLogger.isInfoEnabled()) {
 *       myLogger.info("This is an informative log message.");
 *   }
 * </code>
 * 
 * <p>It is common practice to obtain loggers per class. You may thus consider the
 * following strategy of obtaining loggers:
 * <code>private static var logger:Logger = LogManager.getLogger("org.as2lib.MyClass");</code>
 * 
 * <p>Applying this strategy you have a logger per class that can be used within
 * per class and per instance methods of the logging class.
 *
 * @author Simon Wacker
 */
class org.as2lib.env.log.LogManager extends BasicClass {
	
	/** Repository that stores already retrieved loggers. */
	private static var repository:LoggerRepository;
	
	/** Proxies of loggers that are replaced by real loggers as soon as repository gets set. */
	private static var loggerProxies:Array;
	
	/**
	 * @overload #getLoggerByName
	 * @overload #getLoggerByObject
	 */
	public static function getLogger():Logger {
		// do not use Overloading API hear because 'LogManager' must be as light-weight as possible
		if (arguments[0].__proto__ != String.prototype) {
			return getLoggerByObject(arguments[0]);
		}
		return getLoggerByName(arguments[0]);
	}
	
	/**
	 * Returns the logger according to the passed-in {@code object}.
	 * 
	 * <p>If {@code object} is of type 'function' it is supposed that this is the type
	 * to get the name of otherwise it is supposed to be the instance of the type to get
	 * the name of.
	 * 
	 * <p>The name of the type is used as logger name.
	 * 
	 * <p>Note that evaluating the name is rather slow. It is thus recommended to
	 * hardcode the name and use the {@link #getLoggerByName} method.
	 * 
	 * @param object the object to return the type name of
	 * @return the logger for the given {@code object}
	 * @see #getLoggerByName
	 */
	public static function getLoggerByObject(object):Logger {
		return getLoggerByName(ReflectUtil.getTypeName(object));
	}
	
	/**
	 * Returns the logger according the passed-in {@code loggerName}.
	 * 
	 * <p>Uses the set logger repository to receive the logger that is returned.
	 * 
	 * <p>{@code null} is only returned if the logger repository is initialized and
	 * returns {@code null} or {@code undefined}.
	 * 
	 * <p>If the logger repository has not been initialized yet a proxy gets returned
	 * that is replaced by the actual logger of the repository, as soon as the
	 * repository gets initialized. This means that the following access in classes is
	 * possible:
	 * <code>private static var logger:Logger = LogManager.getLogger("org.as2lib.MyClass");</code>
	 * 
	 * <p>But note that you shall not log messages before the actual initialization of
	 * the repository; these messages will never be logged. Proxies are just returne to
	 * enable the convenient logger access above.
	 * 
	 * @param loggerName the name of the logger to return
	 * @return the logger according to the passed-in {@code name}
	 */
	public static function getLoggerByName(loggerName:String):Logger {
		if (!repository) {
			if (loggerProxies[loggerName]) return loggerProxies[loggerName];
			if (!loggerProxies) loggerProxies = new Array();
			var result:Logger = getBlankLogger();
			result["__resolve"] = function() {
				return false;
			};
			result["name"] = loggerName;
			loggerProxies.push(result);
			loggerProxies[loggerName] = result;
			return result;
		}
		var result:Logger = repository.getLogger(loggerName);
		if (result) return result;
		return null;
	}
	
	/**
	 * Returns a blank logger.
	 *
	 * <p>This is a {@code Logger} instance with no implemented methods.
	 *
	 * @return a blank logger
	 */
	private static function getBlankLogger(Void):Logger {
		var result = new Object();
		result.__proto__ = Logger["prototype"];
		result.__constructor__ = Logger;
		return result;
	}
	
	/**
	 * Sets the {@code logger} that is returned on calls to the {@link #getLogger}
	 * method.
	 *
	 * <p>This method actually sets a singleton repository via the static
	 * {@link #setLoggerRepository} that always returns the passed-in {@code logger}
	 * and ignores the name.
	 *
	 * <p>You could also set the repository by hand, this is just an easier way of
	 * doing it if you always want the same logger to be returned.
	 *
	 * @param logger the logger to return on calls to the {@code #getLogger} method
	 */
	public static function setLogger(logger:Logger):Void {
		repository = getBlankLoggerRepository();
		repository.getLogger = function(loggerName:String):Logger {
			return logger;
		};
	}
	
	/**
	 * Returns a blank logger repository.
	 *
	 * <p>This is a {@code LoggerRepository} instance with no implemented methods.
	 *
	 * @return a blank logger repository
	 */
	private static function getBlankLoggerRepository(Void):LoggerRepository {
		var result = new Object();
		result.__proto__ = LoggerRepository["prototype"];
		result.__constructor__ = LoggerRepository;
		return result;
	}
	
	/**
	 * Reutrns the logger repository set via {@link #setLoggerRepository}.
	 *
	 * <p>There is no default logger repository, so you must set it before anything
	 * else.
	 *
	 * @return the set logger repository
	 */
	public static function getLoggerRepository(Void):LoggerRepository {
		return repository;
	}
	
	/**
	 * Sets a new repositroy returned by {@link #getLoggerRepository}.
	 *
	 * <p>The {@link #getLogger} method uses this repository to obtain the logger for
	 * the given logger name.
	 *
	 * @param loggerRepository the new logger repository
	 */
	public static function setLoggerRepository(loggerRepository:LoggerRepository):Void {
		repository = loggerRepository;
		if (loggerProxies) {
			for (var i:Number = loggerProxies.length - 1; i >= 0; i--) {
				var proxy:Logger = loggerProxies[i];
				var name:String = proxy["name"];
				delete proxy["__constructor__"];
				delete proxy["__resolve"];
				delete proxy["name"];
				loggerProxies.pop();
				delete loggerProxies[name];
				var logger:Logger = loggerRepository.getLogger(name);
				proxy["__proto__"] = logger;
			}
		}
	}
	
	/**
	 * Returns whether a logger repository has been added.
	 * 
	 * @return {@code true} if a logger repository has been added else {@code false}
	 */
	public static function hasLoggerRepository(Void):Boolean {
		return (repository != null);
	}
	
	/**
	 * Private constructor.
	 */
	private function LogManager(Void) {
	}
	
}