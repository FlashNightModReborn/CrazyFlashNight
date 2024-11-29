import org.flashNight.arki.bullet.BulletComponent.Collider.*;

interface org.flashNight.arki.bullet.BulletComponent.Collider.ICollider {
    // Checks if this collider collides with another collider
    function checkCollision(other:ICollider):CollisionResult;

    // Handles collision response based on the collision result
    function handleCollision(result:CollisionResult):Void;
}
