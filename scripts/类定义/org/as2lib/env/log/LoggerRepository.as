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
 
import org.as2lib.core.BasicInterface;
import org.as2lib.env.log.Logger;

/**
 * {@code LoggerRepository} is used to obtain {@code Logger} instances.
 *
 * <p>What logger instances are returned and how they are organized depends on the
 * specific implementation.
 * 
 * <p>There are simple implementations that just always returns instances of the
 * same class that are configured with the passed-in name.
 *
 * <p>Other implementations organize the loggers in a more complex way like in a
 * hierarchy.
 *
 * <p>All implementations have their strengths and weaknesses. In most cases you
 * have to decide between performance and functionality, like ease of configuration.
 * Take a look at the {@code org.as2lib.env.log.repository} package on what logger
 * repositories are supported.
 *
 * <p>When working with logger repositories you normally store them in the log
 * manager using the static {@link LogManager#setLoggerRepository} method. You can
 * then use the static {@link LogManager#getLogger} method to obtain loggers from
 * the set repository.
 *
 * @author Simon Wacker
 */
interface org.as2lib.env.log.LoggerRepository extends BasicInterface {
	
	/**
	 * Returns a pre-configured logger for the passed-in {@code name}.
	 * 
	 * <p>The implementation of this method can be simple and only return new logger
	 * instances or complex and structuring the loggers in a hierarchy. Thus invoking
	 * this method can be very fast or not that fast. So it is proposed to store the
	 * received logger by yourself.
	 *
	 * @param name the name of the logger to return
	 * @return a specific logger depending on the passed-in {@code name}
	 */
	public function getLogger(name:String):Logger;
	
}