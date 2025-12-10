import org.flashNight.arki.bullet.BulletComponent.Loader.*;


class org.flashNight.arki.bullet.BulletComponent.Loader.AttributeLoader implements IComponentLoader {

    // === 宏展开：在加载阶段直接转换为状态标志位 ===
    // 编译期展开 STATE_GRENADE_XML，避免运行时污染 Obj
    #include "../macros/STATE_GRENADE_XML.as"

    public function AttributeLoader() {
        // 构造函数，可用于初始化参数
    }

    /**
     * 实现 IComponentLoader 接口的方法，解析 <attribute> 节点中的数据
     * @param data:Object 子弹的原始数据节点
     * @return Object 解析后的属性信息对象
     *
     * === XML属性转换机制 ===
     * 部分XML属性会被直接转换为 stateFlags 预置值，而非作为独立属性传递：
     * • FLAG_GRENADE → stateFlags |= STATE_GRENADE_XML
     *
     * 这样设计的好处：
     * 1. 避免"污染"传播到 Obj，无需后续 delete 清理
     * 2. 减少运行时开销（delete 操作在AS2中有一定成本）
     * 3. 职责清晰：加载器负责格式转换，初始化器只做合并
     */
    public function load(data:Object):Object {
        var attributeNode:Object = data.attribute;

        // 如果 attribute 节点存在，则读取配置项
        if(attributeNode != undefined) {
            var attributeInfo:Object = {};
            var sf:Number = 0;  // 预置的 stateFlags

            if(attributeNode.pierceLimit != undefined) {
                attributeInfo.pierceLimit = Number(attributeNode.pierceLimit);
            }

            // FLAG_GRENADE 不再作为属性传递，直接转换为 stateFlags 位
            if(attributeNode.FLAG_GRENADE != undefined && Boolean(attributeNode.FLAG_GRENADE)) {
                sf |= STATE_GRENADE_XML;
            }

            if(attributeNode.hitMark != undefined) {
                attributeInfo.hitMark = String(attributeNode.hitMark);
            }

            // 仅当有预置状态位时才写入
            if(sf != 0) {
                attributeInfo.stateFlags = sf;
            }

            return attributeInfo;
        }

        return null;
    }
}
