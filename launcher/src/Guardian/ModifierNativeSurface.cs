using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Media;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.Tasks;
using Newtonsoft.Json.Linq;
using SkiaSharp;

namespace CF7Launcher.Guardian
{
    internal sealed class ModifierNativeSurface : Form
    {
        private sealed class ItemEntry
        {
            internal long Id;
            internal string Name;
            internal string DisplayName;
            internal string Icon;
            internal string Type;
            internal string Use;
        }

        private sealed class UnitEntry
        {
            internal long Id;
            internal string Name;
            internal string SpriteName;
            internal string Key;
            internal long Level;
            internal bool Hostile;
        }

        private static readonly Color KeyColor = Color.FromArgb(1, 2, 3);
        private static readonly Color Gold = Color.FromArgb(255, 204, 0);
        private static readonly Color SoftGold = Color.FromArgb(216, 195, 138);
        private static readonly Color UnitText = Color.FromArgb(241, 220, 168);
        private static readonly Color UnitMeta = Color.FromArgb(200, 184, 142);
        private static readonly Color HostileText = Color.FromArgb(255, 176, 160);
        private static readonly Color ErrorText = Color.FromArgb(255, 111, 97);
        private static readonly Color OkText = Color.FromArgb(184, 233, 134);
        private static readonly Color PendingText = Color.FromArgb(255, 204, 0);

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        private static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);

        [DllImport("user32.dll")]
        private static extern bool ReleaseCapture();

        [DllImport("user32.dll")]
        private static extern IntPtr SendMessage(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam);

        private readonly Form _owner;
        private readonly string _webRoot;
        private readonly ModifierTask _task;
        private readonly object _callGate = new object();
        private readonly Dictionary<string, Action<JObject>> _calls = new Dictionary<string, Action<JObject>>(StringComparer.Ordinal);
        private readonly Dictionary<string, Image> _backgrounds = new Dictionary<string, Image>(StringComparer.Ordinal);
        private readonly Dictionary<string, Image> _icons = new Dictionary<string, Image>(StringComparer.Ordinal);
        private readonly Dictionary<string, Image> _unitFrames = new Dictionary<string, Image>(StringComparer.Ordinal);
        private readonly HashSet<string> _unitFrameRequests = new HashSet<string>(StringComparer.Ordinal);
        private readonly TextBox _itemQuery;
        private readonly TextBox _itemQuantity;
        private readonly TextBox _taskId;
        private readonly TextBox _unitLevel;
        private readonly TextBox _unitCount;
        private readonly Timer _armTimer;
        private readonly SoundPlayer _tabSound;
        private readonly Font _textFont;
        private readonly Font _smallFont;
        private readonly Font _tinyFont;
        private readonly Font _statusFont;
        private readonly StringFormat _clip;
        private readonly StringFormat _ellipsis;
        private JObject _iconManifest;
        private JObject _portraitManifest;
        private bool _portraitManifestLoaded;
        private List<ItemEntry> _items;
        private List<UnitEntry> _units;
        private JObject _snapshot;
        private Image _unitFrame;
        private string _unitFrameSprite;
        private string _activeTab = "economy";
        private string _token = "";
        private string _instance = "";
        private string _status = "";
        private string _statusTone = "neutral";
        private string _armedAction;
        private string _pressedAction;
        private string _unresolvedToken;
        private string _unresolvedOperation;
        private int _requestSequence;
        private int _operationSequence;
        private long _revision;
        private int _itemPage = 1;
        private int _itemTotal;
        private int _itemPageSize = 64;
        private int _unitPage = 1;
        private int _unitTotal;
        private int _unitPageSize = 8;
        private int _selectedItem = -1;
        private int _selectedUnit = -1;
        private int _hoverItem = -1;
        private int _hoverUnit = -1;
        private int _hoverAction;
        private int _sessionGeneration;
        private bool _prepared;
        private bool _active;
        private bool _disposed;
        private bool _writeBusy;
        private bool _itemLoading;
        private bool _unitLoading;
        private bool _closeRaised;
        private DateTime _armedUntil;
        private Point _tooltipPoint;
        private Point _pressPoint;
        private bool _trackingLeave;

        internal ModifierNativeSurface(Form owner, string webRoot, string profileRoot, ModifierTask task)
        {
            _owner = owner ?? throw new ArgumentNullException(nameof(owner));
            _webRoot = webRoot ?? throw new ArgumentNullException(nameof(webRoot));
            _task = task ?? throw new ArgumentNullException(nameof(task));
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            AutoScaleMode = AutoScaleMode.None;
            BackColor = KeyColor;
            TransparencyKey = KeyColor;
            DoubleBuffered = true;
            KeyPreview = true;
            base.Text = "CF7 Modifier";
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint, true);

            _textFont = CreateFont(10f, FontStyle.Regular);
            _smallFont = CreateFont(8.5f, FontStyle.Regular);
            _tinyFont = CreateFont(7.5f, FontStyle.Regular);
            _statusFont = CreateFont(8f, FontStyle.Regular);
            _clip = new StringFormat(StringFormatFlags.NoWrap) { Trimming = StringTrimming.EllipsisCharacter };
            _ellipsis = new StringFormat(StringFormatFlags.NoWrap) { Trimming = StringTrimming.EllipsisCharacter };
            _armTimer = new Timer { Interval = 3000 };
            _armTimer.Tick += OnArmTimer;
            _tabSound = null;
            try
            {
                string sound = Path.Combine(_webRoot, "assets", "modifier", "tab-click.wav");
                if (File.Exists(sound)) _tabSound = new SoundPlayer(sound);
            }
            catch { _tabSound = null; }

