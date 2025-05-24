/**
 * Event 类表示一个事件，包含事件的名称和相关的数据。
 * 该类用于在事件总线或事件处理系统中传递事件信息。
 */
class org.flashNight.neur.Event.Event {
    public var name:String;  // 事件的名称
    public var data:Object;  // 事件附带的数据

    /**
     * 构造函数，用于创建一个新的事件实例。
     * 
     * @param name 事件的名称，用于标识事件类型。
     * @param data 事件附带的数据，通常包含事件相关的上下文信息或参数。
     */
    public function Event(name:String, data:Object) {
        this.name = name;     // 将传入的事件名称赋值给实例变量
        this.data = data;     // 将传入的数据赋值给实例变量
    }
}
