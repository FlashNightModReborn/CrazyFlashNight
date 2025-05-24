import org.flashNight.naki.DataStructures.*;

class org.flashNight.naki.DataStructures.ArrayStackTest {
    public function ArrayStackTest() {
        testPush();
        testPop();
        testPeek();
        testIsEmpty();
        testGetSize();
        testClear();
        performanceTest();
    }
    
    private function assert(condition:Boolean, message:String):Void {
        if (!condition) {
            trace("[FAIL]Assertion : " + message);
        }
        else
        {
            trace("[PASS]Assertion : " + message);
        }
    }
    
    private function testPush():Void {
        var stack:ArrayStack = new ArrayStack();
        stack.push(1);
        assert(stack.getSize() == 1, "Stack size should be 1 after one push.");
        stack.push("two");
        assert(stack.getSize() == 2, "Stack size should be 2 after two pushes.");
        stack.push(null);
        assert(stack.getSize() == 3, "Stack size should be 3 after pushing null.");
    }
    
    private function testPop():Void {
        var stack:ArrayStack = new ArrayStack();
        stack.push("one");
        var poppedValue:Object = stack.pop();
        assert(poppedValue == "one", "Popped value should be 'one'.");
        assert(stack.isEmpty(), "Stack should be empty after pop.");
        poppedValue = stack.pop();
        assert(poppedValue == null, "Popping from empty stack should return null.");
    }
    
    private function testPeek():Void {
        var stack:ArrayStack = new ArrayStack();
        stack.push(1);
        assert(stack.peek() == 1, "Peek should return 1.");
        stack.push("two");
        assert(stack.peek() == "two", "Peek should return 'two'.");
        assert(stack.getSize() == 2, "Stack size should remain 2 after peek.");
        var peekedValue:Object = stack.peek();
        assert(peekedValue == "two", "Peek should still return 'two'.");
    }
    
    private function testIsEmpty():Void {
        var stack:ArrayStack = new ArrayStack();
        assert(stack.isEmpty(), "New stack should be empty.");
        stack.push(true);
        assert(!stack.isEmpty(), "Stack should not be empty after push.");
        stack.pop();
        assert(stack.isEmpty(), "Stack should be empty after pop.");
    }
    
    private function testGetSize():Void {
        var stack:ArrayStack = new ArrayStack();
        assert(stack.getSize() == 0, "New stack size should be 0.");
        stack.push(1);
        assert(stack.getSize() == 1, "Stack size should be 1 after push.");
        stack.push(2);
        assert(stack.getSize() == 2, "Stack size should be 2 after second push.");
        stack.pop();
        assert(stack.getSize() == 1, "Stack size should be 1 after pop.");
        stack.clear();
        assert(stack.getSize() == 0, "Stack size should be 0 after clear.");
    }
    
    private function testClear():Void {
        var stack:ArrayStack = new ArrayStack();
        stack.clear();
        assert(stack.isEmpty(), "Clearing empty stack should keep it empty.");
        stack.push(1);
        stack.push(2);
        stack.clear();
        assert(stack.isEmpty(), "Stack should be empty after clear.");
        assert(stack.getSize() == 0, "Stack size should be 0 after clear.");
    }
    
    private function performanceTest():Void {
        var stack:ArrayStack = new ArrayStack();
        var startTime:Number = getTimer();
        var iterations:Number = 100000; // Adjust based on environment
        for (var i:Number = 0; i < iterations; i++) {
            stack.push(i);
        }
        for (i = 0; i < iterations; i++) {
            stack.pop();
        }
        var endTime:Number = getTimer();
        assert(stack.isEmpty(), "Stack should be empty after performance test.");
        trace("Performance test completed in " + (endTime - startTime) + " milliseconds.");
    }
}