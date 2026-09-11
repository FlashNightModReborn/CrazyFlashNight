using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using CF7Launcher.Tasks;

namespace CF7Launcher.Guardian.Hud
{
    public partial class RightContextWidget : IStageReturnPresenter, ITaskDeliveryPresenter
    {
        private const int ReturnPageSize = 5;
        private const int DestinationActionWidthBase = 64;
        private const int DestinationConfirmWidthBase = 60;
        private const int DestinationReturnWidthBase = 52;
        private int CurrentStatusHeightBase => ShowsDailyChoices || (PaintsStageDecision && HasInlineReturnChoices)
            ? RightHudLayout.TaskDestinationHeightBase : RightHudLayout.StatusSlotHeightBase;
        private bool _returnMenuOpen;
        private int _returnMenuPage;
        private string _selectedReturnId = "";
        private string _returnSelectionToken = "";
        private string _returnChoiceRun = "";
        private string _downReturnSignature;
        private readonly string _npcPortraitDirectory;
        private readonly Dictionary<string, Bitmap> _returnPortraits = new Dictionary<string, Bitmap>(StringComparer.Ordinal);
        public event Action<string, int, string, string> ReturnRequested;

        private bool HasInlineReturnChoices => CanOfferStageDelivery(_stageOutcomeState)
            && _stageOutcomeState.ReturnOptions != null
            && _stageOutcomeState.ReturnOptions.Choices.Count > 0;
        private bool InlineReturnReady => HasInlineReturnChoices && _stageOutcomeState.ReturnOptions.Status == "ready";

        private TaskDestinationChoices _deliveryOptions;
        private string _deliveryScope = "";
        private bool _deliveryProtocolSeen;
        public event Action<string, string, string> DeliveryRequested;
        private bool UsesStageDestination => ShouldPresentStageOutcome(_stageOutcomeState);
        private bool HasDailyChoices => !UsesStageDestination && _deliveryOptions?.Choices.Count > 0
            && _runtimeMapMode != RuntimeMapMode.Combat;
        private bool ShowsDailyChoices => PaintsActionableNotice && CurrentNoticeMode == NoticeMode.TaskDone && HasDailyChoices;
        private TaskDestinationChoices DestinationOptions => UsesStageDestination ? _stageOutcomeState.ReturnOptions : _deliveryOptions;
        private bool HasDestinationChoices => UsesStageDestination ? HasInlineReturnChoices : HasDailyChoices;
        private bool DestinationReady => HasDestinationChoices && DestinationOptions.Status == "ready";
        private bool PaintsDestination => PaintsStageDecision || ShowsDailyChoices;

        public void ApplyDeliveryState(string scope, TaskDestinationChoices options)
        {
            if (MarshalToUi(() => ApplyDeliveryState(scope, options))) return;
            _deliveryProtocolSeen = true;
            _deliveryScope = scope;
            _deliveryOptions = options;
            if (UsesStageDestination) return;
            AdoptReturnChoices();
            _hover = NoHit();
            ClearPointerDown();
            RebuildNoticeText();
            FireBounds();
        }
        public void ResetDeliveryState()
        {
            if (MarshalToUi(ResetDeliveryState)) return;
            _deliveryScope = "";
            _deliveryOptions = null;
            if (UsesStageDestination) return;
            AdoptReturnChoices();
            ClearPointerDown();
            RebuildNoticeText();
            FireBounds();
        }

        private TaskDestinationChoices.Choice SelectedReturnChoice
        {
            get
            {
                if (!HasDestinationChoices) return null;
                foreach (var choice in DestinationOptions.Choices)
                    if (choice.Id == _selectedReturnId) return choice;
                return null;
            }
        }

