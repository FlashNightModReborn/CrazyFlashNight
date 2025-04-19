import org.flashNight.arki.render.*;
import org.flashNight.arki.spatial.transform.*;
import org.flashNight.sara.util.*;
import org.flashNight.neur.Event.*;

//----------------------------------------------------
// 刀光系统：只做“刀口采集与提交”，并调用 TrailRenderer 进行拖影管理
//----------------------------------------------------
_root.刀光系统 = {};


//-----------------------------------------------------------------------
// 针对独立刀对象的绘制
//-----------------------------------------------------------------------
_root.刀光系统.刀引用绘制刀光 = function(target:MovieClip, mc:MovieClip, style:String)
{
    BladeMotionTrailsRenderer.processBladeTrail(target, mc, style)
};



//-----------------------------------------------------------------------
// 清理内存，转调 TrailRenderer
//-----------------------------------------------------------------------
_root.刀光系统.清理内存 = function(forceCleanAll:Boolean, maxInactiveFrames:Number) {
    return TrailRenderer.getInstance().cleanMemory(forceCleanAll, maxInactiveFrames);
};

var trailRenderer:TrailRenderer = TrailRenderer.getInstance();
EventBus.getInstance().subscribe("SceneChanged", trailRenderer.cleanMemory, trailRenderer); 
EventBus.getInstance().subscribe("SceneChanged", VectorAfterimageRenderer.instance.onSceneChanged
, VectorAfterimageRenderer.instance); 
var trailStyleManager:TrailStyleManager = TrailStyleManager.getInstance();
trailStyleManager.loadStyles();