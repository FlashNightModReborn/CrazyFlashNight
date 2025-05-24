interface org.flashNight.aven.test.TestReporter {
    function startSuite(name:String):Void;
    function endSuite(name:String):Void;
    function startTest(description:String):Void;
    function passTest(description:String, time:Number):Void;
    function failTest(description:String, time:Number, error:Error):Void;
    function skipTest(description:String):Void;
    function generateReport():Void;
}
