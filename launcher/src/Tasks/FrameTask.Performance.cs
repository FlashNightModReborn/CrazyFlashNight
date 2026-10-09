using CF7Launcher.Guardian.WorldCompositor;

namespace CF7Launcher.Tasks
{
    public partial class FrameTask
    {
        private NativeVisualBudget _nativeVisualBudget;

        internal void ConfigureNativeVisualBudget(int effectLevel)
        {
            NativeVisualBudget budget=NativeVisualBudget.FromEffectLevel(effectLevel);
            lock(_combatFxLock) {
                _nativeVisualBudget=budget;
                _combatFxEngine?.ConfigureVisualBudget(budget);
            }
        }
    }
}
