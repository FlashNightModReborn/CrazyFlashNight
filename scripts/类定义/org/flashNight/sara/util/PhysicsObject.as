import org.flashNight.sara.util.Vector;
import org.flashNight.sara.util.AABB;
import org.flashNight.sara.graphics.*;

/**
 * PhysicsObject 类
 * 负责管理物理属性、应用力和力矩、更新物理状态，以及处理与其他物理对象的碰撞检测与响应。
 */
class org.flashNight.sara.util.PhysicsObject extends MovieClip {
    
    // ------------------ 物理属性 ------------------
    public var position:Vector;
    public var previousPosition:Vector;
    public var velocity:Vector;
    public var acceleration:Vector;
    public var mass:Number;
    public var inverseMass:Number; // 质量的倒数，便于计算
    public var restitution:Number; // 恢复系数（弹性）
    public var friction:Number;    // 摩擦系数
    
    // ------------------ 角动力学属性 ------------------
    public var angle:Number;               // 角度（弧度）
    public var angularVelocity:Number;     // 角速度
    public var torque:Number;              // 力矩
    public var inertia:Number;             // 惯性矩
    public var inverseInertia:Number;      // 惯性矩的倒数
    
    // ------------------ 碰撞属性 ------------------
    public var aabb:AABB;
    
    // ------------------ 力的累积 ------------------
    private var forceAccumulator:Vector;
    private var torqueAccumulator:Number;

    // ------------------ 调试信息 ------------------
    private var debugLayer:MovieClip;
    
    /**
     * 构造函数
     */
    public function PhysicsObject() {
        super();
        
        // 初始化物理属性
        this.position = Vector.getPosition(this);
        this.previousPosition = this.position.clone();
        this.velocity = new Vector(0, 0);
        this.acceleration = new Vector(0, 0);
        this.mass = 1; // 默认质量为1
        this.inverseMass = (this.mass > 0) ? 1 / this.mass : 0;
        this.restitution = 0.5; // 默认恢复系数
        this.friction = 0.1;    // 默认摩擦系数
        
        // 初始化角动力学属性
        this.angle = 0;
        this.angularVelocity = 0;
        this.torque = 0;
        this.inertia = calculateInertia();
        this.inverseInertia = (this.inertia > 0) ? 1 / this.inertia : 0;
        
        // 初始化力的累积
        this.forceAccumulator = new Vector(0, 0);
        this.torqueAccumulator = 0;
        
        // 初始化AABB
        this.aabb = AABB.fromMovieClip(this, 0); // 假设 z_offset 为0
    }
    
    /**
     * 计算惯性矩
     * 假设物体为矩形：I = (1/12) * m * (width^2 + height^2)
     * @return 计算得到的惯性矩
     */
    private function calculateInertia():Number {
        return (1 / 12) * this.mass * (this._width * this._width + this._height * this._height);
    }
    
    /**
     * 应用一个力到物体上
     * @param force 要应用的力向量
     */
    public function applyForce(force:Vector):Void {
        this.forceAccumulator.plus(force);
    }
    
    /**
     * 应用一个力矩到物体上
     * @param torque 要应用的力矩（标量）
     */
    public function applyTorque(torque:Number):Void {
        this.torqueAccumulator += torque;
    }
    
    /**
     * 物理更新方法，将由测试框架调用
     * @param deltaTime 时间步长
     * @param globalDamping 全局阻尼系数
     */
    public function update(deltaTime:Number, globalDamping:Number):Void {
        // 线性运动更新
        // F = m * a => a = F / m
        var accelerationThisFrame:Vector = this.forceAccumulator.clone().multNew(this.inverseMass);
        this.acceleration.copy(accelerationThisFrame);
        
        // 更新速度：v = v + a * dt
        this.velocity.plus(this.acceleration.clone().multNew(deltaTime));
        
        // 更新位置：p = p + v * dt
        this.position.plus(this.velocity.clone().multNew(deltaTime));
        this.setPosition(this.position);
        
        // 应用全局阻尼
        this.velocity.mult(globalDamping);
        
        // 角动力学更新
        var angularAcceleration:Number = this.torqueAccumulator * this.inverseInertia;
        this.angularVelocity += angularAcceleration * deltaTime;
        this.angularVelocity *= globalDamping; // 阻尼
        this.angle += this.angularVelocity * deltaTime;
        this._rotation = this.angle * (180 / Math.PI); // Flash 中旋转以度为单位
        
        // 重置力和力矩累积器
        this.forceAccumulator.setTo(0, 0);
        this.torqueAccumulator = 0;
        
        // 更新 AABB
        this.aabb = AABB.fromMovieClip(this, 0);
    }
    
