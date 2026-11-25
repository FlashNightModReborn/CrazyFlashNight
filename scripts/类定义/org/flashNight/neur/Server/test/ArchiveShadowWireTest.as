import FastJSON;
import JSON;
import org.flashNight.neur.Server.ArchiveShadowWire;

class org.flashNight.neur.Server.test.ArchiveShadowWireTest {
    public static function runAllTests():Void {
        var strict:JSON = new JSON(false);
        var pair:String = String.fromCharCode(0xD840, 0xDE8E);
        var cases:Array = [
            {name:"quoted-and-backslash", data:strict.stringify({text:"\"\\\"\\\\\\中"})},
            {name:"valid-surrogate-pair", data:strict.stringify({text:"甲" + pair + "丙"})},
            {name:"isolated-high-surrogate", data:strict.stringify({text:String.fromCharCode(0xD840) + "中"})},
            {name:"isolated-low-surrogate", data:strict.stringify({text:"中" + String.fromCharCode(0xDE8E)})},
            {name:"escaped-controls", data:strict.stringify({text:String.fromCharCode(1, 8, 9, 10, 12, 13, 31)})},
            {name:"raw-controls", data:"甲" + String.fromCharCode(1, 31) + "丙"}
        ];
        var legacy:FastJSON = new FastJSON();
        var candidate:FastJSON = new FastJSON();
        var passed:Number = 0;
        for (var i:Number = 0; i < cases.length; i++) {
            var test:Object = cases[i];
            var expected:String = legacy.stringify(message(test.data, i));
            var actual:String = ArchiveShadowWire.stringify(candidate, message(test.data, i));
            if (expected != null && actual === expected) {
                passed++;
            } else {
                trace("[FAIL] ArchiveShadowWireTest " + test.name);
            }
        }
        trace("========== ArchiveShadowWireTest END: " + passed + "/" + cases.length
            + " passed, " + (cases.length - passed) + " failed ==========");
    }

    private static function message(data:String, callId:Number):Object {
        var envelope:Object = new Object();
        envelope.task = "archive";
        envelope.payload = {op:"shadow", slot:"wire_regression", data:data};
        envelope.callId = callId;
        return envelope;
    }
}
