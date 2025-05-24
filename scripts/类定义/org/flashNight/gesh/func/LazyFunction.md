import org.flashNight.gesh.func.LazyFunctionTest;
var test:LazyFunctionTest = new LazyFunctionTest();
try
{
	test.runTests();
}
catch (e:Error)
{
	trace(e.message);
}