            _itemQuery = CreateInput(false);
            _itemQuery.MaxLength = 64;
            _itemQuery.KeyDown += OnItemQueryKeyDown;
            _itemQuantity = CreateInput(true);
            _itemQuantity.MaxLength = 9;
            _itemQuantity.Text = "1";
            _taskId = CreateInput(true);
            _taskId.MaxLength = 3;
            _taskId.Text = "1";
            _unitLevel = CreateInput(true);
            _unitLevel.MaxLength = 4;
            _unitLevel.Text = "1";
            _unitCount = CreateInput(true);
            _unitCount.MaxLength = 3;
            _unitCount.Text = "1";
            Controls.Add(_itemQuery);
            Controls.Add(_itemQuantity);
            Controls.Add(_taskId);
            Controls.Add(_unitLevel);
            Controls.Add(_unitCount);
            Visible = false;
        }

        internal event Action CloseRequested;

        internal bool Ready { get { return _prepared && !_disposed; } }
        internal bool Active { get { return _active && Ready; } }
        internal int SessionGeneration { get { return _sessionGeneration; } }
        internal string PanelName { get { return "modifier"; } }
        internal bool CanRestoreGameFocus
        {
            get
            {
                if (_disposed || _owner.IsDisposed || !_owner.Visible) return false;
                IntPtr foreground = GetForegroundWindow();
                if (foreground == IntPtr.Zero) return false;
                if (foreground == Handle || foreground == _owner.Handle) return true;
                return GetAncestor(foreground, 2) == Handle || GetAncestor(foreground, 2) == _owner.Handle;
            }
        }

        internal Task PrepareAsync()
        {
            if (_disposed) throw new ObjectDisposedException(nameof(ModifierNativeSurface));
            if (InvokeRequired) throw new InvalidOperationException("PrepareAsync must run on the surface UI thread.");
            _prepared = true;
            LoadBackground("economy");
            return Task.CompletedTask;
        }

        internal bool ResumePanel(Rectangle rect)
        {
            if (_disposed) return false;
            _sessionGeneration++;
            Owner = _owner;
            Bounds = rect;
            _active = true;
            _prepared = true;
            _closeRaised = false;
            UpdateInputLayout();
            if (!Visible) Show();
            if (CanRestoreGameFocus) Activate();
            UpdateInputVisibility();
            Invalidate();
            return true;
        }

        internal void SuspendPanel()
        {
            if (_disposed) return;
            _active = false;
            _pressedAction = null;
            _hoverAction = 0;
            _hoverItem = -1;
            _hoverUnit = -1;
            _armTimer.Stop();
            _armedAction = null;
            Capture = false;
            ClearCalls();
            if (Visible) Hide();
        }

        internal bool CommitGeometry(Rectangle rect, int generation)
        {
            if (!Active || generation != _sessionGeneration) return false;
            Bounds = rect;
            UpdateInputLayout();
            Invalidate();
            return true;
        }

        internal void RepositionPanel(Rectangle rect, bool ensureVisible)
        {
            if (_disposed) return;
            Bounds = rect;
            UpdateInputLayout();
            if (ensureVisible && !Visible) Show();
            Invalidate();
        }

        internal bool TryPost(string json)
        {
            if (_disposed || string.IsNullOrEmpty(json)) return false;
            JObject message;
            try { message = JObject.Parse(json); }
            catch { return false; }
            string type = Text(message["type"]);
            if (string.Equals(type, "panel_cmd", StringComparison.Ordinal))
            {
                if (!string.Equals(Text(message["panel"]), "modifier", StringComparison.Ordinal)) return false;
                string cmd = Text(message["cmd"]);
                if (string.Equals(cmd, "open", StringComparison.Ordinal))
                {
                    JObject data = message["initData"] as JObject;
                    string instance = Text(data?["panelInstanceId"]);
                    string token = Text(data?["token"]);
                    if (string.IsNullOrEmpty(instance) || string.IsNullOrEmpty(token)) return false;
                    OpenSession(instance, token);
                    return true;
                }
                if (string.Equals(cmd, "close", StringComparison.Ordinal) || string.Equals(cmd, "force_close", StringComparison.Ordinal))
                {
                    RequestClose();
                    return true;
                }
                return false;
            }
            if (string.Equals(type, "panel_resp", StringComparison.Ordinal))
            {
                string instance = Text(message["panelInstanceId"]);
                if (!string.IsNullOrEmpty(instance) && !string.Equals(instance, _instance, StringComparison.Ordinal)) return false;
                string callId = Text(message["callId"]);
                if (string.IsNullOrEmpty(callId)) return false;
                Action<JObject> callback;
                lock (_callGate)
                {
                    if (!_calls.TryGetValue(callId, out callback)) return false;
                    _calls.Remove(callId);
                }
                try { callback?.Invoke(message); }
                catch (Exception error) { LogManager.Log("[ModifierNative] response failed: " + error.GetType().Name); }
                return true;
            }
            return false;
        }

        internal void ClearGeometry(string reason)
        {
            if (_disposed) return;
            _pressedAction = null;
            _hoverAction = 0;
            Invalidate();
        }

        internal bool Replay(Rectangle rect, int generation, string reason)
        {
            if (!Active || generation != _sessionGeneration) return false;
            Bounds = rect;
            if (!Visible) Show();
            UpdateInputLayout();
            Invalidate();
            return true;
        }

        private void OpenSession(string instance, string token)
        {
            _instance = instance;
            _token = token;
            _sessionGeneration++;
            _closeRaised = false;
            _snapshot = null;
            _revision = 0;
            _items = null;
            _units = null;
            _selectedItem = -1;
            _selectedUnit = -1;
            _itemPage = 1;
            _unitPage = 1;
            _itemTotal = 0;
            _unitTotal = 0;
            _unitFrame = null;
            _unitFrameSprite = null;
            _itemLoading = false;
            _unitLoading = false;
            _writeBusy = false;
            _status = "正在读取…";
            _statusTone = "pending";
            _unresolvedToken = null;
            _unresolvedOperation = null;
            _activeTab = "economy";
            _itemQuery.Text = "";
            _itemQuantity.Text = "1";
            _taskId.Text = "1";
            _unitLevel.Text = "1";
            _unitCount.Text = "1";
            _hoverItem = -1;
            _hoverUnit = -1;
            _hoverAction = 0;
            _armTimer.Stop();
            _armedAction = null;
            ClearCalls();
            UpdateInputVisibility();
            UpdateInputLayout();
            Invalidate();
            LoadSnapshot(true);
        }

        private void LoadSnapshot(bool initial)
        {
            if (!Active || _token.Length == 0) return;
            if (initial) SetStatus("正在读取…", "pending");
            SendRequest("snapshot", new JObject { ["v"] = 1, ["token"] = _token }, ApplySnapshot);
        }

        private void ApplySnapshot(JObject response)
        {
            if (!Active) return;
            if (!Bool(response["success"]))
            {
                HandleReadFailure(response);
                return;
            }
            JObject state = response["state"] as JObject;
            if (state == null)
            {
                SetStatus("状态不可用。", "error");
                return;
            }
            _snapshot = response;
            _revision = Math.Max(0, Long(response["revision"]));
            _itemPageSize = (int)Math.Max(1, Math.Min(1000, Long(response["itemPageSize"])));
            _unitPageSize = (int)Math.Max(1, Math.Min(1000, Long(response["unitPageSize"])));
            _itemTotal = (int)Math.Max(0, Math.Min(1000000, Long(response["itemCount"])));
            _unitTotal = (int)Math.Max(0, Math.Min(1000000, Long(response["unitCount"])));
            if (Bool(response["requiresReconcile"]))
                SetUnresolved(Text(response["recoveryToken"]), Text(response["recoveryOperationId"]));
            else
                ClearUnresolved();
            if (Bool(state["challengeMode"])) SetStatus("挑战模式中写操作不可用。", "error");
            else if (!Bool(state["saveAvailable"])) SetStatus("存档系统尚未就绪。", "error");
            else if (_statusTone == "pending") SetStatus("", "neutral");
            UpdateInputVisibility();
            UpdateInputLayout();
            Invalidate();
        }

        private void LoadItems()
        {
            if (!Active || _itemLoading || _token.Length == 0) return;
            _itemLoading = true;
            SetStatus("正在读取物品目录…", "pending");
            string query = (_itemQuery.Text ?? "").Trim();
            if (query.Length > 64) query = query.Substring(0, 64);
            int page = Math.Max(1, Math.Min(9999, _itemPage));
            SendRequest("items", new JObject
            {
                ["v"] = 1,
                ["token"] = _token,
                ["query"] = query,
                ["page"] = page
            }, ApplyItems);
        }

        private void ApplyItems(JObject response)
        {
            _itemLoading = false;
            if (!Active) return;
            if (!Bool(response["success"]))
            {
                HandleReadFailure(response);
                return;
            }
            JArray array = response["items"] as JArray;
            if (array == null)
            {
                SetStatus("物品目录不可用。", "error");
                return;
            }
            var items = new List<ItemEntry>();
            foreach (JToken token in array)
            {
                JObject item = token as JObject;
                if (item == null) continue;
                var entry = new ItemEntry
                {
                    Id = Long(item["id"]),
                    Name = Text(item["name"]) ?? "",
                    DisplayName = Text(item["displayName"]) ?? "",
                    Icon = Text(item["icon"]) ?? "",
                    Type = Text(item["type"]) ?? "",
                    Use = Text(item["use"]) ?? ""
                };
                items.Add(entry);
            }
            _items = items;
            _itemPage = (int)Math.Max(1, Math.Min(9999, Long(response["page"])));
            _itemPageSize = (int)Math.Max(1, Math.Min(1000, Long(response["pageSize"])));
            _itemTotal = (int)Math.Max(0, Math.Min(1000000, Long(response["total"])));
            _revision = Math.Max(_revision, Math.Max(0, Long(response["revision"])));
            _selectedItem = -1;
            if (_statusTone == "pending") SetStatus("物品目录已更新。", "ok");
            Invalidate();
        }

        private void LoadUnits()
        {
            if (!Active || _unitLoading || _token.Length == 0) return;
            _unitLoading = true;
            SetStatus("正在读取兵种目录…", "pending");
            int page = Math.Max(1, Math.Min(9999, _unitPage));
            SendRequest("units", new JObject
            {
                ["v"] = 1,
                ["token"] = _token,
                ["query"] = "",
                ["page"] = page
            }, ApplyUnits);
        }

        private void ApplyUnits(JObject response)
        {
            _unitLoading = false;
            if (!Active) return;
            if (!Bool(response["success"]))
            {
                HandleReadFailure(response);
                return;
            }
            JArray array = response["units"] as JArray;
            if (array == null)
            {
                SetStatus("兵种目录不可用。", "error");
                return;
            }
            var units = new List<UnitEntry>();
            foreach (JToken token in array)
            {
                JObject unit = token as JObject;
                if (unit == null) continue;
                units.Add(new UnitEntry
                {
                    Id = Long(unit["id"]),
                    Name = Text(unit["name"]) ?? "",
                    SpriteName = Text(unit["spriteName"]) ?? "",
                    Key = Text(unit["key"]) ?? "",
                    Level = Long(unit["level"]),
                    Hostile = Bool(unit["hostile"])
                });
            }
            _units = units;
            _unitPage = (int)Math.Max(1, Math.Min(9999, Long(response["page"])));
            _unitPageSize = (int)Math.Max(1, Math.Min(1000, Long(response["pageSize"])));
            _unitTotal = (int)Math.Max(0, Math.Min(1000000, Long(response["total"])));
            _revision = Math.Max(_revision, Math.Max(0, Long(response["revision"])));
            _selectedUnit = -1;
            if (_statusTone == "pending") SetStatus("兵种目录已更新。", "ok");
            Invalidate();
        }

        private bool TryLoadPortrait(string spriteName, out Image image)
        {
            image = null;
            if (string.IsNullOrEmpty(spriteName)) return false;
            if (!_portraitManifestLoaded)
            {
                _portraitManifestLoaded = true;
                try
                {
                    string manifestPath = Path.Combine(_webRoot, "assets", "enemy-portraits", "manifest.json");
                    if (File.Exists(manifestPath))
                        _portraitManifest = JObject.Parse(File.ReadAllText(manifestPath));
                }
                catch { _portraitManifest = null; }
            }
            JObject entry = (_portraitManifest?["entries"] as JObject)?[spriteName] as JObject;
            string status = Text(entry?["status"]);
            if (string.IsNullOrEmpty(status) || !string.Equals(status, "ready", StringComparison.Ordinal)) return false;
            JObject variants = entry?["variants"] as JObject;
            JObject variant = null;
            string defaultVariant = Text(entry?["defaultVariant"]);
            if (!string.IsNullOrEmpty(defaultVariant)) variant = variants?[defaultVariant] as JObject;
            if (variant == null && variants != null)
            {
                foreach (JProperty property in variants.Properties())
                {
                    variant = property.Value as JObject;
                    break;
                }
            }
            JObject png = (variant?["subject"] as JObject)?["pngFallback"] as JObject;
            string url = Text(png?["url"]);
            if (string.IsNullOrEmpty(url)) return false;
            try
            {
                string root = Path.GetFullPath(Path.Combine(_webRoot, "assets", "enemy-portraits"));
                string path = Path.GetFullPath(Path.Combine(_webRoot, url.Replace('/', Path.DirectorySeparatorChar)));
                if (!path.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)
                    || !File.Exists(path)) return false;
                using (Image source = Image.FromFile(path))
                {
                    Rectangle crop = PortraitCrop(png, source.Width, source.Height);
                    if (crop.Width < 1 || crop.Height < 1)
                    {
                        image = new Bitmap(source);
                    }
                    else
                    {
                        image = new Bitmap(crop.Width, crop.Height);
                        using (Graphics graphics = Graphics.FromImage(image))
                            graphics.DrawImage(source, new Rectangle(0, 0, crop.Width, crop.Height), crop, GraphicsUnit.Pixel);
                    }
                }
                return image != null;
            }
            catch { return false; }
        }

        private static Rectangle PortraitCrop(JObject png, int width, int height)
        {
            JArray bounds = png?["visibleBounds"] as JArray;
            if (bounds == null || bounds.Count < 4) return Rectangle.Empty;
            int left = (int)Math.Max(0, Math.Min(width - 1, Long(bounds[0])));
            int top = (int)Math.Max(0, Math.Min(height - 1, Long(bounds[1])));
            int right = (int)Math.Max(left + 1, Math.Min(width, Long(bounds[2])));
            int bottom = (int)Math.Max(top + 1, Math.Min(height, Long(bounds[3])));
            return new Rectangle(left, top, right - left, bottom - top);
        }

        private void RequestUnitFrame(string spriteName)
        {
            if (!Active || string.IsNullOrEmpty(spriteName) || !_unitFrameRequests.Add(spriteName)) return;
            SendRequest("unitFrame", new JObject
            {
                ["v"] = 1,
                ["token"] = _token,
                ["spriteName"] = spriteName
            }, response =>
            {
                _unitFrameRequests.Remove(spriteName);
                if (!Active || !Bool(response["success"])) return;
                int width = (int)Long(response["width"]);
                int height = (int)Long(response["height"]);
                string encoded = Text(response["pixels"]);
                Image image = DecodeUnitFrame(encoded, width, height);
                if (image == null) return;
                _unitFrames[spriteName] = image;
                if (_selectedUnit >= 0 && _units != null && _selectedUnit < _units.Count
                    && string.Equals(_units[_selectedUnit].SpriteName, spriteName, StringComparison.Ordinal))
                {
                    SetUnitFrame(image, spriteName);
                }
            });
        }

        private void SetUnitFrame(Image image, string spriteName)
        {
            _unitFrame = image;
            _unitFrameSprite = spriteName;
            Invalidate();
        }

        private void SelectUnit(int index)
        {
            if (_units == null || index < 0 || index >= _units.Count) return;
            _selectedUnit = index;
            UnitEntry unit = _units[index];
            _unitLevel.Text = Math.Max(1, unit.Level).ToString();
            _unitCount.Text = "1";
            _unitFrameSprite = null;
            Image cached;
            if (_unitFrames.TryGetValue(unit.SpriteName, out cached))
            {
                SetUnitFrame(cached, unit.SpriteName);
            }
            else if (TryLoadPortrait(unit.SpriteName, out cached))
            {
                _unitFrames[unit.SpriteName] = cached;
                SetUnitFrame(cached, unit.SpriteName);
            }
            else
            {
                _unitFrame = null;
                RequestUnitFrame(unit.SpriteName);
            }
            SetStatus(unit.Name.Length > 0 ? unit.Name : unit.SpriteName, "neutral");
            Invalidate();
        }

        private void SelectItem(int index)
        {
            if (_items == null || index < 0 || index >= _items.Count) return;
            _selectedItem = index;
            ItemEntry item = _items[index];
            _itemQuery.Text = item.Name;
            SetStatus(item.DisplayName, "neutral");
            Invalidate();
        }

        private void SearchItems()
        {
            _itemPage = 1;
            _items = null;
            _selectedItem = -1;
            LoadItems();
        }

        private void ChangeItemPage(int delta, bool first, bool last)
        {
            int pages = _itemTotal > 0 ? (int)Math.Ceiling(_itemTotal / (double)Math.Max(1, _itemPageSize)) : 0;
            int next = first ? 1 : last ? Math.Max(1, pages) : _itemPage + delta;
            if (next < 1) next = 1;
            if (pages > 0 && next > pages) next = pages;
            if (next == _itemPage && !first && !last) return;
            _itemPage = next;
            _items = null;
            _selectedItem = -1;
            LoadItems();
        }

        private void ChangeUnitPage(int delta, bool first, bool last)
        {
            int pages = _unitTotal > 0 ? (int)Math.Ceiling(_unitTotal / (double)Math.Max(1, _unitPageSize)) : 0;
            int next = first ? 1 : last ? Math.Max(1, pages) : _unitPage + delta;
            if (next < 1) next = 1;
            if (pages > 0 && next > pages) next = pages;
            if (next == _unitPage && !first && !last) return;
            _unitPage = next;
            _units = null;
            _selectedUnit = -1;
            LoadUnits();
        }

        private void SetTab(string tab)
        {
            if (string.IsNullOrEmpty(tab) || string.Equals(tab, _activeTab, StringComparison.Ordinal)) return;
            _activeTab = tab;
            _hoverItem = -1;
            _hoverUnit = -1;
            _hoverAction = 0;
            _pressedAction = null;
            try { _tabSound?.Play(); } catch { }
            UpdateInputVisibility();
            UpdateInputLayout();
            Invalidate();
            if (tab == "items" && _items == null) LoadItems();
            if (tab == "units" && _units == null) LoadUnits();
        }

        private void IssueWrite(string cmd, JObject extra, bool closeAfter)
        {
            if (!CanWrite())
            {
                SetStatus(_unresolvedToken != null ? "请先核对上次操作。" : "当前不能执行写操作。", "error");
                return;
            }
            string operationId = "mod.native." + (++_operationSequence).ToString() + "." + Guid.NewGuid().ToString("N").Substring(0, 8);
            var payload = new JObject
            {
                ["v"] = 1,
                ["token"] = _token,
                ["operationId"] = operationId,
                ["expectedRevision"] = _revision
            };
            if (extra != null)
            {
                foreach (JProperty property in extra.Properties()) payload[property.Name] = property.Value;
            }
            _writeBusy = true;
            SetStatus("正在请求 AS2…", "pending");
            UpdateInputVisibility();
            Invalidate();
            SendRequest(cmd, payload, response =>
            {
                _writeBusy = false;
                HandleWriteResponse(cmd, operationId, response, closeAfter);
                UpdateInputVisibility();
                Invalidate();
            });
        }

        private void HandleWriteResponse(string cmd, string operationId, JObject response, bool closeAfter)
        {
            if (!Active) return;
            bool success = Bool(response["success"]);
            long revision = Long(response["revision"]);
            if (revision >= 0) _revision = Math.Max(_revision, revision);
            if (success)
            {
                ClearUnresolved();
                long money;
                long kcoin;
                JObject state = _snapshot?["state"] as JObject;
                if (state != null && TryLong(response["money"], out money) && money >= 0) state["money"] = money;
                if (state != null && TryLong(response["kcoin"], out kcoin) && kcoin >= 0) state["kcoin"] = kcoin;
                SetStatus(Text(response["message"]) ?? "已完成。", "ok");
                if (closeAfter || Bool(response["closeAfter"]))
                {
                    RequestClose();
                    return;
                }
                LoadSnapshot(false);
                return;
            }
            string error = Text(response["error"]) ?? "操作未完成。";
            if (string.Equals(error, "not_applied", StringComparison.Ordinal))
            {
                ClearUnresolved();
                SetStatus("上次操作未执行。", "ok");
                LoadSnapshot(false);
                return;
            }
            if (Bool(response["requiresReconcile"]) || string.Equals(error, "apply_ambiguous", StringComparison.Ordinal))
            {
                SetUnresolved(Text(response["recoveryToken"]) ?? _token, Text(response["recoveryOperationId"]) ?? operationId);
                SetStatus("写操作结果未确认，已冻结后续写。", "error");
                return;
            }
            SetStatus(MessageFor(error), "error");
            if (string.Equals(error, "stale_revision", StringComparison.Ordinal)
                || string.Equals(error, "context_changed", StringComparison.Ordinal))
                LoadSnapshot(false);
        }

        private void QueryUnresolved()
        {
            if (!Active || _writeBusy || string.IsNullOrEmpty(_unresolvedToken) || string.IsNullOrEmpty(_unresolvedOperation)) return;
            string token = _unresolvedToken;
            string operation = _unresolvedOperation;
            SetStatus("正在核对…", "pending");
            SendRequest("query", new JObject
            {
                ["v"] = 1,
                ["token"] = token,
                ["operationId"] = operation
            }, response =>
            {
                if (!Active) return;
                bool success = Bool(response["success"]);
                string error = Text(response["error"]) ?? "";
                if (success || string.Equals(error, "not_applied", StringComparison.Ordinal))
                {
                    ClearUnresolved();
                    SetStatus(success ? (Text(response["message"]) ?? "已确认完成。") : "上次操作未执行。", "ok");
                    LoadSnapshot(false);
                }
                else if (Bool(response["requiresReconcile"]) || string.Equals(error, "apply_ambiguous", StringComparison.Ordinal))
                {
                    SetStatus("仍无法确认，请保留现场并重启。", "error");
                }
                else
                {
                    ClearUnresolved();
                    SetStatus(MessageFor(error), "error");
                    LoadSnapshot(false);
                }
            });
        }

        private bool CanWrite()
        {
            if (!Active || _snapshot == null || _writeBusy || _unresolvedToken != null) return false;
            JObject state = _snapshot["state"] as JObject;
            return state != null && !Bool(state["challengeMode"]) && Bool(state["saveAvailable"]);
        }

        private void HandleReadFailure(JObject response)
        {
            string error = Text(response?["error"]) ?? "读取失败。";
            if (Bool(response?["requiresReconcile"]))
                SetUnresolved(Text(response["recoveryToken"]), Text(response["recoveryOperationId"]));
            SetStatus(MessageFor(error), "error");
        }

        private void SetUnresolved(string token, string operation)
        {
            if (string.IsNullOrEmpty(token) || string.IsNullOrEmpty(operation))
            {
                SetStatus("缺少恢复身份，请重启游戏。", "error");
                return;
            }
            _unresolvedToken = token;
            _unresolvedOperation = operation;
            SetStatus("上次操作结果未确认，请先核对。", "error");
        }

        private void ClearUnresolved()
        {
            _unresolvedToken = null;
            _unresolvedOperation = null;
        }

        private void SendRequest(string cmd, JObject payload, Action<JObject> callback)
        {
            if (!Active || _disposed) return;
            string callId = "modifier.native." + (++_requestSequence).ToString() + "." + Guid.NewGuid().ToString("N").Substring(0, 8);
            lock (_callGate) _calls[callId] = callback;
            var message = new JObject
            {
                ["type"] = "panel",
                ["panel"] = "modifier",
                ["domain"] = "modifier",
                ["cmd"] = cmd,
                ["panelInstanceId"] = _instance,
                ["callId"] = callId,
                ["payload"] = payload
            };
            try
            {
                _task.HandleWebRequest(cmd, message);
            }
            catch (Exception error)
            {
                lock (_callGate) _calls.Remove(callId);
                SetStatus("请求未能发送。", "error");
                LogManager.Log("[ModifierNative] request failed: " + error.GetType().Name);
            }
        }

        private void ClearCalls()
        {
            lock (_callGate) _calls.Clear();
        }

        private void RequestClose()
        {
            if (_disposed || _closeRaised) return;
            _closeRaised = true;
            Action handler = CloseRequested;
            try { handler?.Invoke(); }
            catch (Exception error) { LogManager.Log("[ModifierNative] close failed: " + error.GetType().Name); }
        }

        private void OnItemQueryKeyDown(object sender, KeyEventArgs e)
        {
            if (e.KeyCode != Keys.Enter) return;
            e.SuppressKeyPress = true;
            SearchItems();
        }

        private TextBox CreateInput(bool numeric)
        {
            var input = new TextBox
            {
                BorderStyle = BorderStyle.None,
                BackColor = Color.Black,
                ForeColor = Gold,
                Font = _smallFont,
                Visible = false,
                TabStop = false
            };
            if (numeric)
            {
                input.KeyPress += OnNumericKeyPress;
            }
            return input;
        }

        private static void OnNumericKeyPress(object sender, KeyPressEventArgs e)
        {
            if (!char.IsControl(e.KeyChar) && !char.IsDigit(e.KeyChar)) e.Handled = true;
        }

        private void UpdateInputVisibility()
        {
            if (_itemQuery == null) return;
            bool items = Active && _activeTab == "items";
            bool level = Active && _activeTab == "level";
            bool units = Active && _activeTab == "units";
            _itemQuery.Visible = items;
            _itemQuantity.Visible = items;
            _taskId.Visible = level;
            _unitLevel.Visible = units;
            _unitCount.Visible = units;
        }

        private void UpdateInputLayout()
        {
            if (_itemQuery == null) return;
            Size size = ClientSize;
            _itemQuery.Bounds = ModifierNativeLayout.ToClient(ModifierNativeLayout.ItemQuery, size);
            _itemQuantity.Bounds = ModifierNativeLayout.ToClient(ModifierNativeLayout.ItemQuantity, size);
            _taskId.Bounds = ModifierNativeLayout.ToClient(ModifierNativeLayout.TaskId, size);
            _unitLevel.Bounds = ModifierNativeLayout.ToClient(ModifierNativeLayout.UnitLevel, size);
            _unitCount.Bounds = ModifierNativeLayout.ToClient(ModifierNativeLayout.UnitCount, size);
            _itemQuery.Font = _smallFont;
            _itemQuantity.Font = _smallFont;
            _taskId.Font = _smallFont;
            _unitLevel.Font = _smallFont;
            _unitCount.Font = _smallFont;
        }

        private static Font CreateFont(float size, FontStyle style)
        {
            try { return new Font("Microsoft YaHei UI", size, style, GraphicsUnit.Point); }
            catch { return new Font(FontFamily.GenericSansSerif, size, style, GraphicsUnit.Point); }
        }

        private void SetStatus(string text, string tone)
        {
            _status = text ?? "";
            _statusTone = tone ?? "neutral";
            if (IsHandleCreated) Invalidate();
        }

        private static string MessageFor(string error)
        {
            switch (error)
            {
                case "unsupported_domain": return "请求域无效。";
                case "unsupported_cmd": return "命令不受支持。";
                case "unsupported_version": return "协议版本不一致。";
                case "invalid_payload": return "参数无效。";
                case "invalid_owner": return "面板实例已失效。";
                case "disconnected": return "游戏连接不可用。";
                case "timeout": return "AS2 未在时限内确认。";
                case "not_sent": return "请求未能发送。";
                case "client_timeout": return "AS2 未在时限内确认。";
                case "malformed_response": return "回包无法验证。";
                case "reconcile_required": return "请先核对上次操作。";
                case "apply_ambiguous": return "结果未确认。";
                case "stale_token": return "会话已失效。";
                case "stale_revision": return "状态已变化，请刷新。";
                case "context_changed": return "场景或存档已切换。";
                case "invalid_balance": return "余额无法安全写入。";
                case "item_unavailable": return "物品不可生产。";
                case "quantity_overflow": return "数量超过上限。";
                case "pickup_unavailable": return "拾取物系统未就绪。";
                case "actor_unavailable": return "角色不在场景。";
                case "stage_unavailable": return "没有可操作关卡。";
                case "wave_unavailable": return "没有可完成波次。";
                case "task_unavailable": return "任务系统不可用。";
                case "unit_unavailable": return "兵种不可生成。";
                case "merc_pool_empty": return "雇佣池为空。";
                case "merc_pool_invalid": return "雇佣池结构异常。";
                case "spawn_unavailable": return "生成函数未就绪。";
                case "spawn_failed": return "生成失败。";
                case "navigation_unavailable": return "场景转场未就绪。";
                case "not_allowed": return "当前场景不允许。";
                case "challenge_mode": return "挑战模式不可写。";
                case "save_unavailable": return "存档系统未就绪。";
                case "not_applied": return "上次操作未执行。";
                default: return "操作未完成。";
            }
        }

        private static new string Text(JToken token)
        {
            return token != null && token.Type == JTokenType.String ? token.Value<string>() : null;
        }

        private static bool Bool(JToken token)
        {
            return token != null && token.Type == JTokenType.Boolean && token.Value<bool>();
        }

        private static bool TryLong(JToken token, out long value)
        {
            value = 0;
            if (token == null || token.Type != JTokenType.Integer) return false;
            try { value = token.Value<long>(); return true; }
            catch (OverflowException) { return false; }
        }

        private static long Long(JToken token)
        {
            long value;
            return TryLong(token, out value) ? value : 0;
        }

        private Image BackgroundFor(string tab)
        {
            Image image;
            if (_backgrounds.TryGetValue(tab, out image)) return image;
            try
            {
                string path = Path.Combine(_webRoot, "assets", "modifier", "flash-" + tab + ".png");
                if (!File.Exists(path)) return null;
                using (Image source = Image.FromFile(path)) image = new Bitmap(source);
                _backgrounds[tab] = image;
                return image;
            }
            catch { return null; }
        }

        private void LoadBackground(string tab)
        {
            Image image = BackgroundFor(tab);
            if (image != null) Invalidate();
        }

        private Image IconFor(string name)
        {
            if (string.IsNullOrEmpty(name)) return null;
            Image image;
            if (_icons.TryGetValue(name, out image)) return image;
            try
            {
                if (_iconManifest == null)
                {
                    string manifestPath = Path.Combine(_webRoot, "icons", "manifest.json");
                    if (!File.Exists(manifestPath)) return null;
                    _iconManifest = JObject.Parse(File.ReadAllText(manifestPath));
                }
                JObject entry = _iconManifest[name] as JObject;
                string file = Text(entry?["f1"]) ?? Text(entry?["uri"]);
                if (string.IsNullOrEmpty(file)) return null;
                string path = Path.Combine(_webRoot, "icons", file);
                if (!File.Exists(path)) return null;
                using (SKBitmap bitmap = SKBitmap.Decode(path))
                {
                    if (bitmap == null) return null;
                    using (SKImage skImage = SKImage.FromBitmap(bitmap))
                    using (SKData data = skImage.Encode(SKEncodedImageFormat.Png, 100))
                    using (var stream = new MemoryStream(data.ToArray()))
                    using (Image source = Image.FromStream(stream))
                        image = new Bitmap(source);
                }
                _icons[name] = image;
                return image;
            }
            catch { return null; }
        }

        private static Image DecodeUnitFrame(string encoded, int width, int height)
        {
            if (string.IsNullOrEmpty(encoded) || width < 1 || height < 1) return null;
            try
            {
                byte[] source = Convert.FromBase64String(encoded);
                if (source.Length != width * height * 4) return null;
                var bitmap = new Bitmap(width, height, PixelFormat.Format32bppArgb);
                BitmapData data = bitmap.LockBits(new Rectangle(0, 0, width, height), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
                try
                {
                    byte[] target = new byte[source.Length];
                    for (int i = 0; i < source.Length; i += 4)
                    {
                        target[i] = source[i + 2];
                        target[i + 1] = source[i + 1];
                        target[i + 2] = source[i];
                        target[i + 3] = source[i + 3];
                    }
                    Marshal.Copy(target, 0, data.Scan0, target.Length);
                }
                finally { bitmap.UnlockBits(data); }
                return bitmap;
            }
            catch { return null; }
        }

        protected override void OnPaintBackground(PaintEventArgs e)
        {
            e.Graphics.Clear(KeyColor);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            Graphics graphics = e.Graphics;
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            graphics.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
            Size client = ClientSize;
            float scale = ModifierNativeLayout.ScaleFor(client);
            PointF offset = ModifierNativeLayout.OffsetFor(client, scale);
            Image background = BackgroundFor(_activeTab) ?? BackgroundFor("economy");
            if (background != null)
                graphics.DrawImage(background, new RectangleF(offset.X, offset.Y, ModifierNativeLayout.Width * scale, ModifierNativeLayout.Height * scale));
            GraphicsState state = graphics.Save();
            graphics.TranslateTransform(offset.X, offset.Y);
            graphics.ScaleTransform(scale, scale);
            DrawTab(graphics, ModifierNativeLayout.EconomyTab, "economy");
            DrawTab(graphics, ModifierNativeLayout.ItemsTab, "items");
            DrawTab(graphics, ModifierNativeLayout.LevelTab, "level");
            DrawTab(graphics, ModifierNativeLayout.UnitsTab, "units");
            if (_activeTab == "economy")
            {
                DrawButton(graphics, ModifierNativeLayout.Money, "money");
                DrawButton(graphics, ModifierNativeLayout.KCoin, "kcoin");
                DrawButton(graphics, ModifierNativeLayout.TestSpace, "test_space");
            }
            else if (_activeTab == "items")
            {
                DrawItems(graphics);
            }
            else if (_activeTab == "level")
            {
                DrawButton(graphics, ModifierNativeLayout.KillAll, "kill_all");
                DrawButton(graphics, ModifierNativeLayout.FinishWave, "finish_wave");
                DrawButton(graphics, ModifierNativeLayout.FinishMap, "finish_map");
                DrawButton(graphics, ModifierNativeLayout.FinishStage, "finish_stage");
                DrawButton(graphics, ModifierNativeLayout.GrantTask, "grant_task");
                DrawButton(graphics, ModifierNativeLayout.UnlockStages, "unlock_stages");
            }
            else if (_activeTab == "units")
            {
                DrawUnits(graphics);
            }
            DrawStatus(graphics);
            graphics.Restore(state);
        }

        private void DrawTab(Graphics graphics, Rectangle rect, string tab)
        {
            if (string.Equals(_activeTab, tab, StringComparison.Ordinal)) return;
            if (_hoverAction == ActionId("tab:" + tab))
                DrawOutline(graphics, rect, Color.FromArgb(70, Gold));
        }

        private void DrawButton(Graphics graphics, Rectangle rect, string action)
        {
            if (_hoverAction == ActionId(action)) DrawOutline(graphics, rect, Color.FromArgb(100, Gold));
        }

        private void DrawOutline(Graphics graphics, Rectangle rect, Color color)
        {
            using (var pen = new Pen(color, 1f))
                graphics.DrawRectangle(pen, rect.X + 1, rect.Y + 1, rect.Width - 2, rect.Height - 2);
        }

        private void DrawItems(Graphics graphics)
        {
            DrawButton(graphics, ModifierNativeLayout.ItemFirst, "item_first");
            DrawButton(graphics, ModifierNativeLayout.ItemPrevious, "item_prev");
            DrawButton(graphics, ModifierNativeLayout.ItemNext, "item_next");
            DrawButton(graphics, ModifierNativeLayout.ItemLast, "item_last");
            DrawButton(graphics, ModifierNativeLayout.ItemMinus, "item_minus");
            DrawButton(graphics, ModifierNativeLayout.ItemPlus, "item_plus");
            DrawButton(graphics, ModifierNativeLayout.ItemProduce, "item_produce");
            DrawButton(graphics, ModifierNativeLayout.ItemSearch, "item_search");
            if (_items == null)
            {
                DrawText(graphics, _itemLoading ? "读取中…" : "物品目录未加载。", ModifierNativeLayout.ItemGrid, _smallFont, Gold, _ellipsis);
                return;
            }
            if (_items.Count == 0)
            {
                DrawText(graphics, "没有匹配物品。", ModifierNativeLayout.ItemGrid, _smallFont, Gold, _ellipsis);
            }
            for (int i = 0; i < _items.Count && i < ModifierNativeLayout.ItemColumns * ModifierNativeLayout.ItemRows; i++)
            {
                Rectangle cell = ModifierNativeLayout.ItemCell(i);
                ItemEntry item = _items[i];
                if (_selectedItem == i)
                {
                    using (var brush = new SolidBrush(Color.FromArgb(32, Gold)))
                        graphics.FillRectangle(brush, cell);
                    using (var pen = new Pen(Gold, 1f))
                        graphics.DrawRectangle(pen, cell.X, cell.Y, cell.Width - 1, cell.Height - 1);
                }
                Image icon = IconFor(item.Icon);
                if (icon != null)
                    graphics.DrawImage(icon, cell.X + 3, cell.Y + 3, 22, 22);
                else
                    DrawText(graphics, "?", new Rectangle(cell.X, cell.Y + 6, cell.Width, 18), _smallFont, Gold, _ellipsis);
                DrawText(graphics, "1", new Rectangle(cell.Right - 8, cell.Bottom - 9, 8, 8), _tinyFont, Gold, _ellipsis);
            }
            DrawText(graphics, PageText(_itemTotal, _itemPage, _itemPageSize), new Rectangle(360, 348, 130, 20), _smallFont, Gold, _ellipsis);
            if (_hoverItem >= 0 && _items != null && _hoverItem < _items.Count)
                DrawItemTooltip(graphics, _items[_hoverItem]);
        }

        private void DrawUnits(Graphics graphics)
        {
            DrawButton(graphics, ModifierNativeLayout.UnitFirst, "unit_first");
            DrawButton(graphics, ModifierNativeLayout.UnitPrevious, "unit_prev");
            DrawButton(graphics, ModifierNativeLayout.UnitNext, "unit_next");
            DrawButton(graphics, ModifierNativeLayout.UnitLast, "unit_last");
            DrawButton(graphics, ModifierNativeLayout.UnitLevelMinus, "level_minus");
            DrawButton(graphics, ModifierNativeLayout.UnitLevelPlus, "level_plus");
            DrawButton(graphics, ModifierNativeLayout.UnitCountMinus, "count_minus");
            DrawButton(graphics, ModifierNativeLayout.UnitCountPlus, "count_plus");
            DrawButton(graphics, ModifierNativeLayout.UnitSpawn, "unit_spawn");
            DrawButton(graphics, ModifierNativeLayout.UnitMerc, "unit_merc");
            if (_unitFrame != null && !string.Equals(_unitFrameSprite, null, StringComparison.Ordinal))
            {
                Rectangle frame = ModifierNativeLayout.UnitFrame;
                float ratio = Math.Min(frame.Width / (float)_unitFrame.Width, frame.Height / (float)_unitFrame.Height);
                int width = Math.Max(1, (int)(_unitFrame.Width * ratio));
                int height = Math.Max(1, (int)(_unitFrame.Height * ratio));
                graphics.DrawImage(_unitFrame, frame.X + (frame.Width - width) / 2, frame.Y + (frame.Height - height) / 2, width, height);
            }
            if (_units == null)
            {
                DrawText(graphics, _unitLoading ? "读取中…" : "兵种目录未加载。", ModifierNativeLayout.UnitGrid, _smallFont, Gold, _ellipsis);
                return;
            }
            for (int i = 0; i < _units.Count && i < ModifierNativeLayout.UnitRowsPerPage; i++)
            {
                UnitEntry unit = _units[i];
                Rectangle row = ModifierNativeLayout.UnitRow(i);
                if (_selectedUnit == i)
                {
                    using (var brush = new SolidBrush(Color.FromArgb(32, Gold)))
                        graphics.FillRectangle(brush, row);
                    using (var pen = new Pen(Gold, 1f))
                        graphics.DrawRectangle(pen, row.X, row.Y, row.Width - 1, row.Height - 1);
                }
                Color nameColor = unit.Hostile ? HostileText : UnitText;
                DrawText(graphics, unit.Name.Length > 0 ? unit.Name : unit.SpriteName,
                    new Rectangle(row.X + 6, row.Y + 1, row.Width - 12, 12), _textFont, nameColor, _ellipsis);
                DrawText(graphics, unit.SpriteName + " · " + unit.Level + " · " + (unit.Hostile ? "敌" : "友"),
                    new Rectangle(row.X + 6, row.Y + 13, row.Width - 12, 11), _tinyFont, UnitMeta, _ellipsis);
            }
            DrawText(graphics, PageText(_unitTotal, _unitPage, _unitPageSize), ModifierNativeLayout.UnitPageState, _smallFont, Gold, _ellipsis);
            DrawHostile(graphics);
        }

        private void DrawHostile(Graphics graphics)
        {
            Rectangle rect = ModifierNativeLayout.UnitHostile;
            bool checkedValue = _selectedUnit >= 0 && _units != null && _selectedUnit < _units.Count && _units[_selectedUnit].Hostile;
            using (var pen = new Pen(SoftGold, 1f)) graphics.DrawRectangle(pen, rect);
            if (checkedValue)
                using (var brush = new SolidBrush(Gold))
                    graphics.FillRectangle(brush, rect.X + 3, rect.Y + 3, rect.Width - 6, rect.Height - 6);
        }

        private void DrawItemTooltip(Graphics graphics, ItemEntry item)
        {
            string name = item.DisplayName.Length > 0 ? item.DisplayName : item.Name;
            string meta = "#" + item.Id + " · " + (item.Type.Length > 0 ? item.Type : "—") + " · " + (item.Use.Length > 0 ? item.Use : "—");
            const int width = 180;
            int x = _tooltipPoint.X + 14;
            int y = _tooltipPoint.Y + 10;
            if (x + width > ModifierNativeLayout.Width - 4) x = Math.Max(4, _tooltipPoint.X - width - 8);
            if (y + 38 > ModifierNativeLayout.Height - 4) y = Math.Max(4, ModifierNativeLayout.Height - 42);
            using (var brush = new SolidBrush(Color.FromArgb(235, Color.Black)))
                graphics.FillRectangle(brush, x, y, width, 38);
            using (var pen = new Pen(Color.White, 1f))
                graphics.DrawRectangle(pen, x, y, width - 1, 37);
            DrawText(graphics, name, new Rectangle(x + 6, y + 4, width - 12, 14), _smallFont, Color.White, _ellipsis);
            DrawText(graphics, meta, new Rectangle(x + 6, y + 20, width - 12, 12), _tinyFont, SoftGold, _ellipsis);
        }

        private void DrawStatus(Graphics graphics)
        {
            if (_unresolvedToken != null)
            {
                DrawButton(graphics, ModifierNativeLayout.Reconcile, "reconcile");
                DrawText(graphics, "核对", ModifierNativeLayout.Reconcile, _tinyFont, ErrorText, _ellipsis);
            }
            if (string.IsNullOrEmpty(_status)) return;
            Color color = StatusColor(_statusTone);
            DrawText(graphics, _status, new Rectangle(180, 374, 510, 20), _statusFont, color, _ellipsis);
        }

        private static Color StatusColor(string tone)
        {
            switch (tone)
            {
                case "ok": return OkText;
                case "error": return ErrorText;
                case "warn":
                case "pending": return PendingText;
                default: return Color.FromArgb(229, 166, 77);
            }
        }

        private void DrawText(Graphics graphics, string text, Rectangle rect, Font font, Color color, StringFormat format)
        {
            if (string.IsNullOrEmpty(text)) return;
            using (var brush = new SolidBrush(color))
                graphics.DrawString(text, font, brush, rect, format ?? _clip);
        }

        private static string PageText(int total, int page, int pageSize)
        {
            int pages = total > 0 ? (int)Math.Ceiling(total / (double)Math.Max(1, pageSize)) : 0;
            return total + " · " + (pages > 0 ? page + "/" + pages : "0/0");
        }

        private int ActionId(string action)
        {
            int hash = 17;
            for (int i = 0; i < action.Length; i++) hash = hash * 31 + action[i];
            return hash;
        }

        private string HitAction(Point logical)
        {
            string tab = ModifierNativeLayout.TabAt(logical);
            if (tab != null) return "tab:" + tab;
            if (ModifierNativeLayout.Close.Contains(logical)) return "close";
            if (_unresolvedToken != null && ModifierNativeLayout.Reconcile.Contains(logical)) return "reconcile";
            if (_activeTab == "economy")
            {
                if (ModifierNativeLayout.Money.Contains(logical)) return "money";
                if (ModifierNativeLayout.KCoin.Contains(logical)) return "kcoin";
                if (ModifierNativeLayout.TestSpace.Contains(logical)) return "test_space";
            }
            else if (_activeTab == "items")
            {
                if (ModifierNativeLayout.ItemFirst.Contains(logical)) return "item_first";
                if (ModifierNativeLayout.ItemPrevious.Contains(logical)) return "item_prev";
                if (ModifierNativeLayout.ItemNext.Contains(logical)) return "item_next";
                if (ModifierNativeLayout.ItemLast.Contains(logical)) return "item_last";
                if (ModifierNativeLayout.ItemMinus.Contains(logical)) return "item_minus";
                if (ModifierNativeLayout.ItemPlus.Contains(logical)) return "item_plus";
                if (ModifierNativeLayout.ItemProduce.Contains(logical)) return "item_produce";
                if (ModifierNativeLayout.ItemSearch.Contains(logical)) return "item_search";
                int index = ModifierNativeLayout.ItemIndexAt(logical);
                if (index >= 0) return "item:" + index;
            }
            else if (_activeTab == "level")
            {
                if (ModifierNativeLayout.KillAll.Contains(logical)) return "kill_all";
                if (ModifierNativeLayout.FinishWave.Contains(logical)) return "finish_wave";
                if (ModifierNativeLayout.FinishMap.Contains(logical)) return "finish_map";
                if (ModifierNativeLayout.FinishStage.Contains(logical)) return "finish_stage";
                if (ModifierNativeLayout.GrantTask.Contains(logical)) return "grant_task";
                if (ModifierNativeLayout.UnlockStages.Contains(logical)) return "unlock_stages";
            }
            else if (_activeTab == "units")
            {
                if (ModifierNativeLayout.UnitFirst.Contains(logical)) return "unit_first";
                if (ModifierNativeLayout.UnitPrevious.Contains(logical)) return "unit_prev";
                if (ModifierNativeLayout.UnitNext.Contains(logical)) return "unit_next";
                if (ModifierNativeLayout.UnitLast.Contains(logical)) return "unit_last";
                if (ModifierNativeLayout.UnitLevelMinus.Contains(logical)) return "level_minus";
                if (ModifierNativeLayout.UnitLevelPlus.Contains(logical)) return "level_plus";
                if (ModifierNativeLayout.UnitCountMinus.Contains(logical)) return "count_minus";
                if (ModifierNativeLayout.UnitCountPlus.Contains(logical)) return "count_plus";
                if (ModifierNativeLayout.UnitHostile.Contains(logical)) return "hostile";
                if (ModifierNativeLayout.UnitSpawn.Contains(logical)) return "unit_spawn";
                if (ModifierNativeLayout.UnitMerc.Contains(logical)) return "unit_merc";
                int index = ModifierNativeLayout.UnitIndexAt(logical);
                if (index >= 0) return "unit:" + index;
            }
            return null;
        }

        private void ExecuteAction(string action)
        {
            if (string.IsNullOrEmpty(action)) return;
            if (action.StartsWith("tab:", StringComparison.Ordinal)) { SetTab(action.Substring(4)); return; }
            if (action.StartsWith("item:", StringComparison.Ordinal)) { int index; if (int.TryParse(action.Substring(5), out index)) SelectItem(index); return; }
            if (action.StartsWith("unit:", StringComparison.Ordinal)) { int index; if (int.TryParse(action.Substring(5), out index)) SelectUnit(index); return; }
            switch (action)
            {
                case "close": RequestClose(); break;
                case "reconcile": QueryUnresolved(); break;
                case "money": IssueWrite("grantMoney", null, false); break;
                case "kcoin": IssueWrite("grantKCoin", null, false); break;
                case "test_space": ArmThenWrite("test_space", "levelAction", new JObject { ["levelAction"] = "test_space" }, true); break;
                case "item_first": ChangeItemPage(0, true, false); break;
                case "item_prev": ChangeItemPage(-1, false, false); break;
                case "item_next": ChangeItemPage(1, false, false); break;
                case "item_last": ChangeItemPage(0, false, true); break;
                case "item_minus": Nudge(_itemQuantity, -1, 1, 999999999); break;
                case "item_plus": Nudge(_itemQuantity, 1, 1, 999999999); break;
                case "item_produce": ProduceItem(); break;
                case "item_search": SearchItems(); break;
                case "kill_all": IssueWrite("levelAction", new JObject { ["levelAction"] = "kill_all" }, false); break;
                case "finish_wave": IssueWrite("levelAction", new JObject { ["levelAction"] = "finish_wave" }, false); break;
                case "finish_map": IssueWrite("levelAction", new JObject { ["levelAction"] = "finish_map" }, false); break;
                case "finish_stage": ArmThenWrite("finish_stage", "levelAction", new JObject { ["levelAction"] = "finish_stage" }, true); break;
                case "grant_task": GrantTask(); break;
                case "unlock_stages": IssueWrite("levelAction", new JObject { ["levelAction"] = "unlock_stages" }, false); break;
                case "unit_first": ChangeUnitPage(0, true, false); break;
                case "unit_prev": ChangeUnitPage(-1, false, false); break;
                case "unit_next": ChangeUnitPage(1, false, false); break;
                case "unit_last": ChangeUnitPage(0, false, true); break;
                case "level_minus": Nudge(_unitLevel, -1, 1, 9999); break;
                case "level_plus": Nudge(_unitLevel, 1, 1, 9999); break;
                case "count_minus": Nudge(_unitCount, -1, 1, 100); break;
                case "count_plus": Nudge(_unitCount, 1, 1, 100); break;
                case "hostile": ToggleHostile(); break;
                case "unit_spawn": SpawnUnit(); break;
                case "unit_merc": SpawnMerc(); break;
            }
        }

        private void ArmThenWrite(string action, string cmd, JObject extra, bool closeAfter)
        {
            if (string.Equals(_armedAction, action, StringComparison.Ordinal) && DateTime.UtcNow <= _armedUntil)
            {
                _armedAction = null;
                _armTimer.Stop();
                IssueWrite(cmd, extra, closeAfter);
                return;
            }
            _armedAction = action;
            _armedUntil = DateTime.UtcNow.AddSeconds(3);
            _armTimer.Stop();
            _armTimer.Start();
            SetStatus("再次点击确认。", "warn");
        }

        private void OnArmTimer(object sender, EventArgs e)
        {
            _armTimer.Stop();
            _armedAction = null;
            if (_statusTone == "warn") SetStatus("", "neutral");
        }

        private void ProduceItem()
        {
            if (_selectedItem < 0 || _items == null || _selectedItem >= _items.Count)
            {
                SetStatus("请先选择物品。", "warn");
                return;
            }
            int quantity;
            if (!int.TryParse(_itemQuantity.Text, out quantity) || quantity < 1 || quantity > 999999999)
            {
                SetStatus("数量需为 1–999999999。", "error");
                return;
            }
            IssueWrite("spawnItem", new JObject
            {
                ["itemName"] = _items[_selectedItem].Name,
                ["quantity"] = quantity
            }, false);
        }

        private void GrantTask()
        {
            int task;
            if (!int.TryParse(_taskId.Text, out task) || task < 1 || task > 999)
            {
                SetStatus("任务 id 必须是 1–999 的整数。", "error");
                return;
            }
            IssueWrite("grantTask", new JObject { ["taskId"] = task }, false);
        }

        private void SpawnUnit()
        {
            if (_selectedUnit < 0 || _units == null || _selectedUnit >= _units.Count)
            {
                SetStatus("请先选择兵种。", "warn");
                return;
            }
            int level;
            int count;
            if (!int.TryParse(_unitLevel.Text, out level) || level < 1 || level > 9999
                || !int.TryParse(_unitCount.Text, out count) || count < 1 || count > 100)
            {
                SetStatus("等级 1–9999，数量 1–100。", "error");
                return;
            }
            IssueWrite("spawnUnit", new JObject
            {
                ["unitId"] = _units[_selectedUnit].Id,
                ["count"] = count,
                ["level"] = level,
                ["hostile"] = CurrentHostile()
            }, false);
        }

        private void SpawnMerc()
        {
            if (_selectedUnit < 0 || _units == null || _selectedUnit >= _units.Count)
            {
                SetStatus("请先选择兵种。", "warn");
                return;
            }
            int level;
            if (!int.TryParse(_unitLevel.Text, out level) || level < 1 || level > 9999)
            {
                SetStatus("等级 1–9999。", "error");
                return;
            }
            IssueWrite("spawnMerc", new JObject
            {
                ["unitId"] = _units[_selectedUnit].Id,
                ["level"] = level,
                ["hostile"] = CurrentHostile()
            }, false);
        }

        private bool CurrentHostile()
        {
            return _selectedUnit >= 0 && _units != null && _selectedUnit < _units.Count && _units[_selectedUnit].Hostile;
        }

        private void ToggleHostile()
        {
            if (_selectedUnit < 0 || _units == null || _selectedUnit >= _units.Count) return;
            _units[_selectedUnit].Hostile = !_units[_selectedUnit].Hostile;
            Invalidate();
        }

        private static void Nudge(TextBox input, int delta, int min, int max)
        {
            int value;
            if (!int.TryParse(input.Text, out value)) value = min;
            value = Math.Max(min, Math.Min(max, value + delta));
            input.Text = value.ToString();
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            if (!Active) return;
            Point logical = ModifierNativeLayout.ToLogical(e.Location, ClientSize);
            string hit = HitAction(logical);
            int action = hit == null ? 0 : ActionId(hit);
            bool changed = action != _hoverAction;
            _hoverAction = action;
            _tooltipPoint = logical;
            int item = _activeTab == "items" ? ModifierNativeLayout.ItemIndexAt(logical) : -1;
            int unit = _activeTab == "units" ? ModifierNativeLayout.UnitIndexAt(logical) : -1;
            if (item != _hoverItem || unit != _hoverUnit) changed = true;
            _hoverItem = item;
            _hoverUnit = unit;
            if (changed) Invalidate();
        }

        protected override void OnMouseLeave(EventArgs e)
        {
            base.OnMouseLeave(e);
            if (_trackingLeave) return;
            _trackingLeave = true;
            _hoverAction = 0;
            _hoverItem = -1;
            _hoverUnit = -1;
            Invalidate();
            _trackingLeave = false;
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == 0x0201 && Active)
            {
                long packed = m.LParam.ToInt64();
                int x = (short)(packed & 0xFFFF);
                int y = (short)((packed >> 16) & 0xFFFF);
                int dragLeft = (int)(ClientSize.Width * (169.0 / ModifierNativeLayout.Width));
                int dragRight = (int)(ClientSize.Width * (610.0 / ModifierNativeLayout.Width));
                int dragHeight = (int)(ClientSize.Height * (40.0 / ModifierNativeLayout.Height));
                if (x >= dragLeft && x < dragRight && y >= 0 && y < dragHeight)
                {
                    ReleaseCapture();
                    SendMessage(Handle, 0x00A1, new IntPtr(2), IntPtr.Zero);
                    return;
                }
            }
            base.WndProc(ref m);
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (!Active || e.Button != MouseButtons.Left) return;
            Point logical = ModifierNativeLayout.ToLogical(e.Location, ClientSize);
            _pressedAction = HitAction(logical);
            _pressPoint = e.Location;
            if (_pressedAction != null)
            {
                Capture = true;
                Invalidate();
            }
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            if (!Active || e.Button != MouseButtons.Left) return;
            string action = _pressedAction;
            _pressedAction = null;
            Capture = false;
            if (action == null) return;
            Point logical = ModifierNativeLayout.ToLogical(e.Location, ClientSize);
            if (!string.Equals(action, HitAction(logical), StringComparison.Ordinal)) return;
            ExecuteAction(action);
        }

        protected override void OnMouseWheel(MouseEventArgs e)
        {
            base.OnMouseWheel(e);
            if (!Active || _hoverAction != 0) return;
            if (_activeTab == "items") ChangeItemPage(e.Delta > 0 ? -1 : 1, false, false);
            else if (_activeTab == "units") ChangeUnitPage(e.Delta > 0 ? -1 : 1, false, false);
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            base.OnKeyDown(e);
            if (e.KeyCode == Keys.Escape)
            {
                e.SuppressKeyPress = true;
                RequestClose();
            }
        }

        protected override void OnResize(EventArgs e)
        {
            base.OnResize(e);
            UpdateInputLayout();
            Invalidate();
        }

        protected override void OnDpiChanged(DpiChangedEventArgs e)
        {
            base.OnDpiChanged(e);
            UpdateInputLayout();
            Invalidate();
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (!_disposed && e.CloseReason == CloseReason.UserClosing)
            {
                e.Cancel = true;
                RequestClose();
                return;
            }
            base.OnFormClosing(e);
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing)
            {
                _disposed = true;
                _armTimer.Stop();
                _armTimer.Dispose();
                try { _tabSound?.Dispose(); } catch { }
                foreach (Image image in _backgrounds.Values) image.Dispose();
                _backgrounds.Clear();
                foreach (Image image in _icons.Values) image.Dispose();
                _icons.Clear();
                foreach (Image image in _unitFrames.Values) image.Dispose();
                _unitFrames.Clear();
                _unitFrame = null;
                _textFont.Dispose();
                _smallFont.Dispose();
                _tinyFont.Dispose();
                _statusFont.Dispose();
                _clip.Dispose();
                _ellipsis.Dispose();
                ClearCalls();
            }
            base.Dispose(disposing);
        }
    }
}
