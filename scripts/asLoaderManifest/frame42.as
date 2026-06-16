// [stage-wrap] frame42 折叠中间态：帧顶联合头(lint --fold-specific 子集,0 碰撞)
//   + staged 函数 + 内联调用。
import flash.filters.*;
import flash.geom.*;
import org.flashNight.arki.component.Effect.*;
import org.flashNight.arki.render.*;
import org.flashNight.arki.spatial.transform.*;
import org.flashNight.arki.weather.*;
import org.flashNight.naki.DataStructures.*;
import org.flashNight.neur.Event.*;
import org.flashNight.sara.util.*;

if (_root.__boot == undefined) _root.__boot = {};
_root.__boot.f42 = function() {
    #include "../展现/视觉系统/视觉系统_fs_打击数字池.as"
    #include "../展现/视觉系统/视觉系统_fs_画面效果控制生成.as"
    #include "../展现/视觉系统/视觉系统_fs_天气系统.as"
    #include "../展现/视觉系统/视觉系统_fs_绘图处理引擎.as"
    #include "../展现/视觉系统/视觉系统_fs_效果处理引擎.as"
    #include "../展现/视觉系统/视觉系统_fs_光照处理引擎.as"
    #include "../展现/视觉系统/视觉系统_fs_刀光处理引擎.as"
    #include "../展现/视觉系统/视觉系统_fs_显示列表引擎.as"
};
_root.__boot.f42();
