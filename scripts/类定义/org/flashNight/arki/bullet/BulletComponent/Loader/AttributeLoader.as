import org.flashNight.arki.bullet.BulletComponent.Loader.*;


class org.flashNight.arki.bullet.BulletComponent.Loader.AttributeLoader implements IComponentLoader {
    public function AttributeLoader() {
        // 构造函数，可用于初始化参数
    }
    
    /**
     * 实现 IComponentLoader 接口的方法，解析 <attribute> 节点中的数据
     * @param data:Object 子弹的原始数据节点
     * @return Object 解析后的属性信息对象
     */
    public function load(data:Object):Object {
        var attributeNode:Object = data.attribute;
        
        // 如果 attribute 节点存在，则读取配置项
        if(attributeNode != undefined) {
            var attributeInfo:Object = {};

            if(attributeNode.pierceLimit != undefined) {
                attributeInfo.pierceLimit = Number(attributeNode.pierceLimit);
            }

            if(attributeNode.FLAG_GRENADE != undefined) {
                attributeInfo.FLAG_GRENADE = Boolean(attributeNode.FLAG_GRENADE);
            }

            if(attributeNode.hitMark != undefined) {
                attributeInfo.hitMark = String(attributeNode.hitMark);
            }
            
            return attributeInfo;
        }
        
        return null;
    }
}
