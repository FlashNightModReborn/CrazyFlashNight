using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Linq;
using CF7Launcher.Guardian.HitNumbers;
using CF7Launcher.Guardian.Hud;

namespace CF7Launcher.Tools.HitNumberVisualHarness
{
    internal sealed class ProductionRenderResult
    {
        internal string Id = string.Empty;
        internal string ScenarioId = string.Empty;
        internal string Title = string.Empty;
        internal string Mode = string.Empty;
        internal int WorldRowLimit;
        internal int Width;
        internal int Height;
        internal string RelativePath = string.Empty;
        internal int InputActive;
        internal int OffscreenCulled;
        internal int WorldRows;
        internal int WorldRowsOmitted;
        internal int WorldSegmentsOmitted;
        internal Rectangle PixelRegion;
        internal int SurfaceEdgeAlphaPixels;
    }

    internal sealed class VideoRenderResult
    {
        internal string Id = string.Empty;
        internal string Title = string.Empty;
        internal string RelativeVideoPath = string.Empty;
        internal string RelativeStoryboardPath = string.Empty;
        internal int Frames;
        internal int FramesPerSecond;
        internal bool Encoded;
        internal string Error = string.Empty;
    }

    /// <summary>
    /// 最终接线视觉门：只负责提供合成战斗底图，伤害行和数字全部直接调用
    /// Launcher 生产 HitNumberLayoutEngine / HitNumberScenePainter / HitNumberPainter。
    /// </summary>
    internal sealed class ProductionRenderer : IDisposable
    {
        private readonly string _outputRoot;
        private readonly HitNumberPainter _painter = new HitNumberPainter();
        private readonly HitNumberScenePainter _scenePainter = new HitNumberScenePainter();
        private readonly Font _labelFont = NativeHudFonts.CreateUiFont(
            18f,
            FontStyle.Bold,
            GraphicsUnit.Pixel);
        private readonly StringFormat _center = new StringFormat
        {
            Alignment = StringAlignment.Center,
            LineAlignment = StringAlignment.Center
        };
        private bool _disposed;

        internal ProductionRenderer(string outputRoot)
        {
            _outputRoot = outputRoot ?? throw new ArgumentNullException(nameof(outputRoot));
        }

