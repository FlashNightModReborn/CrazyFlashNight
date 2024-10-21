// PortExtractor.as
class org.flashNight.neur.Server.PortExtractor {
    public static function extractPorts():Array {
        var portList:Array = [];
        var eyeOf119:String = (_root.闪客之夜 != undefined) ? _root.闪客之夜.toString() : "1192433993";
        trace("Extracting ports from eyeOf119: " + eyeOf119);

        // 提取4位数的端口
        for (var i:Number = 0; i <= eyeOf119.length - 4; i++) {
            var port4:String = eyeOf119.substring(i, i + 4);
            var port4Num:Number = Number(port4);

            if (isValidPort(port4Num) && !containsPort(portList, port4Num)) {
                portList.push(port4Num);
                trace("Added valid 4-digit port: " + port4Num);
            }
        }

        // 提取5位数的端口
        for (var j:Number = 0; j <= eyeOf119.length - 5; j++) {
            var port5:String = eyeOf119.substring(j, j + 5);
            var port5Num:Number = Number(port5);

            if (isValidPort(port5Num) && !containsPort(portList, port5Num)) {
                portList.push(port5Num);
                trace("Added valid 5-digit port: " + port5Num);
            }
        }

        // 确保端口3000被加入（如果还未加入）
        if (!containsPort(portList, 3000) && isValidPort(3000)) {
            portList.push(3000);
            trace("Added default port: 3000");
        }

        // 移除重复的端口
        var uniquePorts:Object = {};
        var finalPortList:Array = [];
        for (var k:Number = 0; k < portList.length; k++) {
            var port:Number = portList[k];
            if (uniquePorts[port] == undefined) {
                uniquePorts[port] = true;
                finalPortList.push(port);
            }
        }

        trace("Final extracted ports: " + finalPortList.join(", "));
        return finalPortList;
    }

    public static function isValidPort(port:Number):Boolean {
        return (port >= 1024 && port <= 65535);
    }

    public static function containsPort(portList:Array, port:Number):Boolean {
        for (var i:Number = 0; i < portList.length; i++) {
            if (portList[i] == port) {
                return true;
            }
        }
        return false;
    }
}