    /**
     * 设置物体的位置
     * @param pos 新的位置向量
     */
    public function setPosition(pos:Vector):Void {
        this._x = pos.x;
        this._y = pos.y;
    }
    
    /**
     * 处理与另一个物理对象的碰撞
     * @param other 另一个物理对象
     * @param coeffRest 恢复系数
     * @param coeffFric 摩擦系数
     */
    public function resolveCollision(other:PhysicsObject, coeffRest:Number, coeffFric:Number):Void {
        // 计算最小移动向量（MTV）
        var mtv:Object = this.aabb.getMTV(other.aabb);
        if (mtv != null) {
            // 分离两个物体
            var separation:Vector = new Vector(mtv.dx, mtv.dy);
            var totalInverseMass:Number = this.inverseMass + other.inverseMass;
            if (totalInverseMass == 0) return; // 两者都是静止的
            
            // 按质量分配分离距离
            var separationThis:Vector = separation.clone().multNew(this.inverseMass / totalInverseMass);
            var separationOther:Vector = separation.clone().multNew(-other.inverseMass / totalInverseMass);
            
            this.position.plus(separationThis);
            other.position.plus(separationOther);
            this.setPosition(this.position);
            other.setPosition(other.position);
            
            // 计算相对速度
            var relativeVelocity:Vector = this.velocity.minus(other.velocity);
            var normal:Vector = new Vector(mtv.dx, mtv.dy).normalize();
            var velAlongNormal:Number = relativeVelocity.dot(normal);
            
            if (velAlongNormal > 0) return; // 如果相对速度在法线方向上是分离的
            
            // 计算恢复系数
            var e:Number = Math.min(this.restitution, other.restitution);
            
            // 计算冲量
            var j:Number = -(1 + e) * velAlongNormal;
            j /= totalInverseMass;
            
            // 应用冲量
            var impulse:Vector = normal.clone().multNew(j);
            this.velocity.plus(impulse.clone().multNew(this.inverseMass));
            other.velocity.minus(impulse.clone().multNew(other.inverseMass));
            
            // 应用摩擦
            var tangent:Vector = relativeVelocity.minus(normal.clone().multNew(relativeVelocity.dot(normal))).normalize();
            var jt:Number = -relativeVelocity.dot(tangent);
            jt /= totalInverseMass;
            
            var mu:Number = Math.sqrt(this.friction * other.friction);
            var frictionImpulse:Number = (Math.abs(jt) < j * mu) ? jt : -j * mu;
            var frictionVector:Vector = tangent.clone().multNew(frictionImpulse);
            this.velocity.plus(frictionVector.clone().multNew(this.inverseMass));
            other.velocity.minus(frictionVector.clone().multNew(other.inverseMass));
        }
    }
    
    /**
     * 释放物理对象资源
     */
    public function dispose():Void {
        // 清理引用
        this.position = null;
        this.previousPosition = null;
        this.velocity = null;
        this.acceleration = null;
        this.aabb = null;
        this.forceAccumulator = null;
        this.torqueAccumulator = null;
    }
    
    /**
     * 绘制调试信息（如 AABB 和速度向量）
     */
    public function paintDebug():Void {
        // 创建一个独立的调试层
        if (this.debugLayer == undefined) {
            this.debugLayer = this.createEmptyMovieClip("debugLayer", this.getNextHighestDepth());
        }
        
        // 清除之前的绘图
        this.debugLayer.clear();
        
        // 绘制 AABB
        Graphics.drawAABB(this.debugLayer, this.aabb);
        
        // 绘制速度向量
        Graphics.drawVector(this.debugLayer, this.position, this.velocity, 0xFF0000);
    }

    
    // ------------------ 静态方法 ------------------
    