        internal List<ProductionRenderResult> RenderAcceptanceSet(
            IReadOnlyList<VisualScenario> scenarios)
        {
            var byId = scenarios.ToDictionary(s => s.Id, StringComparer.Ordinal);
            var specs = new[]
            {
                new Spec("P01", "S01", "平衡默认 · 单发冲击", HitNumberDisplayMode.Balanced, 24, 1600, 900),
                new Spec("P02", "S05", "平衡默认 · 20 段/秒", HitNumberDisplayMode.Balanced, 24, 1600, 900),
                new Spec("P03", "S06", "平衡默认 · 60 段/秒", HitNumberDisplayMode.Balanced, 24, 1600, 900),
                new Spec("P04", "S08", "平衡默认 · 六目标归属", HitNumberDisplayMode.Balanced, 24, 1600, 900),
                new Spec("P05", "S15", "平衡默认 · 近邻交错归属", HitNumberDisplayMode.Balanced, 24, 1600, 900),
                new Spec("P06", "S10", "平衡默认 · 混合标识", HitNumberDisplayMode.Balanced, 24, 1600, 900),
                new Spec("P07", "S06", "总伤兼容 · 60 段/秒", HitNumberDisplayMode.Total, 24, 1600, 900),
                new Spec("P08", "S08", "总伤兼容 · 六目标", HitNumberDisplayMode.Total, 24, 1600, 900),
                new Spec("P09", "S03", "经典 Flash · 12 段联弹", HitNumberDisplayMode.Classic, 0, 1600, 900),
                new Spec("P10", "S06", "经典 Flash · 60 段/秒", HitNumberDisplayMode.Classic, 0, 1600, 900),
                new Spec("P11", "S03", "逐发矩阵 · 12 段联弹", HitNumberDisplayMode.Detail, 24, 1600, 900),
                new Spec("P12", "S06", "逐发矩阵 · 60 段/秒", HitNumberDisplayMode.Detail, 24, 1600, 900),
                new Spec("P13", "S09", "平衡默认 · 边缘与屏外", HitNumberDisplayMode.Balanced, 24, 1024, 576),
                new Spec("P14", "S14", "平衡默认 · 120 段无限制", HitNumberDisplayMode.Balanced, 0, 1600, 900),
                new Spec("P15", "S16", "平衡默认 · 连续交错归因", HitNumberDisplayMode.Balanced, 24, 2560, 1440),
                new Spec("P16", "S17", "逐发矩阵 · 五位数无碰撞", HitNumberDisplayMode.Detail, 24, 1600, 900),
                new Spec("P17", "S18", "总伤兼容 · 当前段色闪现", HitNumberDisplayMode.Total, 24, 1600, 900),
                new Spec("P18", "S19", "总伤兼容 · 回落主体色", HitNumberDisplayMode.Total, 24, 1600, 900),
                new Spec("P19", "S20", "平衡默认 · 同源 11 色板", HitNumberDisplayMode.Balanced, 24, 1600, 900),
                new Spec("P20", "S20", "逐发矩阵 · 同源 11 色板", HitNumberDisplayMode.Detail, 24, 1600, 900),
                new Spec("P21", "S20", "经典 Flash · 同源 11 色板", HitNumberDisplayMode.Classic, 0, 1600, 900),
                new Spec("P22", "S20", "总伤兼容 · 同源 11 色板", HitNumberDisplayMode.Total, 24, 1600, 900),
                new Spec("P23", "S21", "平衡默认 · 同源语义全集", HitNumberDisplayMode.Balanced, 24, 1600, 900),
                new Spec("P24", "S21", "逐发矩阵 · 同源语义全集", HitNumberDisplayMode.Detail, 24, 1600, 900),
                new Spec("P25", "S21", "经典 Flash · 同源语义全集", HitNumberDisplayMode.Classic, 0, 1600, 900),
                new Spec("P26", "S21", "总伤兼容 · 同源语义全集", HitNumberDisplayMode.Total, 24, 1600, 900)
            };

            var results = new List<ProductionRenderResult>(specs.Length);
            for (int i = 0; i < specs.Length; i++)
            {
                if (!byId.TryGetValue(specs[i].ScenarioId, out VisualScenario scenario))
                    throw new InvalidOperationException("missing scenario: " + specs[i].ScenarioId);
                results.Add(Render(specs[i], scenario));
            }
            return results;
        }

        internal string RenderContactSheet(IReadOnlyList<ProductionRenderResult> results)
        {
            const int columns = 3;
            const int cellWidth = 640;
            const int imageHeight = 360;
            const int labelHeight = 46;
            int rows = (results.Count + columns - 1) / columns;
            string filename = "production-review-sheet.png";
            string output = Path.Combine(_outputRoot, filename);
            using (var sheet = new Bitmap(
                columns * cellWidth,
                rows * (imageHeight + labelHeight),
                PixelFormat.Format32bppPArgb))
            using (Graphics graphics = Graphics.FromImage(sheet))
            {
                ConfigureGraphics(graphics);
                graphics.Clear(Color.FromArgb(8, 13, 24));
                for (int i = 0; i < results.Count; i++)
                {
                    int x = (i % columns) * cellWidth;
                    int y = (i / columns) * (imageHeight + labelHeight);
                    using (var source = new Bitmap(Path.Combine(_outputRoot, results[i].RelativePath)))
                    {
                        graphics.DrawImage(
                            source,
                            new Rectangle(x, y, cellWidth, imageHeight),
                            0,
                            0,
                            source.Width,
                            source.Height,
                            GraphicsUnit.Pixel);
                    }
                    using (var background = new SolidBrush(Color.FromArgb(238, 8, 14, 26)))
                    using (var text = new SolidBrush(Color.FromArgb(242, 226, 237, 251)))
                    {
                        graphics.FillRectangle(background, x, y + imageHeight, cellWidth, labelHeight);
                        graphics.DrawString(
                            results[i].Id + "  " + results[i].Title,
                            _labelFont,
                            text,
                            new RectangleF(x + 8, y + imageHeight + 3, cellWidth - 16, labelHeight - 6),
                            _center);
                    }
                }
                sheet.Save(output, ImageFormat.Png);
            }
            return filename;
        }

