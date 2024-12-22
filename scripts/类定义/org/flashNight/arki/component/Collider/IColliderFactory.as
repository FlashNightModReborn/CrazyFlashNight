import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;

interface org.flashNight.arki.component.Collider.IColliderFactory {
    function createFromTransparentBullet(bullet:Object):ICollider;
    function createFromBullet(bullet:MovieClip, detectionArea:MovieClip):ICollider;
    function createFromUnitArea(unit:MovieClip):ICollider;
}
