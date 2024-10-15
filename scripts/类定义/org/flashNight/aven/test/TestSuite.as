class org.flashNight.aven.test.TestSuite {
    private var name:String;
    private var testCases:Array;

    public function TestSuite(name:String) {
        this.name = name;
        this.testCases = [];
    }

    public function addTestCase(testCase:org.flashNight.aven.test.TestCase):Void {
        this.testCases.push(testCase);
    }

    public function getName():String {
        return this.name;
    }

    public function getTestCases():Array {
        return this.testCases;
    }
}