        private void AdoptReturnChoices()
        {
            string token = DestinationOptions?.Token ?? "";
            string run = UsesStageDestination ? "stage:" + _stageOutcomeState.RunId : "daily:" + _deliveryScope;
            bool keepOpen = _returnMenuOpen && run == _returnChoiceRun
                && token == _returnSelectionToken && DestinationReady;
            if (run != _returnChoiceRun)
            {
                _returnChoiceRun = run;
                _selectedReturnId = "";
            }
            _returnSelectionToken = token;
            if (HasDestinationChoices && SelectedReturnChoice == null)
                _selectedReturnId = DestinationOptions.Choices[0].Id;
            if (HasDestinationChoices)
                foreach (var choice in DestinationOptions.Choices) GetReturnPortrait(choice.NpcName);
            // 同一组选项的状态刷新保留展开与页码；ApplyState 仍会作废正在按下的旧手势。
            _returnMenuOpen = keepOpen;
            _returnMenuPage = keepOpen
                ? Math.Min(_returnMenuPage, (DestinationOptions.Choices.Count - 1) / ReturnPageSize)
                : 0;
        }

        private Rectangle ReturnFieldRect(Rectangle slot, float scale)
        {
            int pad = WidgetScaler.Px(4, scale);
            // 状态归入任务信息；两种入口按实际动作数量分配文字空间。
            int controlsLeft = UsesStageDestination
                ? StageActionRect(slot, scale, 0).Left : DailyDeliveryActionRect(slot, scale).Left;
            return new Rectangle(slot.Left + pad, slot.Top + pad,
                Math.Max(1, controlsLeft - slot.Left - pad * 2), slot.Height - pad * 2);
        }

        private Rectangle ReturnMenuRect(Rectangle slot, float scale)
        {
            if (!_returnMenuOpen || !DestinationReady || !PaintsDestination) return Rectangle.Empty;
            int count = Math.Min(ReturnPageSize, DestinationOptions.Choices.Count - _returnMenuPage * ReturnPageSize);
            int height = WidgetScaler.Px(count * 38 + 24, scale);
            return new Rectangle(slot.Left, slot.Bottom, slot.Width, height);
        }

        private Rectangle ReturnMenuItemRect(Rectangle menu, float scale, int pageIndex)
        {
            int top = menu.Top + WidgetScaler.Px(pageIndex * 38, scale);
            return new Rectangle(menu.Left, top, menu.Width, WidgetScaler.Px((pageIndex + 1) * 38, scale) - WidgetScaler.Px(pageIndex * 38, scale));
        }

        private Rectangle IncludeReturnMenu(Rectangle bounds)
        {
            Rectangle viewport = RightHudLayout.GetViewportRect(_anchor, _mapper);
            float scale = RightHudLayout.ScaleForViewport(viewport);
            Rectangle slot = RightHudLayout.GetStatusSlotRect(_anchor, _mapper, LayoutMapMode, ShowStatusSlot, CurrentStatusHeightBase);
            Rectangle menu = ReturnMenuRect(slot, scale);
            return menu.IsEmpty ? bounds : Rectangle.Union(bounds, menu);
        }

