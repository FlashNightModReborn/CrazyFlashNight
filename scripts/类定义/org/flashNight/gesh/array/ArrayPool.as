import org.flashNight.sara.util.*;

class org.flashNight.gesh.array.ArrayPool extends LightObjectPool {
    private var initialCapacity:Number;

    public function ArrayPool(initialCapacity:Number) {
        super(function():Array { 
            return new Array(initialCapacity); 
        });
        this.initialCapacity = initialCapacity;
    }

    public function releaseObject(obj:Object):Void {
        // 严格过滤非数组对象和空值
        if (obj == null || !(obj instanceof Array)) return;
        
        // 清空内容，并重置数组至初始容量
        obj.length = 0;
        obj.length = this.initialCapacity;
        super.releaseObject(obj);
    }
}