        internal List<VideoRenderResult> RenderAcceptanceVideos()
        {
            const double durationSeconds = 4.2;
            const int framesPerSecond = 30;
            return new List<VideoRenderResult>
            {
                RenderVideo(
                    "V01",
                    "平衡默认 · 持续 60 段/秒 · 冲击与目标锚定",
                    "balanced-impact-production",
                    ScenarioCatalog.BuildVideoStream(durationSeconds + 0.5),
                    durationSeconds,
                    framesPerSecond),
                RenderVideo(
                    "V02",
                    "平衡模式 · 近邻目标交叉攻击 · 固定来源归属",
                    "causal-attribution-production",
                    ScenarioCatalog.BuildCausalAttributionVideoStream(durationSeconds + 0.5),
                    durationSeconds,
                    framesPerSecond)
            };
        }

        private VideoRenderResult RenderVideo(
            string id,
            string title,
            string fileStem,
            IReadOnlyList<HitNumberSegment> segments,
            double durationSeconds,
            int framesPerSecond)
        {
            string frameRoot = Path.Combine(_outputRoot, ".frames-" + fileStem);
            Directory.CreateDirectory(frameRoot);
            int frameCount = (int)Math.Ceiling(durationSeconds * framesPerSecond);
            var storyboardFrames = new List<string>();
            int[] storyboardIndices =
            {
                framesPerSecond / 2,
                framesPerSecond * 3 / 2,
                framesPerSecond * 5 / 2,
                framesPerSecond * 7 / 2
            };
            for (int frameIndex = 0; frameIndex < frameCount; frameIndex++)
            {
                double now = frameIndex / (double)framesPerSecond;
                string framePath = Path.Combine(
                    frameRoot,
                    "frame-" + frameIndex.ToString("0000", CultureInfo.InvariantCulture) + ".png");
                RenderVideoFrame(
                    segments,
                    now,
                    framePath,
                    title);
                if (Array.IndexOf(storyboardIndices, frameIndex) >= 0)
                    storyboardFrames.Add(framePath);
            }

            string storyboardName = id + "-" + fileStem + "-storyboard.png";
            RenderVideoStoryboard(storyboardFrames, Path.Combine(_outputRoot, storyboardName));
            string videoName = id + "-" + fileStem + ".mp4";
            string videoPath = Path.Combine(_outputRoot, videoName);
            var result = new VideoRenderResult
            {
                Id = id,
                Title = title,
                RelativeVideoPath = videoName,
                RelativeStoryboardPath = storyboardName,
                Frames = frameCount,
                FramesPerSecond = framesPerSecond
            };
            result.Encoded = TryEncodeVideo(frameRoot, videoPath, framesPerSecond, out string error);
            result.Error = error;
            if (result.Encoded)
            {
                // frameRoot 是本轮唯一 outputRoot 下的固定子目录；成功编码后只删除中间帧。
                Directory.Delete(frameRoot, true);
            }
            return result;
        }

