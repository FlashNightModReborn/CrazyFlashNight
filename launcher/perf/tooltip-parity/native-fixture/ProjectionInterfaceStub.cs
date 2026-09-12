// 编译缝占位：ITooltipInspectionProjection 目前定义在
// launcher/src/Guardian/Hud/TooltipInspectionController.cs 内，该文件的
// 依赖链（INativeInteractionTooltipSurface → NativeInteractionSupport →
// IPanelHudCompanion/Tasks.NativeInteractionTask）会把宿主侧整组类型拖进
// 本 fixture 闭包。这里只放接口签名占位——被测对象是 100% 生产 widget 代码，
// 接口本身不进渲染路径。若生产接口增删成员，本 fixture 编译立即报错（天然漂移检测）。
// 提案（见 parity-compare notes）：parity-input 把该接口拆到独立 .cs。
namespace CF7Launcher.Guardian.Hud
{
    internal interface ITooltipInspectionProjection
    {
        void SetInspectionState(string state, int remainingMs);
    }
}
