// ExampleAllocable 类
import org.flashNight.neur.Event.Allocable.*;

class org.flashNight.neur.Event.Allocable.ExampleAllocable implements IAllocable {
    public var data:Array;

    public function ExampleAllocable()
    {
        this.data = [];
    }

    // 初始化对象
    public function initialize():Void {
        // 使用 arguments 对象获取额外参数
        this.data = [];
        for (var i:Number = 0; i < arguments.length; i++) {
            this.data.push(arguments[i]);
        }
    }

    // 重置对象
    public function reset():Void {
        // 清理状态
        this.data = [];
    }
}
