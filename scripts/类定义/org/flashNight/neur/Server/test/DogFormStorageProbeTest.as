import org.flashNight.arki.merc.DogFormService;
import org.flashNight.neur.Server.SaveManager;
/** 仅在随机 cf7_env_probe_<16 hex> 测试槽验证真实犬种字段，不读写玩家槽。 */
class org.flashNight.neur.Server.test.DogFormStorageProbeTest {
    private static var socket:XMLSocket;
    public static function runAllTests():Void {
        socket = new XMLSocket();
        socket.onConnect = function(ok:Boolean):Void {
            if (ok) DogFormStorageProbeTest.socket.send("hello");
            else trace("[FAIL] DogFormStorageProbe connect");
        };
        socket.onData = function(message:String):Void {
            var parts:Array = message.split("|");
            if (parts[0] == "ready") {
                trace("DogFormStorageProbe ready");
                trace("FocusedTestRunId dog-form-storage Complete: " + _root.storageProbeRunId);
                return;
            }
            var slot:String = String(parts[2]);
            if (slot.indexOf("cf7_env_probe_") != 0 || slot.length != 30) return;
            var so:SharedObject = SharedObject.getLocal(slot);
            var outcome:String;
            if (parts[0] == "write") {
                _root.存档系统 = {dirtyMark:false};
                _root.当前为战斗地图 = false;
                _root.宠物领养限制 = 1;
                _root.宠物信息 = [[0,17,73,0,0,{customName:"小黑",宠物升级经验:43,基础训练:{次数:2}}]];
                var changed:Object = DogFormService.change(0,"military");
                if (!changed.success) return;
                // 生产 pack 持有宠物领域的唯一字段映射；测试后端只提交该领域。
                var packed:Object = SaveManager.getInstance().packGameState();
                so.data.pets = packed.pets;
                so.data.nonce = String(parts[1]);
                outcome = String(so.flush());
            } else if (parts[0] == "read") {
                var info:Array = so.data.pets.宠物信息[0];
                var valid:Boolean = info[0] == 0 && info[1] == 17 && info[2] == 73
                    && info[5].dogForm == "military" && info[5].customName == "小黑"
                    && info[5].宠物升级经验 == 43 && info[5].基础训练.次数 == 2
                    && DogFormService.identifier(info,"") == "敌人-制式军警犬";
                outcome = valid ? String(so.data.nonce) : "dog_fields_mismatch";
            } else return;
            DogFormStorageProbeTest.socket.send(parts[0] + "|" + parts[1] + "|" + slot + "|" + outcome);
        };
        socket.connect("127.0.0.1",47183);
    }
}
