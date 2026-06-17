// [stage-wrap] frame40 折叠中间态：帧顶联合头(lint --fold-specific 子集,0 碰撞)
//   + staged 函数 + 内联调用。
import org.flashNight.arki.bullet.BulletComponent.Attributes.*;
import org.flashNight.arki.bullet.BulletComponent.Chain.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.bullet.BulletComponent.Init.*;
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;
import org.flashNight.arki.bullet.BulletComponent.Movement.*;
import org.flashNight.arki.bullet.BulletComponent.Queue.*;
import org.flashNight.arki.bullet.BulletComponent.Shell.*;
import org.flashNight.arki.bullet.BulletComponent.Type.*;
import org.flashNight.arki.bullet.BulletComponent.Utils.*;
import org.flashNight.arki.bullet.Factory.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.Effect.*;
import org.flashNight.arki.component.StatHandler.*;
import org.flashNight.arki.render.*;
import org.flashNight.arki.spatial.move.*;
import org.flashNight.arki.spatial.transform.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.aven.Proxy.*;
import org.flashNight.gesh.depth.*;
import org.flashNight.gesh.object.*;
import org.flashNight.naki.Sort.*;
import org.flashNight.neur.Event.*;
import org.flashNight.neur.ScheduleTimer.*;
import org.flashNight.sara.util.*;

if (_root.__boot == undefined) _root.__boot = {};
_root.__boot.f40 = function() {
    #include "../逻辑/战斗系统/战斗系统_aka_特殊闪避计算函数.as"
    #include "../逻辑/战斗系统/战斗系统_fs_lsy_aka_重写子弹生成逻辑.as"
    #include "../逻辑/战斗系统/战斗系统_fs_冲击力系统.as"
    #include "../逻辑/战斗系统/战斗系统_fs_减伤系统.as"
    #include "../逻辑/战斗系统/战斗系统_fs_联弹管理.as"
    #include "../逻辑/战斗系统/战斗系统_lsy_消弹判定.as"
};
_root.__boot.f40();
