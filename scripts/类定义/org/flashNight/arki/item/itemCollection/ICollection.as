interface org.flashNight.arki.item.itemCollection.ICollection {
    /**
     * 获取物品对象
     * @param key 目标键
     * @return 目标物品对象
     */
    function getItem(key:String):Object;

    /**
     * 获取全部物品集合数据
     * @return 物品集合数据
     */
    function getItems():Object;
    
    /**
     * 判断某个键是否为空
     * @param key 目标键
     * @return 判断结果
     */
    function isEmpty(key:String):Boolean;
    
    /**
     * 判断是否能添加指定物品
     * @param key 目标键
     * @param item 目标物品
     * @return 判断结果
     */
    function isAddable(key:String,item):Boolean;

    /**
     * 添加物品
     * @param key 目标键
     * @param item 目标物品
     * @return 是否成功放入
     */
    function add(key:String,item):Boolean;

    /**
     * 移除物品
     * @param key 目标键
     */
    function remove(key:String):Void;
}
