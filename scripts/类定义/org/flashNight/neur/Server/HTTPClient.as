// HTTPClient.as
import org.flashNight.neur.Event.Delegate;

class org.flashNight.neur.Server.HTTPClient {
    public function HTTPClient() {
        // 构造函数
    }

    public function testConnection(port:Number, callback:Function):Void {
        var lv:LoadVars = new LoadVars();

        lv.onLoad = function(success:Boolean):Void {
            callback(success, port);
        };

        lv.sendAndLoad("http://localhost:" + port + "/testConnection", lv, "POST");
    }

    public function getSocketPort(currentPort:Number, callback:Function):Void {
        var lv:LoadVars = new LoadVars();

        lv.onLoad = function(success:Boolean):Void {
            if (success) {
                var response:Object = this;
                if (response.socketPort != undefined) {
                    callback(true, Number(response.socketPort));
                } else {
                    callback(false, null);
                }
            } else {
                callback(false, null);
            }
        };

        lv.load("http://localhost:" + currentPort + "/getSocketPort");
    }

    public function sendMessage(currentPort:Number, currentFrame:Number, messages:String, callback:Function):Void {
        var lv:LoadVars = new LoadVars();

        lv.frame = currentFrame;
        lv.messages = messages;

        lv.onLoad = function(success:Boolean):Void {
            callback(success);
        };

        lv.sendAndLoad("http://localhost:" + currentPort + "/logBatch", lv, "POST");
    }
}
