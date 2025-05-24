// 文件路径: org/flashNight/neur/Server/PortExtractor.as
class org.flashNight.neur.Server.PortExtractor {
    public var portList:Array;

    public function PortExtractor() {
        portList = [];
    }

    // 提取端口号
    public function extractPorts(eyeOf119:String):Array {
        trace("PortExtractor: Extracting ports from eyeOf119: " + eyeOf119);

        // 提取4位数的端口
        for (var i:Number = 0; i <= eyeOf119.length - 4; i++) {
            var port4:String = eyeOf119.substring(i, i + 4);
            var port4Num:Number = Number(port4);

            if (isValidPort(port4Num) && !containsPort(port4Num)) {
                portList.push(port4Num);
                trace("PortExtractor: Added valid 4-digit port: " + port4Num);
            }
        }

        // 提取5位数的端口
        for (var j:Number = 0; j <= eyeOf119.length - 5; j++) {
            var port5:String = eyeOf119.substring(j, j + 5);
            var port5Num:Number = Number(port5);

            if (isValidPort(port5Num) && !containsPort(port5Num)) {
                portList.push(port5Num);
                trace("PortExtractor: Added valid 5-digit port: " + port5Num);
            }
        }

        // 确保端口3000被加入（如果还未加入）
        if (!containsPort(3000) && isValidPort(3000)) {
            portList.push(3000);
            trace("PortExtractor: Added default port: 3000");
        }

        // 移除重复的端口并返回唯一的端口列表
        return removeDuplicatePorts(portList);
    }

    private function isValidPort(port:Number):Boolean {
        return (port >= 1024 && port <= 65535);
    }

    private function containsPort(port:Number):Boolean {
        for (var i:Number = 0; i < portList.length; i++) {
            if (portList[i] == port) {
                return true;
            }
        }
        return false;
    }

    private function removeDuplicatePorts(portList:Array):Array {
        var uniquePorts:Object = {};
        var finalPortList:Array = [];
        for (var k:Number = 0; k < portList.length; k++) {
            var port:Number = portList[k];
            if (uniquePorts[port] == undefined) {
                uniquePorts[port] = true;
                finalPortList.push(port);
            }
        }
        return finalPortList;
    }
}
