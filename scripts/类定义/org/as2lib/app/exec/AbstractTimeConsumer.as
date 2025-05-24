import org.as2lib.env.event.EventSupport;
import org.as2lib.data.type.Time;

/**
 * {@code AbstractTimeConsumer} represents a time consuming class.
 * 
 * <p>It saves and provides informations about the time that the concrete 
 * class used.
 * 
 * <p>The concrete implementation needs to take care of {@code startTime},
 * {@code endTime},{@code getPercentage},{@code started} and {@code finished}.
 * 
 * @author Martin Heidegger
 * @version 1.0
 */
class org.as2lib.app.exec.AbstractTimeConsumer extends EventSupport {
	
	/** Start time in ms of start point. */
	private var startTime:Number;
	
	/** Finish time in ms of finishing point. */
	private var endTime:Number;
	
	/** Duration time difference. */
	private var duration:Time;
	
	/** Total time difference. */
	private var totalTime:Time;
	
	/** Rest time difference. */
	private var restTime:Time;
	
	/** Flag if execution was started. */
	private var started:Boolean;
	
	/** Flag if execution was finished. */
	private var finished:Boolean;
	
	/**
	 * Constructs a new {@code AbstractTimeConsumer}.
	 */
	public function AbstractTimeConsumer(Void) {
		duration = new Time(0);
		totalTime = new Time(0);
		restTime = new Time(0);
		started = false;
		finished = false;
	}
	
	/**
	 * Returns {@code true} if the process has finished.
	 * 
	 * <p>If the process has not been started it returns {@code false}.
	 * 
	 * @return {@code true} if the process has finished
	 */
	public function hasFinished(Void):Boolean {
		return finished;
	}
	
	/**
	 * Returns {@code true} if the process has started.
	 * 
	 * <p>If the process has finished it returns {@code false}.
	 * 
	 * @return {@code true} if the process has started
	 */
	public function hasStarted(Void):Boolean {
		return started;
	}
	
    /**
     * Returns the percentage of execution
     * 
     * <p>Override this implementation for a matching result.
     * 
     * @return {@code null}, override this implementation
     */
    public function getPercentage(Void):Number {
		return null;
	}
	
	/**
	 * Returns the time of the execution of the process.
	 * 
	 * @return time difference between start time and end time/current time.
	 */
	public function getDuration(Void):Time {
		if (endTime) {
			return duration.setValue(endTime-startTime);
		} else {
			return duration.setValue(getTimer()-startTime);
		}
	}
	
	/**
	 * Estimates the approximate time for the complete execution of the process.
	 * 
	 * @return estimated duration at the end of the process
	 */
	public function getEstimatedTotalTime(Void):Time {
		if ((hasStarted() || hasFinished()) && getPercentage() != null) {
			return totalTime.setValue(getDuration().inMilliSeconds()/getPercentage()*100);
		} else {
			return null;
		}
	}
	
	/**
	 * Estimates the approximate time until the execution finishes.
	 * 
	 * @return estimated time until finish of the process
	 */
	public function getEstimatedRestTime(Void):Time {
		var totalTime:Time = getEstimatedTotalTime();
		if (totalTime == null) {
			return null;
		} else {
			return restTime.setValue(getEstimatedTotalTime().inMilliSeconds()-getDuration().inMilliSeconds());
		}
	}
}