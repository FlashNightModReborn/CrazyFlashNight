// AccessorFactory.as
class org.flashNight.gesh.property.AccessorFactory {
    // 构造函数
    public function AccessorFactory() {
        // 不需要初始化
    }
    
    /**
     * 静态方法：为目标对象添加访问器属性
     * @param target 目标对象
     * @param baseProp 基础属性名
     * @param initialValue 基础属性的初始值
     * @param dependents 依赖属性的配置数组
     */
    public static function addAccessor(target:Object, baseProp:String, initialValue:Number, dependents:Array):Void {
        // 私有存储变量名（使用下划线前缀）
        var privateVarName:String = "_" + baseProp;
        target[privateVarName] = initialValue;
        
        // 定义基础属性的 getter
        var getterBase:Function = function():Number {
            return target[privateVarName];
        };
        
        // 定义基础属性的 setter
        var setterBase:Function = function(newValue:Number):Void {
            if (newValue >= 0) {
                target[privateVarName] = newValue;
            } else {
                trace("无效的 " + baseProp + " 值: " + newValue);
            }
        };
        
        // 使用 addProperty 添加基础属性的 getter 和 setter
        target.addProperty(baseProp, getterBase, setterBase);
        
        // 为每个依赖属性添加只读的 getter
        for (var i:Number = 0; i < dependents.length; i++) {
            var dep:Object = dependents[i];
            var depProp:String = dep.propName;
            var computeFunc:Function = dep.compute;
            
            // 创建依赖属性的 getter，确保闭包正确捕获当前的 computeFunc 和 privateVarName
            var getterDep:Function = AccessorFactory.createDependentGetter(target, privateVarName, computeFunc);
            
            // 使用 addProperty 添加依赖属性的 getter（只读）
            target.addProperty(depProp, getterDep, null);
        }
    }
    
    /**
     * 静态辅助方法：创建依赖属性的 getter
     * @param target 目标对象
     * @param privateVarName 私有存储变量名
     * @param computeFunc 计算函数，根据基础属性值计算依赖属性值
     * @return Function 依赖属性的 getter 函数
     */
    public static function createDependentGetter(target:Object, privateVarName:String, computeFunc:Function):Function {
        return function():Number {
            return computeFunc(target[privateVarName]);
        };
    }
}
