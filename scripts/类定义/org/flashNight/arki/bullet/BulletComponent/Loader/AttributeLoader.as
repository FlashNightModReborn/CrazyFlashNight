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
        var attributeInfo:Object = {};
        var attributeNode:Object = data.attribute;
        
        // 如果 attribute 节点存在，则读取配置项
        if(attributeNode != undefined) {
            // 读取穿刺限制配置，默认配额5
            attributeInfo.pierceLimit = (attributeNode.pierceLimit != undefined) ? Number(attributeNode.pierceLimit) : 5;
            // 如果以后还有更多属性，可以在这里继续解析并赋值
            return attributeInfo;
        }
        
        return null;
    }
}
