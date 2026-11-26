/** Pure checks for the snapshot shape consumed by the save reader. */
class org.flashNight.neur.Server.SaveSnapshotSchema {
    public static function validate(mydata:Object):Boolean {
        if (mydata == undefined) return false;
        if (mydata.version != "3.0") return false;
        if (mydata.lastSaved == undefined) return false;

        // 数组槽位（unpackGameState 消费的最大索引+1）
        if (!(mydata[0] instanceof Array) || mydata[0].length < 14) return false;
        if (mydata[0][0] == undefined || mydata[0][0] == null || String(mydata[0][0]).length == 0) return false;
        if (mydata[0][3] == undefined || isNaN(Number(mydata[0][3]))) return false;
        if (!(mydata[1] instanceof Array) || mydata[1].length < 28) return false;
        if (mydata[3] == undefined) return false;
        if (!(mydata[4] instanceof Array) || mydata[4].length < 2) return false;
        if (!(mydata[5] instanceof Array)) return false;
        if (!(mydata[7] instanceof Array) || mydata[7].length < 5) return false;

        // 对象字段
        if (mydata.inventory == undefined) return false;
        if (mydata.inventory.背包 == undefined) return false;
        if (mydata.inventory.装备栏 == undefined) return false;
        if (mydata.inventory.药剂栏 == undefined) return false;
        if (mydata.inventory.仓库 == undefined) return false;
        if (mydata.inventory.战备箱 == undefined) return false;
        if (mydata.collection == undefined) return false;
        if (mydata.collection.材料 == undefined) return false;
        if (mydata.collection.情报 == undefined) return false;
        if (mydata.infrastructure == undefined) return false;

        // 尾部字段校验 — 每个 loadFromMydata 消费的子字段都必须存在
        if (mydata.tasks == undefined) return false;
        if (mydata.tasks.tasks_to_do == undefined) return false;
        if (mydata.tasks.tasks_finished == undefined) return false;
        if (mydata.tasks.task_chains_progress == undefined) return false;
        if (mydata.pets == undefined) return false;
        if (mydata.pets.宠物信息 == undefined) return false;
        if (mydata.pets.宠物领养限制 == undefined) return false;
        if (mydata.shop == undefined) return false;
        if (mydata.shop.商城已购买物品 == undefined) return false;
        if (mydata.shop.商城购物车 == undefined) return false;

        return true;
    }
}