        private void RenderVideoFrame(
            IReadOnlyList<HitNumberSegment> segments,
            double nowSeconds,
            string output,
            string title)
        {
            const int width = 1600;
            const int height = 900;
            var viewport = new RectangleF(0, 0, width, height);
            HitNumberLayoutFrame worldFrame = HitNumberLayoutEngine.BuildFrame(
                segments,
                0,
                nowSeconds,
                HitNumberLayoutCandidate.BalancedSummary,
                HitNumberCamera.Identity,
                24,
                HitNumberLayoutEngine.DefaultLifetimeSeconds,
                false);
            HitNumberRenderRegion region = HitNumberRenderPlanner.Plan(
                worldFrame,
                width,
                height);

            using (var bitmap = new Bitmap(width, height, PixelFormat.Format32bppPArgb))
            using (Graphics graphics = Graphics.FromImage(bitmap))
            {
                ConfigureGraphics(graphics);
                DrawCombatBackground(graphics, viewport);
                DrawTargets(graphics, viewport, segments, nowSeconds);
                PaintTightProductionRegion(
                    graphics,
                    worldFrame,
                    HitNumberDisplayMode.Balanced,
                    region,
                    out _);
                DrawVideoStatus(
                    graphics,
                    viewport,
                    title,
                    nowSeconds);
                bitmap.Save(output, ImageFormat.Png);
            }
        }

        private void DrawVideoStatus(
            Graphics graphics,
            RectangleF viewport,
            string title,
            double nowSeconds)
        {
            string text = title + "  ·  t=" + nowSeconds.ToString("0.00", CultureInfo.InvariantCulture) +
                "s  ·  战斗层仅世界投影";
            var bounds = new RectangleF(18f, viewport.Height - 44f, viewport.Width - 36f, 32f);
            using (var background = new SolidBrush(Color.FromArgb(212, 8, 14, 26)))
            using (var foreground = new SolidBrush(Color.FromArgb(246, 226, 237, 251)))
            {
                graphics.FillRectangle(background, bounds);
                graphics.DrawString(text, _labelFont, foreground, bounds, _center);
            }
        }

        private static void RenderVideoStoryboard(List<string> framePaths, string output)
        {
            if (framePaths.Count == 0) return;
            const int width = 1600;
            const int cellWidth = 800;
            const int cellHeight = 450;
            int rows = (framePaths.Count + 1) / 2;
            using (var sheet = new Bitmap(width, rows * cellHeight, PixelFormat.Format32bppPArgb))
            using (Graphics graphics = Graphics.FromImage(sheet))
            {
                ConfigureGraphics(graphics);
                graphics.Clear(Color.FromArgb(10, 16, 29));
                for (int i = 0; i < framePaths.Count; i++)
                {
                    using var frame = new Bitmap(framePaths[i]);
                    graphics.DrawImage(
                        frame,
                        new Rectangle((i % 2) * cellWidth, (i / 2) * cellHeight, cellWidth, cellHeight),
                        0,
                        0,
                        frame.Width,
                        frame.Height,
                        GraphicsUnit.Pixel);
                }
                sheet.Save(output, ImageFormat.Png);
            }
        }

