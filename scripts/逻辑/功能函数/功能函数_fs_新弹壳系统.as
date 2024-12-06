import org.flashNight.sara.util.*;
import org.flashNight.naki.RandomNumberEngine.*;
import org.flashNight.gesh.xml.LoadXml.*;
import org.flashNight.neur.Server.*; 
import org.flashNight.gesh.object.*;


// 使用对象池重构后的弹壳系统
_root.弹壳系统 = {};

_root.弹壳系统.弹壳映射表 = {}; // 与原逻辑相同，用于存储不同弹壳类型的配置数据
_root.弹壳系统.弹壳池映射 = {}; // 存放每种弹壳对应的对象池

// 当前弹壳总数与弹壳上限由外部控制，保持原有设计
_root.弹壳系统.当前弹壳总数 = 0;
_root.弹壳系统.弹壳总数上限 = 100; // 实际上在帧计时器中进行控制，这里仅作示例

// 弹壳物理运动函数，与原逻辑基本一致
_root.弹壳系统.弹壳物理运动 = function(弹壳) {   
    if (弹壳._y - 弹壳.Z轴坐标 < -5) {
        弹壳.垂直速度 += 4;
        弹壳._x += 弹壳.水平速度;
        弹壳._y += 弹壳.垂直速度;
        弹壳._rotation += 弹壳.旋转速度;
    } else {
        弹壳.垂直速度 = 弹壳.垂直速度 / -2 - _root.随机整数(0, 5);
        弹壳._xscale = Math.max(Math.sin(弹壳._rotation * Math.PI / 180), 0.5) * 弹壳._xscale; // 设置最小缩放值为50%
        if (弹壳.垂直速度 < -10) {
            弹壳.水平速度 += _root.随机浮点偏移(4);
            弹壳.旋转速度 = 弹壳.旋转速度 * 1.5 + _root.随机浮点(0, 25);
            弹壳._x += 弹壳.水平速度;
            弹壳._y = 弹壳.Z轴坐标 - 6;
            弹壳._rotation += 弹壳.旋转速度;
        } else {
            // 弹壳落地，添加回收任务
            _root.add2map3(弹壳, 2);
            _root.帧计时器.移除任务(弹壳.任务ID);
            _root.帧计时器.添加或更新任务(弹壳, "回收", function(弹壳) {
                // 回收时使用对象池的机制
                弹壳.recycle(); 
                // 减少当前弹壳总数
                --_root.弹壳系统.当前弹壳总数;
            }, 1, 弹壳);
        }
    }
};

// 物理模拟函数，与原逻辑相同，在发射后调用
_root.弹壳系统.弹壳物理模拟 = function(弹壳) {
    var engine = LinearCongruentialEngine.getInstance();
    弹壳.水平速度 = engine.randomFloatOffset(4);
    弹壳.垂直速度 = engine.randomFloat(-8, -20);
    弹壳.旋转速度 = engine.randomFloat(-10, 10);
    弹壳.Z轴坐标 = 弹壳._y + 100;
    弹壳.swapDepths(弹壳.Z轴坐标);

    弹壳.任务ID = _root.帧计时器.添加生命周期任务(弹壳, "运动", this.弹壳物理运动, 33, 弹壳);
};