        private void PaintReturnField(Graphics g, Rectangle slot, float scale)
        {
            Rectangle field = ReturnFieldRect(slot, scale);
            PaintDestinationControl(g, field, scale, _hover.Kind == HitKind.ReturnToggle,
                _down.Kind == HitKind.ReturnToggle, _returnMenuOpen);
            var choice = SelectedReturnChoice;
            int portraitSize = WidgetScaler.Px(24, scale);
            Rectangle portrait = new Rectangle(field.Left + WidgetScaler.Px(3, scale), field.Top + (field.Height - portraitSize) / 2, portraitSize, portraitSize);
            PaintReturnPortrait(g, portrait, choice?.NpcName, scale);
            int textLeft = portrait.Right + WidgetScaler.Px(4, scale);
            int arrowWidth = WidgetScaler.Px(12, scale);
            Rectangle label = new Rectangle(textLeft, field.Top + WidgetScaler.Px(1, scale),
                Math.Max(1, field.Right - textLeft - arrowWidth), WidgetScaler.Px(15, scale));
            using (var brush = new SolidBrush(DestinationReady ? NativeHudTheme.TextPrimary : NativeHudTheme.TextDisabled))
            {
                g.DrawString(choice?.TaskName ?? "选择任务", _fontNoticeJuke11, brush, label, FMT_NEAR_NOWRAP_ELLIPSIS);
                g.DrawString("▾", _fontNoticeJuke11, brush,
                    new Rectangle(label.Right, field.Top, arrowWidth, field.Height), FMT_CENTER);
            }
            label.Y = field.Top + WidgetScaler.Px(16, scale);
            label.Height = field.Bottom - label.Y - WidgetScaler.Px(1, scale);
            string locationName = choice?.LocationName ?? "";
            Rectangle status = Rectangle.Empty;
            if (ShowsDailyChoices)
            {
                // 地点先读，状态紧随其后；长地点省略时仍为可交付提示留足空间。
                int statusWidth = Math.Min(WidgetScaler.Px(43, scale), label.Width);
                int gap = locationName.Length > 0 ? WidgetScaler.Px(4, scale) : 0;
                int locationWidth = (int)Math.Ceiling(g.MeasureString(locationName,
                    _fontDestinationDetail10, PointF.Empty, FMT_NEAR_NOWRAP_ELLIPSIS).Width);
                label.Width = Math.Min(locationWidth, Math.Max(0, label.Width - statusWidth - gap));
                status = new Rectangle(label.Right + gap, label.Y, statusWidth, label.Height);
            }
            using var locationBrush = new SolidBrush(DestinationReady ? NativeHudTheme.TextSecondary : NativeHudTheme.TextDisabled);
            if (label.Width > 0)
                g.DrawString(locationName, _fontDestinationDetail10, locationBrush, label, FMT_NEAR_NOWRAP_ELLIPSIS);
            if (!status.IsEmpty)
            {
                using var statusBrush = new SolidBrush(DestinationReady ? NativeHudTheme.Warning : NativeHudTheme.TextDisabled);
                g.DrawString("! 可交付", _fontDestinationDetail10, statusBrush, status, FMT_NEAR_NOWRAP_ELLIPSIS);
            }
        }

        private static void PaintDestinationControl(Graphics g, Rectangle bounds, float scale, bool hover, bool pressed, bool primary)
        {
            // 外栏保留角饰；内部控件仅一层细框，避免小字号周围堆叠 bevel 和角线。
            Color fill = pressed ? NativeHudTheme.ButtonPressed : hover ? NativeHudTheme.ButtonHover
                : primary ? NativeHudTheme.ButtonActive : NativeHudTheme.ButtonFill;
            Color frame = hover || pressed || primary ? NativeHudTheme.FrameNormal : NativeHudTheme.FrameMuted;
            SmoothingMode previous = g.SmoothingMode;
            g.SmoothingMode = SmoothingMode.None;
            using (var brush = new SolidBrush(fill)) g.FillRectangle(brush, bounds);
            using (var pen = new Pen(frame, NativeHudTheme.StrokePx(scale)))
                g.DrawRectangle(pen, bounds.X, bounds.Y, Math.Max(0, bounds.Width - 1), Math.Max(0, bounds.Height - 1));
            g.SmoothingMode = previous;
        }

