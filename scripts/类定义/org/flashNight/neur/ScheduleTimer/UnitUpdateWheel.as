/**
UnitUpdateWheel.as  （无链表 / 无重复任务）
——————————————————————————————————————————
以极端轻量级的方式托管所有单位的update事件。
固定 WHEEL_SIZE = 4 槽，对应 4 帧的步长。
每帧拨轮一次，对该槽里所有单位发布update事件，并自动检测移除已卸载的单位引用。
*/
class org.flashNight.neur.ScheduleTimer.UnitUpdateWheel {
    // ————————————————————————
    // 配置常量 & 私有字段
    // ————————————————————————
    private static var WHEEL_SIZE:Number = 4;           // 时间轮槽数
    private var slots:Array;                            // Array<MovieClip>[]，每槽保存单位列表
    private var unitDict:Object;                        // 记录unit影片剪辑的引用
    private var posDict:Object;                         // 记录unit所在的槽位
    private var counter:Number = 0;                     // 为每个unit分配唯一的全局ID
    private var pos:Number = WHEEL_SIZE - 1;            // 当前读写指针，初始化到"上一次帧"

    private static var inst:UnitUpdateWheel;            // 单例引用
    
    // ————————————————————————
    // 单例获取
    // ————————————————————————
    /**
     * 返回全局唯一实例
     */
    public static function I():UnitUpdateWheel {
        return inst || (inst = new UnitUpdateWheel());
    }
    
    // ————————————————————————
    // 构造函数（私有）
    // ————————————————————————
    private function UnitUpdateWheel() {
        // 初始化各槽为一个空数组
        slots = new Array(WHEEL_SIZE);
        for (var i:Number = 0; i < WHEEL_SIZE; ++i) {
            slots[i] = [];
        }

        unitDict = {};
        posDict = {};
    }
    
    // ————————————————————————
    // 公开方法
    // ————————————————————————
    /**
     * 添加 update 任务
     * @param unit     目标单位
     */
    public function add(unit:MovieClip):Number {
        if(unit.updateEventComponentID != null){
            return unit.updateEventComponentID;
        }
        counter++;
        slots[pos].push(counter);
        unit.updateEventComponentID = counter;
        unitDict[counter] = unit;
        posDict[counter] = pos;
        return counter;
    }

    /**
     * 移除 update 任务
     * @param unit     目标单位
     */
    public function remove(unit:MovieClip):Void {
        var id = unit.updateEventComponentID;
        var list = slots[posDict[id]];
        if(list == null) return;
        // 遍历目标槽位，找到unit所在位置并移除
        for (var i = list.length - 1; i > -1; i--) {
            if(unitDict[list[i]] === unit){
                delete unitDict[id];
                delete posDict[id];
                list.splice(i,1);
                unit.updateEventComponentID = null;
                return;
            }
        }
    }
    
    /**
     * 对当前槽所有unit发布UpdateEventComponent事件
     * 指针前移一格
     */
    public function tick():Void {
        // 先移动指针到下一槽
        pos = (pos + 1) % WHEEL_SIZE;
        
        // 再执行当前槽的事件发布
        var list:Array = slots[pos];
        for (var i = list.length - 1; i > -1; i--) {
            var unit = unitDict[list[i]];
            // 通过读取单位身上的事件分发器来判断单位是否存在，若不存在则自动移除
            if(unit.dispatcher == null){
                delete unitDict[list[i]];
                delete posDict[list[i]];
                list.splice(i,1);
                continue;
            }
            // 发布UpdateEventComponent事件
            unit.dispatcher.publish("UpdateEventComponent", unit);
        }
    }
    
    /**
     * 重置时间轮状态
     */
    public function reset():Void {
        for (var i:Number = 0; i < WHEEL_SIZE; ++i) {
            slots[i] = [];
        }
        pos = WHEEL_SIZE - 1;
        unitDict = {};
        posDict = {};
    }
}