// 初始化弹壳池函数
// 在重新加载 _root.gameworld 时需要调用该函数以保证世界变化后的引用一致
_root.弹壳系统.初始化弹壳池 = function() {
    var 游戏世界 = _root.gameworld;
    if (!游戏世界) return; // 确保游戏世界存在

    // 对象池的创建、重置、释放函数构造器，用于为不同弹壳类型生成专属 ObjectPool
    function createBulletPoolFuncs(bulletType:String):Object {
        // createFunc：在初始化原型时调用，用于创建该类型的原型弹壳（只调用一次），之后 clone。
        var createFunc:Function = function(parentClip:MovieClip):MovieClip {
            // 在此函数中创建原型弹壳
            var 游戏世界 = _root.gameworld;
            var 世界效果 = 游戏世界.效果;
            var prototypeBullet = 世界效果.attachMovie(bulletType, "prototype_" + bulletType, 世界效果.getNextHighestDepth());
            prototypeBullet._visible = false;
            return prototypeBullet;
        };

        // resetFunc：在 getObject() 时调用，对象从池中取出前对其进行重置，确保是一个干净状态
        var resetFunc:Function = function():Void {
            // 将基本属性重置到可用状态
            // 此处只做基础处理，如确保可见、无销毁标记，其余逻辑在发射时单独设置
            this._visible = true;
            this.__isDestroyed = false; // 确保对象是健康的
            // 清除一些可能残留的运动数据
            // 例如:
            // this._xscale = 100;
            // this._yscale = 100;
            // 在发射弹壳处会再次对位置和缩放进行设定，因此这里只需最小化状态清理
        };

        // releaseFunc：在 releaseObject() 回收对象到池中时调用
        var releaseFunc:Function = function():Void {
            // 对象回收时处理，将其设置为不可见，防止在屏幕上残留
            this._visible = false;
            // 不需要再手动放入池子，ObjectPool 已处理
            // 此处不需要移除任务，因为在逻辑中回收前已经移除任务或由上层控制
        };

        return {createFunc:createFunc, resetFunc:resetFunc, releaseFunc:releaseFunc};
    }

    // 重置弹壳系统状态
    this.当前弹壳总数 = 0;
    this.弹壳池映射 = {}; // 清空之前旧世界的池映射
    游戏世界.可用弹壳池 = {}; // 不再使用数组池，这里仅保留引用以兼容原逻辑（可能外部有用）

    // 按照映射表创建对应的对象池
    // 注意：由于懒加载，实际对象不会在此刻创建（isLazyLoaded=true，无需预加载）
    var 世界效果 = 游戏世界.效果;
    for (var bulletName in this.弹壳映射表) {
        var 弹壳信息 = this.弹壳映射表[bulletName];
        var 弹壳种类:String = 弹壳信息.弹壳;

        // 创建对象池函数集
        var funcs = createBulletPoolFuncs(弹壳种类);

        // 创建对象池
        var pool = new org.flashNight.sara.util.ObjectPool(
            funcs.createFunc,   // createFunc
            funcs.resetFunc,    // resetFunc
            funcs.releaseFunc,  // releaseFunc
            世界效果,            // parentClip
            30,                 // maxPoolSize（根据需要可调）
            0,                  // preloadSize，懒加载无需预加载
            true,               // isLazyLoaded必须为true以支持世界切换后的性能优化
            true,               // isPrototypeEnabled使用原型模式
            []                  // prototypeInitArgs
        );

        // 存储对象池
        this.弹壳池映射[弹壳种类] = pool;
        游戏世界.可用弹壳池[弹壳种类] = pool; // 兼容旧逻辑，外部若依赖此引用可用
    }

    // 设置可用弹壳池为不可枚举以减少外部干扰
    _global.ASSetPropFlags(游戏世界, ["可用弹壳池"], 1, true);
};

// 发射弹壳函数，与原逻辑基本一致
_root.弹壳系统.发射弹壳 = function(子弹类型, myX, myY, xscale, 必然触发) {
    // 确保有当前弹壳上限判断逻辑
    if (this.当前弹壳总数 <= this.弹壳总数上限 || _root.成功率(this.弹壳总数上限) || 必然触发) {
        // 如果游戏世界未初始化或池未初始化，尝试初始化
        var 游戏世界 = _root.gameworld;

        var 弹壳信息 = this.弹壳映射表[子弹类型];
        if (!弹壳信息) return; // 没有该子弹类型信息时直接返回

        var 弹壳种类 = 弹壳信息.弹壳;
        if (!弹壳种类) return;

        // 从池中获取对象
        var pool = this.弹壳池映射[弹壳种类];
        if (!pool) {
            // 万一未创建成功或中途出问题，再次尝试初始化池
            this.初始化弹壳池();
            pool = this.弹壳池映射[弹壳种类];
            if (!pool) return; // 仍无则放弃
        }

        var 弹壳:MovieClip = pool.getObject(); 
        // 根据逻辑在获取对象后再设置位置、缩放、可见性
        var scale = xscale / 100;
        var ascale = Math.abs(scale);
        myX -= scale * 弹壳信息.myX;
        myY += ascale * 弹壳信息.myY;

        弹壳._x = myX;
        弹壳._y = myY;
        弹壳._visible = true;
        弹壳._xscale = xscale;
        弹壳._yscale = ascale * 100;

        // 为兼容回收逻辑，可以存储子弹类型在对象上（如果后续需要）
        弹壳.弹壳种类 = 弹壳种类;

        // 启动物理模拟
        this.弹壳物理模拟(弹壳);

        ++this.当前弹壳总数;
    }
};


// 使用数据加载回调，与原逻辑相同
BulletsCasesLoader.getInstance().loadBulletsCases(
    function(data:Object):Void {
        var server = ServerManager.getInstance();
        server.sendServerMessage("BulletsCasesLoader：bullets_cases.xml 加载成功！");

        var bulletNodes:Array = data.bullet;
        for (var i:Number = 0; i < bulletNodes.length; i++) {
            var bulletInfo:Object = {};
            var child_Nodes:Array = bulletNodes[i];
            bulletInfo.弹壳 = child_Nodes.casing != undefined ? child_Nodes.casing : "步枪弹壳";
            bulletInfo.myX = child_Nodes.xOffset != undefined ? Number(child_Nodes.xOffset) : 0;
            bulletInfo.myY = child_Nodes.yOffset != undefined ? Number(child_Nodes.yOffset) : 0;
            bulletInfo.模拟方式 = child_Nodes.simulationMethod != undefined ? child_Nodes.simulationMethod : "标准";
            
            _root.弹壳系统.弹壳映射表[child_Nodes.name] = bulletInfo;
        }

        server.sendServerMessage("BulletsCasesInfo: 配置完毕");
    },
    function():Void {
        trace("BulletsCasesLoader：bullets_cases.xml 加载失败！");
    }
);