        private void PaintReturnMenu(Graphics g, Rectangle slot, float scale)
        {
            Rectangle menu = ReturnMenuRect(slot, scale);
            if (menu.IsEmpty) return;
            NativeHudTheme.DrawPanel(g, menu, scale, NativeHudTheme.PanelFillDense, NativeHudTheme.TextSecondary, true);
            var choices = DestinationOptions.Choices;
            int count = Math.Min(ReturnPageSize, choices.Count - _returnMenuPage * ReturnPageSize);
            for (int i = 0; i < count; i++)
            {
                int index = _returnMenuPage * ReturnPageSize + i;
                var choice = choices[index];
                Rectangle row = ReturnMenuItemRect(menu, scale, i);
                bool selected = choice.Id == _selectedReturnId;
                bool hover = _hover.Kind == HitKind.ReturnOption && _hover.Index == index;
                Rectangle content = Rectangle.Inflate(row, -WidgetScaler.Px(4, scale), 0);
                using (var fill = new SolidBrush(hover ? NativeHudTheme.ButtonHover
                    : selected ? NativeHudTheme.ButtonActive : NativeHudTheme.PanelFillDense))
                    g.FillRectangle(fill, content);
                int avatarSize = WidgetScaler.Px(28, scale);
                var portrait = new Rectangle(content.Left + WidgetScaler.Px(3, scale), row.Top + (row.Height - avatarSize) / 2, avatarSize, avatarSize);
                PaintReturnPortrait(g, portrait, choice.NpcName, scale);
                int textLeft = portrait.Right + WidgetScaler.Px(4, scale);
                Rectangle label = new Rectangle(textLeft, row.Top + WidgetScaler.Px(3, scale),
                    content.Right - textLeft - WidgetScaler.Px(18, scale), WidgetScaler.Px(16, scale));
                using (var brush = new SolidBrush(NativeHudTheme.TextPrimary))
                    g.DrawString(choice.TaskName, _fontNoticeJuke11, brush, label, FMT_NEAR_NOWRAP_ELLIPSIS);
                label.Y += WidgetScaler.Px(16, scale);
                using (var brush = new SolidBrush(NativeHudTheme.TextSecondary))
                    g.DrawString(choice.Label, _fontDestinationDetail10, brush, label, FMT_NEAR_NOWRAP_ELLIPSIS);
                if (selected)
                {
                    int x = content.Right - WidgetScaler.Px(13, scale), y = row.Top + row.Height / 2;
                    using var check = new Pen(NativeHudTheme.Cyan, NativeHudTheme.StrokePx(scale));
                    g.DrawLines(check, new[] { new Point(x, y), new Point(x + WidgetScaler.Px(3, scale), y + WidgetScaler.Px(3, scale)),
                        new Point(x + WidgetScaler.Px(8, scale), y - WidgetScaler.Px(3, scale)) });
                }
                using (var separator = new Pen(NativeHudTheme.FrameMuted, NativeHudTheme.StrokePx(scale)))
                    g.DrawLine(separator, content.Left, row.Bottom - 1, content.Right - 1, row.Bottom - 1);
            }
            Rectangle footer = new Rectangle(menu.Left, menu.Top + WidgetScaler.Px(count * 38, scale), menu.Width, WidgetScaler.Px(24, scale));
            int third = footer.Width / 3;
            using (var brush = new SolidBrush(NativeHudTheme.TextSecondary))
            {
                g.DrawString(_returnMenuPage > 0 ? "上一页" : "", _fontDestinationDetail10, brush,
                    new Rectangle(footer.Left, footer.Top, third, footer.Height), FMT_CENTER);
                g.DrawString("刷新交付", _fontDestinationDetail10, brush,
                    new Rectangle(footer.Left + third, footer.Top, third, footer.Height), FMT_CENTER);
                g.DrawString((_returnMenuPage + 1) * ReturnPageSize < choices.Count ? "下一页" : "", _fontDestinationDetail10, brush,
                    new Rectangle(footer.Left + third * 2, footer.Top, footer.Width - third * 2, footer.Height), FMT_CENTER);
            }
        }

