import de.audiofarm.code.logger.test.*;
import as2unit.framework.*;
import as2unit.utils.*;

/*
*	Credits to Johannes Stein
*/
class de.audiofarm.code.logger.test.AllTests {
 
	private var testLevelRef:TestLevel;
	private var testLoggerRef:TestLogger;
	private var testErrorsRef:TestErrors;
	
	public function AllTests()	{}
	
	public function test()
	{
		var testSuite:TestSuite = new TestSuite();
		this.addTest( testSuite, "de.audiofarm.code.logger.test.TestLevel" );
		this.addTest( testSuite, "de.audiofarm.code.logger.test.TestLogger" );
		this.addTest( testSuite, "de.audiofarm.code.logger.test.TestErrors" );
		
		return testSuite;
	}
	
	private function addTest( testSuite:TestSuite, className:String):Void
	{
		var clazz = Runtime.findClass(className);
		testSuite.addTest( new TestSuite( clazz ) );
	}
}