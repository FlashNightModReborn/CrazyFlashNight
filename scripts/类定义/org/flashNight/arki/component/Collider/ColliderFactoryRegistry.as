import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;

class org.flashNight.arki.component.Collider.ColliderFactoryRegistry {
    private static var factories:Object = {};

    public static var AABBFactory:String = "AABB";
    public static var CoverageAABBFactory:String = "CoverageAABB";
    public static var PolygonFactory:String = "Polygon";
    public static var RayFactory:String = "Ray";
    
    public static function registerFactory(type:String, factory:IColliderFactory):Void {
        factories[type] = factory;
    }

    public static function getFactory(type:String):IColliderFactory {
        return factories[type];
    }

    /**
        * 初始化所有碰撞器工厂
        * 在应用启动时调用此方法，以注册所有可用的碰撞器工厂
        */
    public static function init():Void {
        // 实例化并注册 AABBColliderFactory
        var aabbFactory:IColliderFactory = new AABBColliderFactory(30);
        ColliderFactoryRegistry.registerFactory(ColliderFactoryRegistry.AABBFactory, aabbFactory);

        // 实例化并注册 CoverageAABBColliderFactory
        var coverageAabbFactory:IColliderFactory = new CoverageAABBColliderFactory(30);
        ColliderFactoryRegistry.registerFactory(ColliderFactoryRegistry.CoverageAABBFactory, coverageAabbFactory);

        var polygonFactory:IColliderFactory = new PolygonColliderFactory(15);
        ColliderFactoryRegistry.registerFactory(ColliderFactoryRegistry.PolygonFactory, polygonFactory);

        // 实例化并注册 RayColliderFactory
        var rayFactory:IColliderFactory = new RayColliderFactory(15);
        ColliderFactoryRegistry.registerFactory(ColliderFactoryRegistry.RayFactory, rayFactory);
    }
}