        private static bool TryEncodeVideo(
            string frameRoot,
            string output,
            int framesPerSecond,
            out string error)
        {
            error = string.Empty;
            try
            {
                var info = new ProcessStartInfo
                {
                    FileName = "ffmpeg",
                    UseShellExecute = false,
                    RedirectStandardError = true,
                    RedirectStandardOutput = true,
                    CreateNoWindow = true
                };
                info.ArgumentList.Add("-y");
                info.ArgumentList.Add("-hide_banner");
                info.ArgumentList.Add("-loglevel");
                info.ArgumentList.Add("error");
                info.ArgumentList.Add("-framerate");
                info.ArgumentList.Add(framesPerSecond.ToString(CultureInfo.InvariantCulture));
                info.ArgumentList.Add("-i");
                info.ArgumentList.Add(Path.Combine(frameRoot, "frame-%04d.png"));
                info.ArgumentList.Add("-c:v");
                info.ArgumentList.Add("libx264");
                info.ArgumentList.Add("-preset");
                info.ArgumentList.Add("medium");
                info.ArgumentList.Add("-crf");
                info.ArgumentList.Add("18");
                info.ArgumentList.Add("-pix_fmt");
                info.ArgumentList.Add("yuv420p");
                info.ArgumentList.Add("-movflags");
                info.ArgumentList.Add("+faststart");
                info.ArgumentList.Add(output);

                using Process process = Process.Start(info);
                if (process == null)
                {
                    error = "ffmpeg process did not start";
                    return false;
                }
                string stderr = process.StandardError.ReadToEnd();
                process.StandardOutput.ReadToEnd();
                if (!process.WaitForExit(120000))
                {
                    process.Kill(true);
                    error = "ffmpeg timed out";
                    return false;
                }
                if (process.ExitCode != 0)
                {
                    error = "ffmpeg exit=" + process.ExitCode + ": " + stderr;
                    return false;
                }
                if (!File.Exists(output) || new FileInfo(output).Length == 0)
                {
                    error = "ffmpeg produced no output";
                    return false;
                }
                return true;
            }
            catch (Exception ex)
            {
                error = ex.GetType().Name + ": " + ex.Message;
                return false;
            }
        }

        private ProductionRenderResult Render(Spec spec, VisualScenario scenario)
        {
            HitNumberLayoutFrame frame = BuildModeFrame(
                scenario.Segments,
                scenario.SnapshotSeconds,
                spec.Mode,
                spec.WorldRowLimit,
                true);
            string filename = spec.Id + "-production-" + spec.ScenarioId + "-" +
                spec.Width.ToString(CultureInfo.InvariantCulture) + "x" +
                spec.Height.ToString(CultureInfo.InvariantCulture) + ".png";
            string output = Path.Combine(_outputRoot, filename);
            var viewport = new RectangleF(0, 0, spec.Width, spec.Height);
            HitNumberRenderRegion region = HitNumberRenderPlanner.Plan(
                frame,
                spec.Width,
                spec.Height);
            int surfaceEdgeAlphaPixels;

            using (var bitmap = new Bitmap(spec.Width, spec.Height, PixelFormat.Format32bppPArgb))
            using (Graphics graphics = Graphics.FromImage(bitmap))
            {
                ConfigureGraphics(graphics);
                DrawCombatBackground(graphics, viewport);
                DrawTargets(graphics, viewport, scenario.Segments, scenario.SnapshotSeconds);
                PaintTightProductionRegion(
                    graphics,
                    frame,
                    spec.Mode,
                    region,
                    out surfaceEdgeAlphaPixels);
                DrawCaptureStatus(graphics, viewport, spec, frame);
                bitmap.Save(output, ImageFormat.Png);
            }

            return new ProductionRenderResult
            {
                Id = spec.Id,
                ScenarioId = spec.ScenarioId,
                Title = spec.Title,
                Mode = spec.Mode.ToString(),
                WorldRowLimit = spec.WorldRowLimit,
                Width = spec.Width,
                Height = spec.Height,
                RelativePath = filename,
                InputActive = frame.InputActiveSegmentCount,
                OffscreenCulled = frame.OffscreenCulledSegmentCount,
                WorldRows = frame.WorldRows.Count,
                WorldRowsOmitted = frame.WorldRowOmittedCount,
                WorldSegmentsOmitted = frame.WorldSegmentOmittedCount,
                PixelRegion = region.PixelBounds,
                SurfaceEdgeAlphaPixels = surfaceEdgeAlphaPixels
            };
        }

