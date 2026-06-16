// [stage-wrap] frame3 折叠中间态：帧顶联合头(lint --fold-specific 子集,0 碰撞)
//   + staged 函数 + 内联调用。
import org.flashNight.arki.bullet.BulletComponent.Shell.*;
import org.flashNight.arki.bullet.Factory.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.component.Effect.*;
import org.flashNight.arki.corpse.*;
import org.flashNight.arki.item.*;
import org.flashNight.arki.key.*;
import org.flashNight.arki.render.*;
import org.flashNight.arki.scene.*;
import org.flashNight.arki.spatial.move.*;
import org.flashNight.arki.spatial.transform.*;
import org.flashNight.arki.task.*;
import org.flashNight.arki.unit.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.weather.*;
import org.flashNight.gesh.arguments.*;
import org.flashNight.gesh.json.LoadJson.*;
import org.flashNight.gesh.object.*;
import org.flashNight.gesh.path.*;
import org.flashNight.gesh.xml.LoadXml.*;
import org.flashNight.naki.DataStructures.*;
import org.flashNight.neur.Controller.*;
import org.flashNight.neur.Event.*;
import org.flashNight.neur.InputCommand.*;
import org.flashNight.neur.PerformanceOptimizer.*;
import org.flashNight.neur.ScheduleTimer.*;
import org.flashNight.neur.Server.*;
import org.flashNight.sara.*;

if (_root.__boot == undefined) _root.__boot = {};
_root.__boot.f3 = function() {
    打印加载内容("加载通信代码……");    
        
    #include "../通信/通信_fs_lsy_XML数据解析.as"    
    #include "../通信/通信_fs_本地服务器.as"    
    #include "../通信/通信_fs_帧计时器.as"    
    #include "../通信/通信_lsy_原版存档系统.as"    
    #include "../通信/通信_lsy_存档迁移.as"    
    #include "../通信/通信_fs_bootstrap.as"    
    #include "../通信/通信_鸡蛋_XML与JSON解析.as"    
    #include "../通信/通信_鸡蛋_任务系统.as"    
    #include "../通信/通信_aka_Agent联动.as"
};
_root.__boot.f3();
