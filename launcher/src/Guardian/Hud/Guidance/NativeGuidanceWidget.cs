using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Windows.Forms;

namespace CF7Launcher.Guardian.Hud.Guidance
{
    /// <summary>Passive scene hints pass all input through; tutorial buttons own only their bounds.</summary>
    public sealed class NativeGuidanceWidget : INativeHudWidget, INativeHudResumable, IDisposable
    {
        private readonly Control _anchor;
        private readonly FlashCoordinateMapper _mapper;
        private readonly GuidanceCatalog _catalog;
        private GuidanceCatalog.Guide _guide;
        private IReadOnlyDictionary<string,string> _keys;
        private string _request, _scene;
        private int _revision, _page, _imageEpoch, _pressed = -1;
        private float _opacity;
        private bool _suppressed, _disposed;
        private Bitmap _image;
        public event EventHandler BoundsOrVisibilityChanged;
        public event EventHandler RepaintRequested;
        public event EventHandler AnimationStateChanged { add { } remove { } }
        public Action<string,string,int> CloseRequested;
        internal Action<string,int> ImageRequested;
        public bool WantsAnimationTick => false;
        public void Tick(int deltaMs) { }
        public bool Visible => !_disposed && !_suppressed && _guide != null && _opacity > 0;
        internal string CurrentRequest => _request;
        internal string CurrentScene => _scene;
        internal int CurrentRevision => _revision;
        internal int ImageEpoch => _imageEpoch;
        internal int CurrentPage => _page;
        internal bool HasImage => _image != null;
        internal string CurrentText => _guide == null ? "" : GuidanceCatalog.Bind(_guide.Pages[_page].Text, _keys);
        internal string CurrentImagePath => _guide?.Pages[_page].Image;
        internal bool KnowsGuide(string id) => _catalog.TryGet(id, out _);
        internal bool UsesWebHelp(string id) => _catalog.TryGet(id, out var guide) && guide.WebHelp;
        internal string GuideTitle(string id) => _catalog.TryGet(id, out var guide) ? guide.Title : "";
        public NativeGuidanceWidget(Control anchor, GuidanceCatalog catalog)
        {
            _anchor = anchor ?? throw new ArgumentNullException(nameof(anchor));
            _catalog = catalog ?? throw new ArgumentNullException(nameof(catalog));
            _mapper = new FlashCoordinateMapper(anchor, 1024f, 576f);
            _anchor.Resize += AnchorChanged;
            _anchor.LocationChanged += AnchorChanged;
        }
        private void AnchorChanged(object sender, EventArgs e) => Changed();
        private RectangleF LogicalBounds => _guide?.Tutorial == true
            ? NativeGuidancePainter.CardBounds
            : _guide == null ? RectangleF.Empty : NativeGuidancePainter.SceneBounds(_guide.Pages[_page]);
        private Rectangle ToScreen(RectangleF r)
        {
            _mapper.CalcViewport(out float x, out float y, out float w, out float h);
            Point origin = _anchor.PointToScreen(Point.Empty);
            return Rectangle.Round(new RectangleF(origin.X + x + r.X * w / 1024f,
                origin.Y + y + r.Y * h / 576f, r.Width * w / 1024f, r.Height * h / 576f));
        }
        public Rectangle ScreenBounds => ToScreen(LogicalBounds);
        internal Rectangle NextButtonBounds => Button(0);
        internal Rectangle CloseButtonBounds => Button(1);
        public void Show(string request, string scene, int revision, string guideId, float opacity, IReadOnlyDictionary<string,string> keys)
        {
            if (_disposed || !_catalog.TryGet(guideId, out var guide)) return;
            bool fresh = _request != request || _scene != scene || _guide != guide;
            _guide = guide; _request = request; _scene = scene; _revision = revision;
            _keys = new Dictionary<string,string>(keys); _opacity = Math.Clamp(opacity, 0, 1);
            if (fresh || _opacity <= 0) _pressed = -1;
            if (fresh) { _page = 0; ClearImage(); RequestImage(); }
            Changed();
        }
        private void RequestImage()
        {
            _imageEpoch++;
            if (!string.IsNullOrEmpty(CurrentImagePath)) ImageRequested?.Invoke(CurrentImagePath, _imageEpoch);
        }
        internal bool SetImage(string request, string scene, int imageEpoch, Bitmap image)
        {
            // Opacity/key revisions do not change the page asset; the asset epoch does.
            if (_disposed || _guide == null || _request != request || _scene != scene || imageEpoch != _imageEpoch || image == null) return false;
            Bitmap owned = (Bitmap)image.Clone();
            ClearImage(); _image = owned;
            RepaintRequested?.Invoke(this, EventArgs.Empty);
            return true;
        }
        private void ClearImage() { _image?.Dispose(); _image = null; }
        public void Clear()
        {
            _guide = null; _request = _scene = null; _pressed = -1; _imageEpoch++;
            ClearImage(); Changed();
        }
        public void SetHostSuppressed(bool suppressed)
        {
            if (_suppressed == suppressed) return;
            _suppressed = suppressed; _pressed = -1; Changed();
        }
        private void Changed()
        {
            BoundsOrVisibilityChanged?.Invoke(this, EventArgs.Empty);
            RepaintRequested?.Invoke(this, EventArgs.Empty);
        }
        private Rectangle Button(int index) => ToScreen(NativeGuidancePainter.Button(index));
        public bool TryHitTest(Point p) => Visible && _guide.Tutorial && (Button(0).Contains(p) || Button(1).Contains(p));
        public void OnMouseEvent(MouseEventArgs e, MouseEventKind kind)
        {
            if (kind == MouseEventKind.Cancel) { _pressed = -1; return; }
            if (!Visible || !_guide.Tutorial || e.Button != MouseButtons.Left) return;
            int hit = Button(0).Contains(e.Location) ? 0 : Button(1).Contains(e.Location) ? 1 : -1;
            if (kind == MouseEventKind.Down) _pressed = hit;
            if (kind != MouseEventKind.Up) return;
            int pressed = _pressed; _pressed = -1;
            if (hit < 0 || hit != pressed) return;
            if (hit == 1 || _page + 1 >= _guide.Pages.Count) CloseRequested?.Invoke(_request, _scene, _revision);
            else { _page++; ClearImage(); RequestImage(); Changed(); }
        }
        public void Paint(Graphics g, float dpr, Point hudOrigin)
        {
            if (!Visible) return;
            _mapper.CalcViewport(out float x, out float y, out float w, out float h);
            Point origin = _anchor.PointToScreen(Point.Empty);
            var state = g.Save();
            try
            {
                g.TranslateTransform(origin.X + x - hudOrigin.X, origin.Y + y - hudOrigin.Y);
                g.ScaleTransform(w / 1024f, h / 576f);
                NativeGuidancePainter.Paint(g, _guide, _page, _keys, _catalog.KeyLabels, _image, _opacity);
            }
            finally { g.Restore(state); }
        }
        public void Dispose()
        {
            if (_disposed) return;
            Clear(); _disposed = true;
            _anchor.Resize -= AnchorChanged; _anchor.LocationChanged -= AnchorChanged;
            ImageRequested = null; CloseRequested = null;
        }
    }
    /// <summary>Shared contain geometry for dialogue illustrations and guide cards.</summary>
    internal static class GuidanceImageLayout
    {
        internal static RectangleF Contain(Size source, RectangleF bounds)
        {
            if (source.Width <= 0 || source.Height <= 0 || bounds.Width <= 0 || bounds.Height <= 0) return RectangleF.Empty;
            float ratio = Math.Min(bounds.Width/source.Width, bounds.Height/source.Height);
            float w=source.Width*ratio, h=source.Height*ratio;
            return new RectangleF(bounds.X+(bounds.Width-w)/2, bounds.Y+(bounds.Height-h)/2, w, h);
        }
        internal static void DrawContained(Graphics g, Bitmap image, RectangleF bounds, float opacity)
        {
            RectangleF dest = Contain(image.Size, bounds);
            using var attr = new ImageAttributes();
            var matrix = new ColorMatrix { Matrix33 = Math.Clamp(opacity, 0, 1) };
            attr.SetColorMatrix(matrix);
            g.DrawImage(image, Rectangle.Round(dest), 0, 0, image.Width, image.Height, GraphicsUnit.Pixel, attr);
        }
    }
}