    /**
     * 通过 attachMovie 创建一个新的 PhysicsObject 实例
     * @param target MovieClip 目标父级
     * @param linkageId 链接标识符，必须在库中设置
     * @param instanceName 实例名称
     * @param depth 实例深度
     * @return 新创建的 PhysicsObject 实例
     */
    public static function create(target:MovieClip, linkageId:String, instanceName:String, depth:Number):PhysicsObject {
        var newObj:MovieClip = target.attachMovie(linkageId, instanceName, depth);
        var physicsObj:PhysicsObject = PhysicsObject(newObj);
        return physicsObj;
    }
    
    /**
     * 通过 duplicateMovieClip 复制一个 PhysicsObject 实例
     * @param target MovieClip 目标父级
     * @param sourceInstanceName 源实例名称
     * @param newInstanceName 新实例名称
     * @param depth 新实例深度
     * @return 新复制的 PhysicsObject 实例
     */
    public static function duplicate(target:MovieClip, sourceInstanceName:String, newInstanceName:String, depth:Number):PhysicsObject {
        // 检查源实例是否存在
        if (target[sourceInstanceName] == undefined) {
            trace("源实例名 '" + sourceInstanceName + "' 在目标 MovieClip 中不存在。");
            return null;
        }
        
        var sourceObj:PhysicsObject = PhysicsObject(target[sourceInstanceName]);
        
        // 使用 attachMovie 创建新的实例
        var newObj:PhysicsObject = PhysicsObject.create(target, "PhysicsObjectSymbol", newInstanceName, depth);
        
        if (newObj == null) {
            trace("使用 attachMovie 创建 PhysicsObject 失败。");
            return null;
        }
        
        // 复制属性
        newObj.mass = sourceObj.mass;
        newObj.inverseMass = sourceObj.inverseMass;
        newObj.restitution = sourceObj.restitution;
        newObj.friction = sourceObj.friction;
        newObj.angle = sourceObj.angle;
        newObj.angularVelocity = sourceObj.angularVelocity;
        newObj.torque = sourceObj.torque;
        newObj.inertia = sourceObj.inertia;
        newObj.inverseInertia = sourceObj.inverseInertia;
        newObj.velocity = sourceObj.velocity.clone();
        newObj.acceleration = sourceObj.acceleration.clone();
        newObj.position = sourceObj.position.clone();
        newObj.previousPosition = sourceObj.previousPosition.clone();
        newObj.aabb = sourceObj.aabb.clone();
        
        // 设置位置
        newObj.setPosition(sourceObj.position);
        
        return newObj;
    }

    
    /**
     * 批量创建多个 PhysicsObject 实例
     * @param target MovieClip 目标父级
     * @param linkageId 链接标识符
     * @param count 创建的实例数量
     * @return 包含所有新创建的 PhysicsObject 实例的数组
     */
    public static function createBatch(target:MovieClip, linkageId:String, count:Number):Array {
        var objects:Array = [];
        for (var i:Number = 0; i < count; i++) {
            var instanceName:String = "physicsObj_" + target.getNextHighestDepth();
            var obj:PhysicsObject = PhysicsObject.create(target, linkageId, instanceName, target.getNextHighestDepth());
            objects.push(obj);
        }
        return objects;
    }
    
    /**
     * 通过 clone 创建一个全新的 PhysicsObject 实例
     * @param source PhysicsObject 源实例
     * @param target MovieClip 目标父级
     * @param newInstanceName 新实例名称
     * @param depth 新实例深度
     * @return 新创建的 PhysicsObject 实例
     */
    public static function clone(source:PhysicsObject, target:MovieClip, newInstanceName:String, depth:Number):PhysicsObject {
        var clonedObj:PhysicsObject = PhysicsObject.duplicate(target, source._name, newInstanceName, depth);
        
        if (clonedObj == null) {
            trace("克隆失败。");
            return null;
        }
        
        // 已在 duplicate 方法中复制了属性，无需再次复制
        return clonedObj;
    }

}
