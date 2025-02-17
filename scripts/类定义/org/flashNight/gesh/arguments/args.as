// 文件路径: org/flashNight/gesh/arguments/args.as
class org.flashNight.gesh.arguments.args extends Array {
    public function args() {
        super();
        _init(arguments);
    }

    private function _init(args:FunctionArguments):Void {
        this.splice(0, this.length);
        
        if (args.length == 1 && args[0] instanceof Array) {
            var arr:Array = args[0];
            this.push.apply(this, arr); // 优化性能
        } else {
            this.push.apply(this, args);
        }
    }

    public static function fromArguments(expectedLength:Number, funcArgs:FunctionArguments):args {
        var startIndex:Number = expectedLength > 0 ? expectedLength - 1 : 0;
        var params:Array = [];
        
        for (var i:Number = startIndex; i < funcArgs.length; i++) {
            params.push(funcArgs[i]);
        }
        
        return new args(params);
    }

    public function splice(start:Number, deleteCount:Number):Array {
        return super.splice(start, deleteCount);
    }

    public function valueOf():Array {
        return this.slice();
    }

    public function toArray():Array {
        return this.slice(); // 返回副本
    }

    public function toString():String {
        return "[Arguments] " + this.join(", ");
    }
}
