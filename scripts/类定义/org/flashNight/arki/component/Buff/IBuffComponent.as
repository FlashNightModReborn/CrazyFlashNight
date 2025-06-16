interface org.flashNight.arki.component.Buff.IBuffComponent {
    /**
     * 组件间消息处理
     * @param messageType 消息类型
     * @param data 消息数据
     */
    function handleMessage(messageType:String, data:Object):Object;
}