        private HitInfo HitReturnMenu(Point pt, Rectangle viewport, float scale)
        {
            if (!PaintsDestination) return NoHit();
            Rectangle slot = RightHudLayout.GetStatusSlotRect(_anchor, _mapper, LayoutMapMode, ShowStatusSlot, CurrentStatusHeightBase);
            if (DestinationReady && ReturnFieldRect(slot, scale).Contains(pt)) return Hit(HitKind.ReturnToggle, 0);
            if (ShowsDailyChoices && DestinationReady && DailyDeliveryActionRect(slot, scale).Contains(pt)) return Hit(HitKind.DeliveryAction, 0);
            Rectangle menu = ReturnMenuRect(slot, scale);
            if (!menu.Contains(pt)) return NoHit();
            int count = Math.Min(ReturnPageSize, DestinationOptions.Choices.Count - _returnMenuPage * ReturnPageSize);
            for (int i = 0; i < count; i++)
                if (ReturnMenuItemRect(menu, scale, i).Contains(pt)) return Hit(HitKind.ReturnOption, _returnMenuPage * ReturnPageSize + i);
            int col = Math.Min(2, (pt.X - menu.Left) * 3 / menu.Width);
            return col == 1 ? Hit(HitKind.ReturnRefresh, 0) : Hit(HitKind.ReturnPage, col == 0 ? -1 : 1);
        }

        private bool DispatchReturnHit(HitInfo hit)
        {
            if (!DestinationReady) return false;
            switch (hit.Kind)
            {
                case HitKind.ReturnToggle: _returnMenuOpen = !_returnMenuOpen; break;
                case HitKind.ReturnOption:
                    if (!_returnMenuOpen || hit.Index < 0 || hit.Index >= DestinationOptions.Choices.Count) return true;
                    _selectedReturnId = DestinationOptions.Choices[hit.Index].Id;
                    _returnMenuOpen = false;
                    break;
                case HitKind.ReturnPage:
                    _returnMenuPage = Math.Max(0, Math.Min((DestinationOptions.Choices.Count - 1) / ReturnPageSize, _returnMenuPage + hit.Index));
                    break;
                case HitKind.ReturnRefresh:
                    _returnMenuOpen = false;
                    if (UsesStageDestination) IntentRequested?.Invoke("refresh_return", _stageOutcomeState.RunId, _stageOutcomeState.Revision);
                    else DeliveryRequested?.Invoke("refresh", DestinationOptions.Token, "");
                    break;
                case HitKind.DeliveryAction:
                    if (!ShowsDailyChoices || SelectedReturnChoice == null) return true;
                    _returnMenuOpen = false;
                    DeliveryRequested?.Invoke("navigate", DestinationOptions.Token, SelectedReturnChoice.Id);
                    break;
                default: return false;
            }
            FireBounds();
            return true;
        }

        private void CloseReturnMenu()
        {
            if (!_returnMenuOpen) return;
            _returnMenuOpen = false;
            FireBounds();
        }

        private Bitmap GetReturnPortrait(string npcName)
        {
            if (string.IsNullOrEmpty(npcName) || string.IsNullOrEmpty(_npcPortraitDirectory)
                || npcName.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0) return null;
            if (_returnPortraits.TryGetValue(npcName, out Bitmap cached)) return cached;
            if (_returnPortraits.Count >= 128) return null;
            Bitmap bitmap = null;
            try
            {
                string path = Path.Combine(_npcPortraitDirectory, npcName + ".png");
                if (File.Exists(path))
                {
                    using var stream = File.OpenRead(path);
                    using var source = Image.FromStream(stream);
                    if (source.Width > 0 && source.Height > 0 && source.Width <= 2048 && source.Height <= 2048)
                    {
                        bitmap = new Bitmap(128, 128);
                        using var graphics = Graphics.FromImage(bitmap);
                        graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
                        graphics.DrawImage(source, new Rectangle(0, 0, 128, 128));
                    }
                }
            }
            catch { bitmap?.Dispose(); bitmap = null; }
            _returnPortraits[npcName] = bitmap;
            return bitmap;
        }

