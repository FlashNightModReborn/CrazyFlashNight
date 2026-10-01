/** 隔离 SharedObject 后端探针；只接受测试前缀槽，真实播放器新进程读回。 */
class org.flashNight.neur.Server.test.FlashStorageProbeTest {
    private static var socket:XMLSocket;
    public static function runAllTests():Void {
        socket = new XMLSocket();
        socket.onConnect = function(ok:Boolean):Void {
            if (ok) FlashStorageProbeTest.socket.send("hello");
            else trace("[FAIL] FlashStorageProbe connect");
        };
        socket.onData = function(message:String):Void {
            var parts:Array = message.split("|");
            if (parts[0] == "ready") {
                trace("FlashStorageProbe ready");
                trace("FocusedTestRunId save-storage-probe Complete: " + _root.storageProbeRunId);
                return;
            }
            var slot:String = String(parts[2]);
            if (slot.indexOf("cf7_env_probe_") != 0 || slot.length != 30) return;
            var so:SharedObject = SharedObject.getLocal(slot);
            var outcome:String;
            if (parts[0] == "write") {
                so.data.nonce = String(parts[1]);
                outcome = String(so.flush());
            } else if (parts[0] == "read") {
                outcome = String(so.data.nonce);
            } else return;
            FlashStorageProbeTest.socket.send(parts[0] + "|" + parts[1] + "|" + slot + "|" + outcome);
        };
        socket.connect("127.0.0.1", 47183);
    }
}
