import org.flashNight.arki.component.Damage.*;

class org.flashNight.arki.component.Damage.DamageManager {
    
    private var handleList:Array;  // IDamageHandle[]

    public function DamageManager() {
        this.handleList = [];
        // 在这里写死执行顺序
        initDefaultHandles();
    }

    private function initDefaultHandles():Void {
        // 按原先脚本先后顺序，将关键逻辑拆分插入
        this.handleList.push(new HandleDefense());     // 防御、伤害类型
        this.handleList.push(new HandleDodgeBlock()); // 躲闪、格挡
        this.handleList.push(new HandleScatter());    // 霰弹
        this.handleList.push(new HandleNanoToxic());     // 中毒、击溃、吸血、斩杀
        this.handleList.push(new HandleFinalize());   // 分段伤害、扣血
    }

    /**
     * 执行伤害流程
     */
    public function applyDamage(context:DamageContext):Void {
        for (var i:Number = 0; i < this.handleList.length; i++) {
            var handle:IDamageHandle = IDamageHandle(this.handleList[i]);
            handle.execute(context);
        }
    }
    
    /**
     * 如果你想在某些特殊子弹或特殊逻辑中，自定义顺序或额外 Handle 
     * 可以在此处操作 handleList
     */
    public function addHandle(handle:IDamageHandle):Void {
        this.handleList.push(handle);
    }

    public function insertHandleAt(handle:IDamageHandle, index:Number):Void {
        this.handleList.splice(index, 0, handle);
    }

    // ...更多自定义方法...
}
