class org.flashNight.arki.unit.TickManager {
    private var 目标缓存:Object; // 存储目标缓存
    private var 当前帧数:Number; // 当前帧数计数器

    public function TickManager() {
        this.目标缓存 = {}; // 初始化目标缓存对象
        this.当前帧数 = 0;  // 初始化帧数
    }

    /**
     * 更新帧数，用于同步 TickManager 的状态。
     */
    public function 更新帧数():Void {
        this.当前帧数++;
    }

    /**
     * 更新目标缓存方法，无缝衔接 _root.帧计时器.更新目标缓存 的逻辑。
     * @param 自机:Object - 当前自机对象
     * @param 更新间隔:Number - 刷新间隔帧数
     * @param 请求类型:String - 目标类型（如 "敌人" 或 "友军"）
     * @param 自机状态键:String - 自机的状态键，用于区分缓存
     */
    public function 更新目标缓存(自机:Object, 更新间隔:Number, 请求类型:String, 自机状态键:String):Void {
        var SORT_KEY:String = "right";

        // 设置默认更新间隔
        更新间隔 = isNaN(更新间隔) ? 1 : 更新间隔;

        // 初始化目标缓存结构
        if (!this.目标缓存[自机状态键]) {
            this.目标缓存[自机状态键] = {};
        }
        if (!this.目标缓存[自机状态键][请求类型]) {
            this.目标缓存[自机状态键][请求类型] = { 数据: [], nameIndex: {}, 最后更新帧数: 0 };
        }

        var cache:Object = this.目标缓存[自机状态键][请求类型];
        var data:Array = cache.数据;
        var nameIndex:Object = cache.nameIndex;

        // 检查是否需要更新
        if (this.当前帧数 - cache.最后更新帧数 < 更新间隔) {
            return; // 如果未达到更新间隔，直接返回
        }

        // 定义条件判断函数
        var 条件判断函数:Function;
        switch (请求类型) {
            case "敌人":
                条件判断函数 = function(目标:Object):Boolean {
                    return 自机.是否为敌人 != 目标.是否为敌人;
                };
                break;
            case "友军":
            default:
                条件判断函数 = function(目标:Object):Boolean {
                    return 自机.是否为敌人 == 目标.是否为敌人;
                };
        }

        // 遍历游戏世界中的所有目标
        var 游戏世界:Object = _root.gameworld;
        for (var 待选目标:String in 游戏世界) {
            var 目标:Object = 游戏世界[待选目标];
            var 名称:String = 目标._name;

            if (目标.hp > 0 && 条件判断函数(目标)) {
                if (!nameIndex[名称]) {
                    目标.aabbCollider.updateFromUnitArea(目标);
                    var targetRight:Number = 目标.aabbCollider.right;

                    var insertIndex:Number = 0;
                    while (insertIndex < data.length && data[insertIndex].aabbCollider.right < targetRight) {
                        insertIndex++;
                    }
                    data.splice(insertIndex, 0, 目标);
                    nameIndex[名称] = true;
                } else {
                    目标.aabbCollider.updateFromUnitArea(目标);
                    var newRight:Number = 目标.aabbCollider.right;

                    var currentIndex:Number = -1;
                    for (var i:Number = 0; i < data.length; i++) {
                        if (data[i]._name == 名称) {
                            currentIndex = i;
                            break;
                        }
                    }

                    if (currentIndex != -1) {
                        data.splice(currentIndex, 1);

                        insertIndex = 0;
                        while (insertIndex < data.length && data[insertIndex].aabbCollider.right < newRight) {
                            insertIndex++;
                        }
                        data.splice(insertIndex, 0, 目标);
                    }
                }
            } else {
                if (nameIndex[名称]) {
                    var removeIndex:Number = -1;
                    for (var j:Number = 0; j < data.length; j++) {
                        if (data[j]._name == 名称) {
                            removeIndex = j;
                            break;
                        }
                    }
                    if (removeIndex != -1) {
                        data.splice(removeIndex, 1);
                        delete nameIndex[名称];
                    }
                }
            }
        }

        // 更新最后更新帧数
        cache.最后更新帧数 = this.当前帧数;
    }
}