        private void PaintTightProductionRegion(
            Graphics destination,
            HitNumberLayoutFrame frame,
            HitNumberDisplayMode mode,
            HitNumberRenderRegion region,
            out int surfaceEdgeAlphaPixels)
        {
            surfaceEdgeAlphaPixels = 0;
            if (region.IsEmpty) return;

            using var overlay = new Bitmap(
                region.PixelBounds.Width,
                region.PixelBounds.Height,
                PixelFormat.Format32bppPArgb);
            using (Graphics graphics = Graphics.FromImage(overlay))
            {
                ConfigureGraphics(graphics);
                graphics.Clear(Color.Transparent);
                _scenePainter.DrawWorldRows(
                    graphics,
                    region.LocalViewport,
                    frame.WorldRows,
                    mode);
                _painter.Paint(
                    graphics,
                    frame.Items,
                    new HitNumberPaintContext(region.LocalViewport));
            }
            surfaceEdgeAlphaPixels = CountEdgeAlphaPixels(overlay, 2);
            destination.DrawImageUnscaled(
                overlay,
                region.PixelBounds.Left,
                region.PixelBounds.Top);
        }

        private static int CountEdgeAlphaPixels(Bitmap bitmap, int thickness)
        {
            int count = 0;
            for (int y = 0; y < bitmap.Height; y++)
            {
                for (int x = 0; x < bitmap.Width; x++)
                {
                    if (x >= thickness && x < bitmap.Width - thickness &&
                        y >= thickness && y < bitmap.Height - thickness)
                        continue;
                    if (bitmap.GetPixel(x, y).A != 0) count++;
                }
            }
            return count;
        }

        private static HitNumberLayoutFrame BuildModeFrame(
            IReadOnlyList<HitNumberSegment> segments,
            double nowSeconds,
            HitNumberDisplayMode mode,
            int worldRowLimit,
            bool diagnostics)
        {
            if (mode == HitNumberDisplayMode.Total)
            {
                var totals = new HitNumberTotalAccumulator();
                totals.AddRange(segments, 0, segments.Count);
                return HitNumberLayoutEngine.BuildTotalFrame(
                    totals.Snapshot(nowSeconds),
                    nowSeconds,
                    HitNumberCamera.Identity,
                    worldRowLimit);
            }

            HitNumberLayoutCandidate candidate = mode == HitNumberDisplayMode.Detail
                ? HitNumberLayoutCandidate.FixedBurstStack
                : mode == HitNumberDisplayMode.Classic
                    ? HitNumberLayoutCandidate.ClassicScatter
                    : HitNumberLayoutCandidate.BalancedSummary;
            double lifetime = mode == HitNumberDisplayMode.Classic
                ? HitNumberLayoutEngine.ClassicLifetimeSeconds
                : HitNumberLayoutEngine.DefaultLifetimeSeconds;
            return HitNumberLayoutEngine.BuildFrame(
                segments,
                0,
                nowSeconds,
                candidate,
                HitNumberCamera.Identity,
                worldRowLimit,
                lifetime,
                diagnostics);
        }

        private void DrawCaptureStatus(
            Graphics graphics,
            RectangleF viewport,
            Spec spec,
            HitNumberLayoutFrame frame)
        {
            string text = spec.Title + "  ·  世界行 " +
                frame.WorldRows.Count.ToString(CultureInfo.InvariantCulture) +
                (frame.WorldRowOmittedCount > 0
                    ? "（省略 " + frame.WorldRowOmittedCount.ToString(CultureInfo.InvariantCulture) + "）"
                    : string.Empty);
            var bounds = new RectangleF(18f, viewport.Height - 44f, viewport.Width - 36f, 32f);
            using var background = new SolidBrush(Color.FromArgb(212, 8, 14, 26));
            using var foreground = new SolidBrush(Color.FromArgb(246, 226, 237, 251));
            graphics.FillRectangle(background, bounds);
            graphics.DrawString(text, _labelFont, foreground, bounds, _center);
        }

        private static void ConfigureGraphics(Graphics graphics)
        {
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;
            graphics.CompositingQuality = CompositingQuality.HighQuality;
        }

