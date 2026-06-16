
// 刀光系统相关初始化
// 所有刀光处理现在直接调用 BladeMotionTrailsRenderer.processBladeTrail
// 内存清理由 TrailRenderer 实例自动管理

var trailRenderer:TrailRenderer = TrailRenderer.getInstance();
EventBus.getInstance().subscribe("SceneChanged", trailRenderer.cleanMemory, trailRenderer); 
EventBus.getInstance().subscribe("SceneChanged", VectorAfterimageRenderer.instance.onSceneChanged
, VectorAfterimageRenderer.instance); 
var trailStyleManager:TrailStyleManager = TrailStyleManager.getInstance();
trailStyleManager.loadStyles();