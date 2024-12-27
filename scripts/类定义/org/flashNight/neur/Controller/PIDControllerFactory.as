import org.flashNight.neur.Controller.*;
import org.flashNight.gesh.xml.LoadXml.*;

class org.flashNight.neur.Controller.PIDControllerFactory {
    // ===== 私有变量定义 =====
    private static var instance:PIDControllerFactory; // 单例实例
    
    // ===== 构造函数 =====
    /**
     * 构造函数 - 私有化以实现单例模式
     */
    private function PIDControllerFactory() {
        // 私有构造函数，防止外部实例化
    }
    
    // ===== 获取单例实例 =====
    /**
     * 获取 PIDControllerFactory 的单例实例
     * @return PIDControllerFactory 单例实例
     */
    public static function getInstance():PIDControllerFactory {
        if (instance == undefined) {
            instance = new PIDControllerFactory();
        }
        return instance;
    }
    
    // ===== 创建 PIDController 方法 =====
    /**
     * 创建并配置 PIDController 实例
     * @param onSuccess:Function 成功回调，接收 PIDController 实例作为参数
     * @param onFailure:Function 失败回调，无参数
     */
    public function createPIDController(onSuccess:Function, onFailure:Function):Void {
        // 获取配置加载器实例
        var pidControllerConfigLoader:PIDControllerConfigLoader = PIDControllerConfigLoader.getInstance();
        
        // 创建 PIDController 实例，使用默认参数初始化
        var pid:PIDController = new PIDController(0, 0, 0, 1000, 0.1);
        
        // 保存当前上下文引用，以便在回调中使用
        var self = this;
        
        // 加载 PIDControllerConfig.xml 配置文件
        pidControllerConfigLoader.loadPIDControllerConfig(function (data:Object):Void {
            // 配置加载成功，设置 PIDController 参数
            self.configurePIDController(pid, data);
            
            // 调用成功回调，传递配置好的 PIDController 实例
            if (onSuccess != undefined) {
                onSuccess(pid);
            }
        }, function ():Void {
            // 配置加载失败，调用失败回调
            if (onFailure != undefined) {
                onFailure();
            }
        });
    }
    
    // ===== 配置 PIDController 参数 =====
    /**
     * 根据配置数据设置 PIDController 实例的参数
     * @param pid:PIDController 需要配置的 PIDController 实例
     * @param data:Object 从 XML 加载的配置数据
     */
    private function configurePIDController(pid:PIDController, data:Object):Void {
        // 设置目标帧率（示例用途）
        // 假设外部有一个变量存储目标帧率，具体实现根据实际需求调整
        // this.targetFrameRate = data.targetFrameRate; // 示例代码，需在实际上下文中定义
        
        // 提取参数对象
        var param:Object = data.parameters;
        
        // 设置 PIDController 的各项参数
        pid.setKp(param.kp); // 设置比例增益
        pid.setKi(param.ki); // 设置积分增益
        pid.setKd(param.kd); // 设置微分增益
        pid.setIntegralMax(param.integralMax); // 设置积分限幅
        pid.setDerivativeFilter(param.derivativeFilter); // 设置微分滤波系数
        
        // 输出配置后的 PIDController 状态，便于调试
        trace(pid.toString() + " 目标帧率: " + data.targetFrameRate);
    }
}
