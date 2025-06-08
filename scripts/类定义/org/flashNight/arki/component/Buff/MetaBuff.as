// org/flashNight/arki/component/Buff/MetaBuff.as
import org.flashNight.arki.component.Buff.*;

class org.flashNight.arki.component.Buff.MetaBuff implements IBuff {
    private var _id:String;
    private var _logicFunction:Function;   // 复杂逻辑函数
    private var _condition:Function;       // 激活条件
    private var _dataContainer:Object;     // 数据区
    private var _active:Boolean;
    private var _dependencies:Array;       // 依赖的其他Buff或条件
    
    public function MetaBuff(
        id:String,
        logicFunction:Function,
        condition:Function
    ) {
        this._id = id;
        this._logicFunction = logicFunction;
        this._condition = condition;
        this._dataContainer = {};
        this._dependencies = [];
        this._active = true;
    }
    
    /**
     * MetaBuff的applyEffect实现：执行复杂逻辑
     */
    public function applyEffect(calculator:IBuffCalculator, context:BuffContext):Void {
        if (!this.isActive()) return;
        
        // 检查激活条件
        if (this._condition != null && !this._condition.call(this, context)) {
            return;
        }
        
        // 执行复杂逻辑 - 这里可能会：
        // 1. 动态创建PodBuff并应用
        // 2. 修改其他Buff的状态
        // 3. 根据条件进行不同的计算
        // 4. 与游戏系统其他部分交互
        if (this._logicFunction != null) {
            this._logicFunction.call(this, calculator, context, this._dataContainer);
        }
    }
    
    public function getId():String {
        return this._id;
    }
    
    public function getType():String {
        return "MetaBuff";
    }
    
    public function isActive():Boolean {
        return this._active;
    }
    
    public function destroy():Void {
        this._active = false;
        this._logicFunction = null;
        this._condition = null;
        this._dataContainer = null;
        this._dependencies = null;
    }
    
    // 数据区访问
    public function setData(key:String, value):Void {
        this._dataContainer[key] = value;
    }
    
    public function getData(key:String) {
        return this._dataContainer[key];
    }
    
    // 依赖管理
    public function addDependency(dependency):Void {
        this._dependencies.push(dependency);
    }
    
    public function getDependencies():Array {
        return this._dependencies.slice(); // 返回副本
    }
}