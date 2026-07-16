// CF7:ME — NativeHud 启动期预热（C# 5）
// 把 GDI+ Font handle / ClearType glyph cache 等"首帧冷启动"成本
// 推进 ThreadPool 后台线程，让 Flash 启动等待窗口（~4-5s）替玩家吸收。
// 不在玩家可见路径上做任何 UI 操作。

using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Threading;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// P2-1 perf：NativeHud 首帧冷启动预热。
    ///
    /// 触发的冷路径：
    ///   1. System.Drawing 初始化（gdiplus.dll 加载、进程级 token）
    ///   2. Microsoft YaHei / Segoe UI Symbol 字体 family 解析 + .ttc 加载
    ///   3. ClearType 字形栅格化进 GDI 进程缓存（widget 首帧用到的所有 glyph）
    ///   4. RightContextWidget / ComboWidget 静态 cctor（21+5 brush + pen + StringFormat）
    ///   5. RightContextWidget / ComboWidget 实例 scaled font 集合
    ///
    /// 调用时机：Program.cs 在 widget 实例化、PerfDecisionEngine 装配之后立刻调用，
    /// 后台 ThreadPool 跑；与 SFX preload / MapCatalog async 并行，全部藏在 Flash 启动等待里。
    ///
    /// GDI+ Graphics 跨线程：每个后台线程只创建自己的 Bitmap+Graphics，不触碰 widget 实例的
    /// 共享 _composedBitmap；widget 上的 PrewarmGdi 内部新建一次性 Bitmap，安全。
    /// </summary>
    public static class NativeHudPrewarm
    {
        /// <summary>
        /// 后台异步预热。立即返回，不阻塞主线程。
        /// PrewarmGdi 是静态方法（只接静态资源），不需要 widget 实例参数。
        /// </summary>
        /// <param name="mapCatalog">保留参数以维持调用边界；地图资源改由 hotspot 切换时按工作集预热</param>
        public static void RunAsync(MapHudDataCatalog mapCatalog)
        {
            ThreadPool.QueueUserWorkItem(delegate(object state)
            {
                long t0 = System.Diagnostics.Stopwatch.GetTimestamp();
                try
                {
                    // 1) 强制触发 gdiplus.dll 加载 + System.Drawing 静态 cctor
                    using (Bitmap warm = new Bitmap(2, 2, PixelFormat.Format32bppPArgb))
                    using (Graphics g = Graphics.FromImage(warm))
                    {
                        g.SmoothingMode = SmoothingMode.AntiAlias;
                        g.TextRenderingHint = TextRenderingHint.ClearTypeGridFit;
                        g.Clear(Color.Transparent);
                    }

                    // 2) widget 静态资源 + base font + 字形栅格化 cache（不触碰 widget 实例字段）
                    RightContextWidget.PrewarmGdi();
                    ComboWidget.PrewarmGdi();

                    PerfTrace.Mark("nativeHud.prewarm_gdi_done");

                    // 地图 WebP 不在启动期全量解码。MapHudWidget / RightContextWidget 收到 mh 后，
                    // 只把当前 outline 的资源放入 24 MiB decoded LRU。
                    PerfTrace.Mark("nativeHud.prewarm_map_assets_deferred", mapCatalog == null ? "no_catalog" : "workset_on_hotspot");
                }
                catch (Exception ex)
                {
                    LogManager.Log("[NativeHudPrewarm] failed: " + ex.Message);
                    PerfTrace.Mark("nativeHud.prewarm_failed", ex.Message);
                    return;
                }
                long t1 = System.Diagnostics.Stopwatch.GetTimestamp();
                long elapsedMs = (t1 - t0) * 1000L / System.Diagnostics.Stopwatch.Frequency;
                LogManager.Log("[NativeHudPrewarm] complete in " + elapsedMs + " ms (background)");
                PerfTrace.Mark("nativeHud.prewarm_complete", elapsedMs + "ms");
            });
        }
    }
}