        private void PaintReturnPortrait(Graphics g, Rectangle bounds, string npcName, float scale)
        {
            Bitmap portrait = GetReturnPortrait(npcName);
            if (portrait != null)
            {
                var previous = g.InterpolationMode;
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.DrawImage(portrait, bounds);
                g.InterpolationMode = previous;
            }
            else
            {
                NativeHudTheme.DrawButton(g, bounds, scale, false, false, false, false);
                using var brush = new SolidBrush(NativeHudTheme.TextSecondary);
                g.DrawString(string.IsNullOrEmpty(npcName) ? "?" : npcName.Substring(0, 1), _fontNoticeJuke11, brush, bounds, FMT_CENTER);
            }
        }

        private void DisposeReturnPortraits()
        {
            foreach (Bitmap bitmap in _returnPortraits.Values) bitmap?.Dispose();
            _returnPortraits.Clear();
        }

        private string ReturnGestureSignature(HitInfo hit)
        {
            if (hit.Kind != HitKind.ReturnToggle && hit.Kind != HitKind.ReturnOption && hit.Kind != HitKind.DeliveryAction
                && hit.Kind != HitKind.ReturnPage && hit.Kind != HitKind.ReturnRefresh) return null;
            string binding = UsesStageDestination ? "stage:" + _stageOutcomeState.RunId + ":" + _stageOutcomeState.Revision : "daily:" + _deliveryScope;
            return DestinationReady && PaintsDestination ? binding + ":" + _returnSelectionToken + ":"
                + _returnMenuPage + ":" + _returnMenuOpen + ":" + _selectedReturnId : "unavailable";
        }

        private Rectangle DailyDeliveryActionRect(Rectangle slot, float scale)
        {
            int pad = WidgetScaler.Px(STAGE_ACTION_INSET_BASE, scale), width = WidgetScaler.Px(DestinationActionWidthBase, scale);
            return new Rectangle(slot.Right - pad - width, slot.Top + pad, width, slot.Height - pad * 2);
        }
        private void PaintDailyDelivery(Graphics g, Rectangle slot, float scale)
        {
            NativeHudTheme.DrawPanel(g, slot, scale, NativeHudTheme.PanelFillDense, NativeHudTheme.Cyan, true);
            PaintReturnField(g, slot, scale);
            Rectangle action = DailyDeliveryActionRect(slot, scale);
            PaintDestinationControl(g, action, scale, _hover.Kind == HitKind.DeliveryAction,
                _down.Kind == HitKind.DeliveryAction, DestinationReady);
            using var brush = new SolidBrush(DestinationReady ? NativeHudTheme.TextPrimary : NativeHudTheme.TextDisabled);
            g.DrawString(DestinationReady ? "前往交付" : "正在前往", _fontNoticeJuke11, brush, action, FMT_CENTER);
        }
        internal Rectangle DailyDeliveryActionForTest => DailyDeliveryActionRect(
            RightHudLayout.GetStatusSlotRect(_anchor, _mapper, LayoutMapMode, ShowStatusSlot, CurrentStatusHeightBase),
            RightHudLayout.ScaleForViewport(RightHudLayout.GetViewportRect(_anchor, _mapper)));

        internal string SelectedReturnIdForTest => SelectedReturnChoice?.Id;
        internal bool ReturnMenuOpenForTest => _returnMenuOpen;
        internal Rectangle ReturnFieldForTest => ReturnFieldRect(
            RightHudLayout.GetStatusSlotRect(_anchor, _mapper, LayoutMapMode, ShowStatusSlot, CurrentStatusHeightBase),
            RightHudLayout.ScaleForViewport(RightHudLayout.GetViewportRect(_anchor, _mapper)));
        internal Rectangle ReturnMenuForTest => ReturnMenuRect(
            RightHudLayout.GetStatusSlotRect(_anchor, _mapper, LayoutMapMode, ShowStatusSlot, CurrentStatusHeightBase),
            RightHudLayout.ScaleForViewport(RightHudLayout.GetViewportRect(_anchor, _mapper)));
    }
}
