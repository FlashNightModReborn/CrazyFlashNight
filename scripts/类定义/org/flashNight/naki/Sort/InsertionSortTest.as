import org.flashNight.naki.Sort.*;
import org.flashNight.naki.RandomNumberEngine.*;
class org.flashNight.naki.Sort.InsertionSortTest {

    public static function runTests():Void {
        trace("Starting InsertionSort tests...");

        // Tests for sort method
        testSortEmptyArray();
        testSortOneElement();
        testSortIdenticalElements();
        testSortAscendingOrder();
        testSortDescendingOrder();
        testSortRandomOrder();
        testSortCustomComparisonFunction();

        // Tests for sortOn method
        testSortOnSingleFieldNumericAscending();
        testSortOnSingleFieldNumericDescending();
        testSortOnSingleFieldStringAscending();
        testSortOnSingleFieldStringDescending();
        testSortOnSingleFieldCaseInsensitive();
        testSortOnMultipleFields();
        testSortOnReturnIndexedArray();
        testSortOnUniqueSortWithDuplicates();
        testSortOnUniqueSortWithoutDuplicates();
        testSortOnInvalidFieldName();
        testSortOnMixedFieldTypes();

        // Performance tests
        performanceTestSort();
        performanceTestSortOn();

        trace("All tests completed.");
    }

    // Test cases for sort method
    public static function testSortEmptyArray():Void {
        var arr:Array = [];
        InsertionSort.sort(arr, function(a, b):Number { return a - b; });
        if (arr.length != 0) {
            trace("testSortEmptyArray failed");
        } else {
            trace("testSortEmptyArray passed");
        }
    }

    public static function testSortOneElement():Void {
        var arr:Array = [5];
        InsertionSort.sort(arr, function(a, b):Number { return a - b; });
        if (arr[0] != 5) {
            trace("testSortOneElement failed");
        } else {
            trace("testSortOneElement passed");
        }
    }

    public static function testSortIdenticalElements():Void {
        var arr:Array = [3, 3, 3, 3];
        InsertionSort.sort(arr, function(a, b):Number { return a - b; });
        var expected:Array = [3, 3, 3, 3];
        if (arr.toString() != expected.toString()) {
            trace("testSortIdenticalElements failed");
        } else {
            trace("testSortIdenticalElements passed");
        }
    }

    public static function testSortAscendingOrder():Void {
        var arr:Array = [1, 2, 3, 4];
        InsertionSort.sort(arr, function(a, b):Number { return a - b; });
        var expected:Array = [1, 2, 3, 4];
        if (arr.toString() != expected.toString()) {
            trace("testSortAscendingOrder failed");
        } else {
            trace("testSortAscendingOrder passed");
        }
    }

    public static function testSortDescendingOrder():Void {
        var arr:Array = [4, 3, 2, 1];
        InsertionSort.sort(arr, function(a, b):Number { return a - b; });
        var expected:Array = [1, 2, 3, 4];
        if (arr.toString() != expected.toString()) {
            trace("testSortDescendingOrder failed");
        } else {
            trace("testSortDescendingOrder passed");
        }
    }

    public static function testSortRandomOrder():Void {
        var arr:Array = [3, 1, 4, 2];
        InsertionSort.sort(arr, function(a, b):Number { return a - b; });
        var expected:Array = [1, 2, 3, 4];
        if (arr.toString() != expected.toString()) {
            trace("testSortRandomOrder failed");
        } else {
            trace("testSortRandomOrder passed");
        }
    }

    public static function testSortCustomComparisonFunction():Void {
        var arr:Array = [3, 1, 4, 2];
        InsertionSort.sort(arr, function(a, b):Number { return b - a; });
        var expected:Array = [4, 3, 2, 1];
        if (arr.toString() != expected.toString()) {
            trace("testSortCustomComparisonFunction failed");
        } else {
            trace("testSortCustomComparisonFunction passed");
        }
    }

    // Test cases for sortOn method
    public static function testSortOnSingleFieldNumericAscending():Void {
        var arr:Array = [
            {value: 10},
            {value: 2},
            {value: 5}
        ];
        InsertionSort.sortOn(arr, "value", Array.NUMERIC);
        var expected:Array = [
            {value: 2},
            {value: 5},
            {value: 10}
        ];
        if (arr[0].value != expected[0].value && arr[1].value != expected[1].value && arr[2].value != expected[2].value) {
            trace("testSortOnSingleFieldNumericAscending failed");
        } else {
            trace("testSortOnSingleFieldNumericAscending passed");
        }
    }

    public static function testSortOnSingleFieldNumericDescending():Void {
        var arr:Array = [
            {value: 10},
            {value: 2},
            {value: 5}
        ];
        InsertionSort.sortOn(arr, "value", Array.NUMERIC | Array.DESCENDING);
        var expected:Array = [
            {value: 10},
            {value: 5},
            {value: 2}
        ];
        if (arr[0].value != expected[0].value && arr[1].value != expected[1].value && arr[2].value != expected[2].value) {
            trace("testSortOnSingleFieldNumericDescending failed");
        } else {
            trace("testSortOnSingleFieldNumericDescending passed");
        }
    }

    public static function testSortOnSingleFieldStringAscending():Void {
        var arr:Array = [
            {name: "Charlie"},
            {name: "Alice"},
            {name: "Bob"}
        ];
        InsertionSort.sortOn(arr, "name", 0);
        var expected:Array = [
            {name: "Alice"},
            {name: "Bob"},
            {name: "Charlie"}
        ];
        if (arr[0].name != expected[0].name && arr[1].name != expected[1].name && arr[2].name != expected[2].name) {
            trace("testSortOnSingleFieldStringAscending failed");
        } else {
            trace("testSortOnSingleFieldStringAscending passed");
        }
    }

