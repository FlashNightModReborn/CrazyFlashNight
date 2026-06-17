// [stage-wrap] frame38 折叠中间态：帧顶联合头(lint --fold-specific 子集,0 碰撞)
//   + staged 函数 + 内联调用。
import org.flashNight.arki.bullet.BulletComponent.Movement.*;
import org.flashNight.arki.bullet.BulletComponent.Movement.Util.*;
import org.flashNight.arki.bullet.BulletComponent.Shell.*;
import org.flashNight.neur.Event.*;

if (_root.__boot == undefined) _root.__boot = {};
_root.__boot.f38 = function() {
    #include "../逻辑/功能函数/功能函数_fs_兵器攻击检测.as"
    #include "../逻辑/功能函数/功能函数_fs_状态机用函数.as"
    #include "../逻辑/功能函数/功能函数_fs_导弹模板.as"
    #include "../逻辑/功能函数/功能函数_fs_新弹壳系统.as"
};
_root.__boot.f38();
