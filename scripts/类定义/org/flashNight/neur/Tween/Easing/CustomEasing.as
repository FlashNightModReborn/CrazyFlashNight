import org.flashNight.neur.Tween.*;
import org.flashNight.neur.Tween.Easing.*;

class org.flashNight.neur.Tween.Easing.CustomEasing implements IEasing {
    private var _func:Function;

    public function CustomEasing(func:Function) {
        _func = func;
    }

    public function ease(t:Number, b:Number, c:Number, d:Number):Number {
        // 提取附加参数
        var args:Array = [];
        for (var i:Number = 4; i < arguments.length; i++) {
            args.push(arguments[i]);
        }

        // 构建参数数组并调用原始函数
        var fullArgs:Array = [t, b, c, d];
        for (var j:Number = 0; j < args.length; j++) {
            fullArgs.push(args[j]);
        }

        return _func.apply(null, fullArgs);
    }
}