        private static void DrawCombatBackground(Graphics graphics, RectangleF viewport)
        {
            using (var gradient = new LinearGradientBrush(
                viewport,
                Color.FromArgb(35, 40, 55),
                Color.FromArgb(13, 20, 31),
                LinearGradientMode.Vertical))
                graphics.FillRectangle(gradient, viewport);
            float sx = viewport.Width / HitNumberLayoutEngine.StageWidth;
            float sy = viewport.Height / HitNumberLayoutEngine.StageHeight;
            using (var distant = new SolidBrush(Color.FromArgb(82, 92, 119, 145)))
            using (var floor = new SolidBrush(Color.FromArgb(225, 40, 49, 63)))
            using (var rim = new Pen(Color.FromArgb(150, 111, 145, 175), Math.Max(1f, 2f * sx)))
            {
                graphics.FillEllipse(distant, 90 * sx, 75 * sy, 190 * sx, 145 * sy);
                graphics.FillEllipse(distant, 710 * sx, 55 * sy, 230 * sx, 170 * sy);
                graphics.FillRectangle(floor, 0, 455 * sy, viewport.Width, 121 * sy);
                graphics.DrawLine(rim, 0, 455 * sy, viewport.Width, 455 * sy);
                graphics.FillRectangle(floor, 70 * sx, 375 * sy, 255 * sx, 24 * sy);
                graphics.FillRectangle(floor, 695 * sx, 345 * sy, 255 * sx, 24 * sy);
            }
        }

        private static void DrawTargets(
            Graphics graphics,
            RectangleF viewport,
            IReadOnlyList<HitNumberSegment> segments,
            double nowSeconds)
        {
            var seen = new HashSet<string>(StringComparer.Ordinal);
            float sx = viewport.Width / HitNumberLayoutEngine.StageWidth;
            float sy = viewport.Height / HitNumberLayoutEngine.StageHeight;
            for (int i = 0; i < segments.Count; i++)
            {
                HitNumberSegment segment = segments[i];
                if (segment.ArrivalSeconds > nowSeconds ||
                    nowSeconds - segment.ArrivalSeconds >= HitNumberLayoutEngine.DefaultLifetimeSeconds ||
                    !seen.Add(segment.TargetId))
                {
                    continue;
                }
                float x = segment.TargetX * sx;
                float y = segment.TargetY * sy;
                float radius = 27f * sx;
                using (var body = new SolidBrush(Color.FromArgb(225, 56, 62, 77)))
                using (var rim = new Pen(Color.FromArgb(225, 236, 104, 78), Math.Max(1f, 3f * sx)))
                using (var eye = new SolidBrush(Color.FromArgb(245, 255, 193, 84)))
                {
                    graphics.FillEllipse(body, x - radius, y - radius, radius * 2f, radius * 2f);
                    graphics.DrawEllipse(rim, x - radius, y - radius, radius * 2f, radius * 2f);
                    graphics.FillEllipse(eye, x - radius * 0.3f, y - radius * 0.18f,
                        radius * 0.18f, radius * 0.18f);
                    graphics.FillEllipse(eye, x + radius * 0.12f, y - radius * 0.18f,
                        radius * 0.18f, radius * 0.18f);
                }
            }
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            _painter.Dispose();
            _scenePainter.Dispose();
            _labelFont.Dispose();
            _center.Dispose();
        }

        private readonly struct Spec
        {
            internal Spec(
                string id,
                string scenarioId,
                string title,
                HitNumberDisplayMode mode,
                int worldRowLimit,
                int width,
                int height)
            {
                Id = id;
                ScenarioId = scenarioId;
                Title = title;
                Mode = mode;
                WorldRowLimit = worldRowLimit;
                Width = width;
                Height = height;
            }

            internal string Id { get; }
            internal string ScenarioId { get; }
            internal string Title { get; }
            internal HitNumberDisplayMode Mode { get; }
            internal int WorldRowLimit { get; }
            internal int Width { get; }
            internal int Height { get; }
        }
    }
}
