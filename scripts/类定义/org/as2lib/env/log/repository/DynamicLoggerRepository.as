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
import org.as2lib.env.log.Logger;
import org.as2lib.env.log.LoggerRepository;
import org.as2lib.env.log.repository.LoggerFactory;

/**
 * {@code DynamicLoggerRepository} is used to obtain loggers.
 *
 * <p>The actual class of these loggers is determined by you at runtime. You can
 * therefor either use the constructors logger class argument or the
 * {@link #setLoggerFactory} method.
 * 
 * <p>This repository is very performant. What it does is quite simple. It only
 * instantiates logger instances passing-in the given name, stores these instances
 * by name for retrieval later on and returns them.
 *
 * <p>When working with logger repositories you normally store them in the log
 * manager using the static {@link LogManager#setLoggerRepository} method. You can
 * then use the static {@link LogManager#getLogger} method to obtain loggers from
 * the set repository.
 *
 * <p>Example:
 * <code>
 *   // configuration: on system start-up
 *   var repository:LoggerRepository = new DynamicLoggerRepository(MyLogger);
 *   LogManager.setLoggerRepository(repository);
 *   // usage: in the org.mydomain.MyClass class
 *   var myLogger:Logger = LogManager.getLogger("org.mydomain.MyClass");
 *   if (myLogger.isWarningEnabled()) {
 *       myLogger.warning("Pay attention please!");
 *   }
 * </code>
 *
 * @author Simon Wacker
 */
class org.as2lib.env.log.repository.DynamicLoggerRepository extends BasicClass implements LoggerRepository {
	
	/** Already received loggers. */
	private var loggers:Object;
	
	/** Creates loggers. */
	private var loggerFactory:LoggerFactory;
	
	/**
	 * Constructs a new {@code DynamicLoggerRepository} instance.
	 *
	 * <p>If you do not pass a {@code loggerClass} you must set the logger factory via
	 * the {@link #setLoggerFactory} method. Otherwise the logger returned by
	 * {@link #getLogger} will always be {@code null}.
	 *
	 * <p>The logger is wrapped into a factory and the factory is set. The factory
	 * then instantiates the logger class passing-in the name of the logger on calls
	 * to {@link #getLogger}.
	 *
	 * <p>Already received loggers are cached by name. Thus there exists only one
	 * logger instance per name.
	 *
	 * @param loggerClass (optional) the class to create loggers of
	 */
	public function DynamicLoggerRepository(loggerClass:Function) {
		if (loggerClass) {
			loggerFactory = getDynamicLoggerFactory(loggerClass);
		}
		loggers = new Object();
	}
	
	/**
	 * Returns a new dynamic logger factory.
	 *
	 * <p>This factory creates new instances of the passed-in {@code loggerClass}. It
	 * passes the logger name as parameter to the constructor of the class on creation.
	 *
	 * @return a new dynamic logger factory
	 */
	private function getDynamicLoggerFactory(loggerClass:Function):LoggerFactory {
		var result:LoggerFactory = getBlankLoggerFactory();
		result.getLogger = function(loggerName:String):Logger {
			return new loggerClass(loggerName);
		};
		return result;
	}
	
	/**
	 * Returns a blank logger factory.
	 *
	 * <p>That is a factory without implemented methods. All methods have still to be
	 * set.
	 *
	 * @return a blank logger factory
	 */
	private function getBlankLoggerFactory(Void):LoggerFactory {
		var result = new Object();
		result.__proto__ = LoggerFactory["prototype"];
		result.__constructor__ = LoggerFactory;
		return result;
	}
	
	/**
	 * Returns the set logger factory.
	 *
	 * @return the set logger factory
	 */
	public function getLoggerFactory(Void):LoggerFactory {
		return loggerFactory;
	}
	
	/**
	 * Sets a new logger factory.
	 *
	 * <p>This logger factory is used to create loggers for given names, that are
	 * returned by the {@link #getLogger} method.
	 *
	 * @param loggerFactory the new logger factory
	 */
	public function setLoggerFactory(loggerFactory:LoggerFactory):Void {
		this.loggerFactory = loggerFactory;
	}
	
	/**
	 * Returns a pre-configured logger for the passed-in {@code name}.
	 *
	 * <p>A new logger is created for names to which no logger has been assigned yet.
	 * The new logger is configured with the {@code name}, either by the custom
	 * factory or by the default one, which passes the {@code name} as parameter to
	 * the constructor of the logger class. The logger is then cached by name and
	 * returned for usage.
	 *
	 * <p>{@code null} will be returned if:
	 * <ul>
	 *   <li>No logger factory has been set.</li>
	 *   <li>The set logger factory returns {@code null} or {@code undefined}.</li>
	 * </ul>
	 *´
	 * @param name the name of the logger to return
	 * @return the logger appropriate to the passed-in {@code name}
	 */
	public function getLogger(name:String):Logger {
		if (loggers[name]) return loggers[name];
		if (loggerFactory) {
			var result:Logger = loggerFactory.getLogger(name);
			loggers[name] = result;
			return result;
		}
		return null;
	}
	
}