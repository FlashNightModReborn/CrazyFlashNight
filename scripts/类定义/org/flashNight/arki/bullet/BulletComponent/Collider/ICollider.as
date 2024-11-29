interface org.flashNight.arki.bullet.BulletComponent.Collider.ICollider {
    // Gets the Axis-Aligned Bounding Box (AABB) of the collider
    function getAABB():AABB;
    
    // Checks if this collider intersects with another collider
    function intersects(other:ICollider):Boolean;
    
    // Gets detailed collision information with another collider
    function getCollisionInfo(other:ICollider):CollisionInfo;
    
    // Transforms the collider by a given transformation matrix or function
    function transform(transformFunc:Function):Void;
}
