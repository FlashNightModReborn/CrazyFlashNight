class org.flashNight.aven.test.TestCase {
    private var description:String;
    private var input:Object;
    private var expected:Object;
    private var testFunction:Function;
    private var tags:Array;

    public function TestCase(description:String, input:Object, expected:Object, testFunction:Function, tags:Array) {
        this.description = description;
        this.input = input;
        this.expected = expected;
        this.testFunction = testFunction;
        this.tags = tags != null ? tags : [];
    }

    public function getDescription():String {
        return this.description;
    }

    public function getInput():Object {
        return this.input;
    }

    public function getExpected():Object {
        return this.expected;
    }

    public function getTestFunction():Function {
        return this.testFunction;
    }

    public function getTags():Array {
        return this.tags;
    }
}
