// 文件路径: org/flashNight/gesh/arguments/args.as
/**
 * 该类模拟了ES6中...args的功能，用于处理函数的剩余参数。
 * 继承自Array类，可以在函数参数列表的末尾使用它来处理动态数量的参数。
 * 
 * @class args
 * @extends Array
 */
class org.flashNight.gesh.arguments.args extends Array {
    
    /**
     * 构造函数，初始化args类实例。
     * 
     * 如果传入的是一个数组，将其作为参数列表；否则，使用原始的arguments对象。
     * 
     * @constructor
     */
    public function args() {
        super();  // 调用父类构造函数，初始化数组
        _init(arguments);  // 调用私有方法初始化参数
    }

    /**
     * 私有方法，用于初始化args实例。
     * 如果参数为一个数组，则将该数组元素作为参数，否则直接将arguments作为数组处理。
     * 
     * @private
     * @param {FunctionArguments} args - 函数传递的arguments对象
     */
    private function _init(args:FunctionArguments):Void {
        var len:Number = args.length;  // 获取参数列表的长度
        if (len > 0) {
            // 如果只有一个参数且该参数是数组，则展开该数组作为参数
            var src:Array = (len == 1 && args[0] instanceof Array) 
                ? args[0]  // 传入的是数组，展开使用
                : args;    // 否则直接使用arguments
            
            // 使用原生方法一次性追加元素到当前数组
            this.push.apply(this, src);
        }
    }

    /**
     * 从函数的arguments对象创建一个args实例。
     * 该方法确保从函数的实际参数中提取出正确的剩余参数，并返回一个args实例。
     * 
     * @static
     * @param {Number} expectedLength - 期望的参数长度
     * @param {FunctionArguments} funcArgs - 函数传递的arguments对象
     * @return {args} - 返回一个args实例
     */
    public static function fromArguments(expectedLength:Number, funcArgs:FunctionArguments):args {
        var len:Number = funcArgs.length;  // 获取参数的长度
        var temp:Number;

        var i:Number =  expectedLength > 0 ? 
                        ((expectedLength - 1 & ((temp = expectedLength - 1 - len, temp) >> 31)) | (len & ~(temp >> 31))) :
                        0;  // 计算实际参数的起始索引
        
        // 计算实际参数的长度（确保非负）
        var params:Array = new Array(len - i);
        
        // 使用while循环避免使用do...while和if判断
        temp = i;
        while (i < len) {
            params[i - temp] = funcArgs[i++];  // 从funcArgs中提取剩余参数
        }
        
        // 返回新的args实例
        return new args(params);
    }

    /**
     * 将args实例与其他数组连接，返回一个新的args实例。
     * 
     * @param {...*} arguments - 要连接的其他数组或值
     * @return {args} - 返回连接后的args实例
     */
    public function concat():Array {
        var result:Array = super.concat.apply(this, arguments);  // 调用父类concat方法
        return new args(result);  // 返回新的args实例
    }

    /**
     * 返回当前args实例的原生数组对象。
     * 
     * @return {Array} - 返回原生数组对象的副本
     */
    public function valueOf():Array {
        // 使用更高效的数组拷贝方式返回原生数组对象
        return super.concat();
    }

    /**
     * 将args实例转换为数组并返回。
     * 返回的内容是args，因此也可以通过数组检查
     * 
     * @return {Array} - 返回转换后的数组
     */
    public function toArray():Array {
        return this.concat();  // 通过concat方法返回新的数组
    }

    /**
     * 返回args实例的字符串表示。
     * 如果args为空数组，返回"[Arguments]"，否则返回详细的字符串表示。
     * 
     * @return {String} - args实例的字符串表示
     */
    public function toString():String {
        return this.length === 0 ? "[Arguments]" : "[Arguments] " + this.join(", ");
    }
}