    public static function testSortOnSingleFieldStringDescending():Void {
        var arr:Array = [
            {name: "Charlie"},
            {name: "Alice"},
            {name: "Bob"}
        ];
        InsertionSort.sortOn(arr, "name", Array.DESCENDING);
        var expected:Array = [
            {name: "Charlie"},
            {name: "Bob"},
            {name: "Alice"}
        ];
        if (arr[0].name != expected[0].name && arr[1].name != expected[1].name && arr[2].name != expected[2].name) {
            trace("testSortOnSingleFieldStringDescending failed");
        } else {
            trace("testSortOnSingleFieldStringDescending passed");
        }
    }

    public static function testSortOnSingleFieldCaseInsensitive():Void {
        var arr:Array = [
            {name: "charlie"},
            {name: "ALICE"},
            {name: "bob"}
        ];
        InsertionSort.sortOn(arr, "name", Array.CASEINSENSITIVE);
        var expected:Array = [
            {name: "ALICE"},
            {name: "bob"},
            {name: "charlie"}
        ];
        if (arr[0].name.toLowerCase() != expected[0].name.toLowerCase() && arr[1].name.toLowerCase() != expected[1].name.toLowerCase() && arr[2].name.toLowerCase() != expected[2].name.toLowerCase()) {
            trace("testSortOnSingleFieldCaseInsensitive failed");
        } else {
            trace("testSortOnSingleFieldCaseInsensitive passed");
        }
    }

    public static function testSortOnMultipleFields():Void {
        var arr:Array = [
            {age: 25, name: "Bob"},
            {age: 30, name: "Alice"},
            {age: 25, name: "Charlie"}
        ];
        InsertionSort.sortOn(arr, ["age", "name"], [Array.NUMERIC, 0]);
        var expected:Array = [
            {age: 25, name: "Bob"},
            {age: 25, name: "Charlie"},
            {age: 30, name: "Alice"}
        ];
        if (arr[0].age != expected[0].age || arr[0].name != expected[0].name ||
            arr[1].age != expected[1].age || arr[1].name != expected[1].name ||
            arr[2].age != expected[2].age || arr[2].name != expected[2].name) {
            trace("testSortOnMultipleFields failed");
        } else {
            trace("testSortOnMultipleFields passed");
        }
    }

    public static function testSortOnReturnIndexedArray():Void {
        var arr:Array = [
            {value: 10},
            {value: 2},
            {value: 5}
        ];
        var indices:Array = InsertionSort.sortOn(arr, "value", Array.RETURNINDEXEDARRAY);
        var expectedIndices:Array = [1, 2, 0];
        if (indices.toString() != expectedIndices.toString()) {
            trace("testSortOnReturnIndexedArray failed    indices:" + indices.toString() + " expectedIndices:" + expectedIndices.toString());
        } else {
            trace("testSortOnReturnIndexedArray passed");
        }
    }

    public static function testSortOnUniqueSortWithDuplicates():Void {
        var arr:Array = [
            {value: 2},
            {value: 2},
            {value: 5}
        ];
        var result:Object = InsertionSort.sortOn(arr, "value", Array.UNIQUESORT);
        if (result != null) {
            trace("testSortOnUniqueSortWithDuplicates failed");
        } else {
            trace("testSortOnUniqueSortWithDuplicates passed");
        }
    }

    public static function testSortOnUniqueSortWithoutDuplicates():Void {
        var arr:Array = [
            {value: 2},
            {value: 3},
            {value: 5}
        ];
        var result:Object = InsertionSort.sortOn(arr, "value", Array.UNIQUESORT);
        if (result == null) {
            trace("testSortOnUniqueSortWithoutDuplicates failed");
        } else {
            trace("testSortOnUniqueSortWithoutDuplicates passed");
        }
    }

    public static function testSortOnInvalidFieldName():Void {
        var arr:Array = [
            {name: "Alice"},
            {name: "Bob"}
        ];
        var result:Object = InsertionSort.sortOn(arr, "age", Array.NUMERIC);
        if (result != null) {
            trace("testSortOnInvalidFieldName failed   result:" + result.toString());
        } else {
            trace("testSortOnInvalidFieldName passed");
        }
    }

    public static function testSortOnMixedFieldTypes():Void {
        var arr:Array = [
            {value: "10"},
            {value: 2},
            {value: "5"}
        ];
        InsertionSort.sortOn(arr, "value", Array.NUMERIC);
        var expected:Array = [
            {value: 2},
            {value: "5"},
            {value: "10"}
        ];
        if (arr[0].value != expected[0].value && arr[1].value != expected[1].value && arr[2].value != expected[2].value) {
            trace("testSortOnMixedFieldTypes failed");
        } else {
            trace("testSortOnMixedFieldTypes passed");
        }
    }

    // Performance tests
    public static function performanceTestSort():Void {
        var arr:Array = [];
        for (var i:Number = 0; i < 1000; i++) {
            arr.push(Math.random() * 1000);
        }
        var startTime:Number = getTimer();
        InsertionSort.sort(arr, function(a, b):Number { return a - b; });
        var endTime:Number = getTimer();
        trace("sort 1000 elements took " + (endTime - startTime) + " ms");
    }

    public static function performanceTestSortOn():Void {
        var arr:Array = [];
        for (var i:Number = 0; i < 1000; i++) {
            arr.push({value: Math.random() * 1000});
        }
        var startTime:Number = getTimer();
        InsertionSort.sortOn(arr, "value", Array.NUMERIC);
        var endTime:Number = getTimer();
        trace("sortOn 1000 elements took " + (endTime - startTime) + " ms");
    }
}