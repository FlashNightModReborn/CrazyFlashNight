#nullable enable
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.Linq;
using System.Windows.Forms;
using CF7Launcher.Guardian.Hud.Loot;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal sealed class PlayerHudAllyWidget : PlayerHudWidgetBase, INativeHudPointerSnapshot
{
    private readonly LootIconCatalog? _icons;
    private readonly Font _font = NativeHudFonts.CreateRoleFont("native.player-info.body", 9f, FontStyle.Bold, GraphicsUnit.Pixel);
    private readonly StringFormat _label = new() { FormatFlags = StringFormatFlags.NoWrap, Trimming = StringTrimming.EllipsisCharacter };
    private readonly PlayerHudPortraitCache _portraits = new();
    private readonly PlayerHudTextCache _numbers = new();
    private readonly StringFormat _center = new(StringFormat.GenericTypographic)
        { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center, FormatFlags = StringFormatFlags.NoWrap };
    private readonly Dictionary<int,int> _flashes = new();
    private readonly HashSet<string> _requested = new(StringComparer.Ordinal);
    private IDollBakeSink? _bake;
    private PlayerHudAllyRoster? _seen;
    private RectangleF _tray;
    private long _epoch;
    private bool _open, _lastSuppressed;
    private int _page, _slots, _focus;
    private int _hoverSlot = -1;
    private readonly bool _observePaint = Environment.GetEnvironmentVariable("CF7_HUD_ALLY_PAINT_TRACE")=="1";
    private PlayerHudAllyRoster? _lastObserved;
    private const int PageSize = PlayerHudAllyLayout.PageSize;
    private PlayerHudAlly[] Rows => _seen?.Rows ?? Array.Empty<PlayerHudAlly>();
    private PlayerHudAlly[] Overflow => _seen?.Overflow ?? Array.Empty<PlayerHudAlly>();
    private RectangleF Drawer => PlayerHudAllyLayout.Drawer(_tray, Overflow.Length);
    private RectangleF Hint => new(_tray.X, _tray.Bottom+2, 158, 17);
    private RectangleF Cell(int slot) => PlayerHudAllyLayout.Cell(slot,_slots,_focus,_tray.Y);
    protected override PlayerHudGroups ConsumedGroups => PlayerHudGroups.Allies | PlayerHudGroups.Focus | PlayerHudGroups.Vitals;
    protected override bool HasContent => Rows.Length != 0 || Overflow.Length != 0;
    protected override RectangleF LogicalBounds => _open ? RectangleF.Union(_tray,Drawer) :
        _hoverSlot >= 0 ? RectangleF.Union(_tray,Hint) : _tray;
    public override bool WantsAnimationTick => Visible && Snapshot?.Vitals.Paused == false && _flashes.Count != 0;

    internal PlayerHudAllyWidget(Control anchor, PlayerHudController controller, LootIconCatalog? icons) : base(anchor,controller)
    {
        _icons=icons;
        OnStateChanged();
    }

    protected override void OnStateChanged()
    {
        var s=Snapshot;
        var next=s?.Allies;
        var rows=next?.Rows ?? Array.Empty<PlayerHudAlly>();
        var overflow=next?.Overflow ?? Array.Empty<PlayerHudAlly>();
        int slots=rows.Length==0 ? 0 : rows.Max(a=>a.Slot)+1;
        int focus=s?.TargetList.Length??0;
        float top=focus==0 ? 0 : PlayerHudFocusTargetWidget.TopLeftBottomFor(0,focus,false,rows.Length)+6;
        var tray=PlayerHudAllyLayout.Tray(slots,focus,top,overflow.Length>0);
        var changes = new HashSet<int>();
        if (s?.Vitals.Paused == true || Suppressed)
        {
            changes.UnionWith(_flashes.Keys);
            _flashes.Clear();
        }
        bool epochChanged=_epoch!=(s?.Epoch??0);
        bool geometry=epochChanged || tray!=_tray || slots!=_slots || focus!=_focus || Suppressed!=_lastSuppressed;
        if (epochChanged) { _open=false; _page=0; _hoverSlot=-1; _flashes.Clear(); _requested.Clear(); }
        if (!geometry && ReferenceEquals(next,_seen))
        {
            if (changes.Count != 0) NotifyVisualChange(Damage(changes,true));
            return;
        }
        var previous=Rows;
        var previousOverflow=Overflow;
        _seen=next; _epoch=s?.Epoch??0; _slots=slots; _focus=focus; _tray=tray; _lastSuppressed=Suppressed;
        if (Overflow.Length==0) _open=false;
        _page=Math.Min(_page,Math.Max(0,(Overflow.Length-1)/PageSize));
        if (_hoverSlot>=0 && !rows.Any(a=>a.Slot==_hoverSlot)) _hoverSlot=-1;
        ReportBounds();
        foreach(var old in previous)
        {
            var current=Array.Find(rows,a=>a.Slot==old.Slot);
            if (current==old) continue;
            changes.Add(old.Slot);
            if (!epochChanged && current!=null && old.Id==current.Id && old.Generation==current.Generation && current.Hp<old.Hp &&
                !PlayerHudMotionSettings.ReducedMotion && !PlayerHudMotionSettings.StaticFeedback && s?.Vitals.Paused==false)
                _flashes[old.Slot]=180;
            else _flashes.Remove(old.Slot);
        }
        foreach(var row in rows)
            if (!Array.Exists(previous,a=>a.Slot==row.Slot)) changes.Add(row.Slot);
        RefreshPortraits();
        if (geometry || !previousOverflow.SequenceEqual(Overflow) || _hoverSlot>=0)
            NotifyVisualChange(HudRepaintRegions.AuthoritativeWidget);
        else if (changes.Count>0) NotifyVisualChange(Damage(changes,true));
    }

    internal void SetPortraitBakeSink(IDollBakeSink? sink) { _bake=sink; _requested.Clear(); RefreshPortraits(); }
    private void RefreshPortraits()
    {
        if (_bake==null) return;
        _requested.RemoveWhere(k=>!Rows.Any(a=>a.PortraitKey==k));
        foreach(var row in Rows)
            if(row.Doll!=null && _requested.Add(row.PortraitKey))
            {
                try { _bake.EnsurePortrait(row.Doll,row.PortraitKey); }
                catch (Exception ex) { _requested.Remove(row.PortraitKey); LogManager.Log("event=ally_portrait_retry reason=" + ex.GetType().Name); }
            }
    }
    internal void NotifyPortraitReady(string key)
    {
        var slots=Rows.Where(a=>a.PortraitKey==key).Select(a=>a.Slot).ToArray();
        if (slots.Length>0) NotifyVisualChange(Damage(slots,false));
    }
    private HudRepaintRegions Damage(IEnumerable<int> slots,bool authority)
    {
        var view=Viewport;float k=Scale;
        return new HudRepaintRegions(slots.Select(slot=>{
            var r=Cell(slot);
            return Rectangle.FromLTRB(view.X+(int)Math.Floor(r.Left*k)-2,view.Y+(int)Math.Floor(r.Top*k)-2,
                view.X+(int)Math.Ceiling(r.Right*k)+2,view.Y+(int)Math.Ceiling(r.Bottom*k)+2);
        }).ToArray(),authority);
    }
    public override void Tick(int deltaMs)
    {
        if (!WantsAnimationTick || deltaMs<=0) return;
        var slots=_flashes.Keys.ToArray();
        foreach (int slot in slots)
            if ((_flashes[slot]-=deltaMs)<=0) _flashes.Remove(slot);
        NotifyVisualChange(Damage(slots,false));
    }

    private void ReportBounds() => HudZoneLayout.ReportAllyBottom(HasContent && !Suppressed ? LogicalBounds.Bottom : 0);
    private static string RoleLabel(string role) => role switch { "merc" => "佣兵", "pet" => "战宠", _ => "友军" };

    private static Color HealthColor(PlayerHudAlly a) =>
        a.Down || a.Hp/a.HpMax<0.3 ? Color.FromArgb(224,80,66) :
        a.Hp/a.HpMax<=0.6 ? Color.FromArgb(207,155,72) : Color.FromArgb(141,163,166);
    private static void Plate(Graphics g, RectangleF r)
    {
        using var bg=new LinearGradientBrush(r,Color.FromArgb(237,35,40,42),Color.FromArgb(238,10,13,14),LinearGradientMode.Vertical);
        using var edge=new Pen(Color.FromArgb(160,172,183,184),0.75f);
        PointF[] corners={new(r.X+2,r.Y),new(r.Right-5,r.Y),new(r.Right,r.Y+5),new(r.Right,r.Bottom-2),new(r.Right-2,r.Bottom),new(r.X,r.Bottom),new(r.X,r.Y+2)};
        g.FillPolygon(bg,corners);g.DrawPolygon(edge,corners);
        using var sheen=new Pen(Color.FromArgb(41,233,239,239),.75f);
        g.DrawLine(sheen,r.Left+3,r.Top+1,r.Right-7,r.Top+1);
    }
    private void Text(Graphics g,string text,RectangleF bounds,Brush brush) => g.DrawString(text,_font,brush,bounds,_label);
    protected override void PaintLogical(Graphics g)
    {
        if (_observePaint && !ReferenceEquals(_lastObserved,_seen))
        {
            _lastObserved=_seen;
            LogManager.Log($"event=ally_hud_paint epoch={_epoch} seq={Snapshot?.Sequence} rows={Rows.Length} overflow={Overflow.Length} slots="+
                string.Join(",",Rows.Select(a=>$"{a.Slot}/{a.Role}/{a.Id}/{a.Generation}/{a.Hp.ToString(CultureInfo.InvariantCulture)}")));
        }
        bool hasOverflow = Overflow.Length > 0;
        int rowCount = Math.Max(hasOverflow ? 1 : 0, PlayerHudAllyLayout.RowCount(_slots, _focus));
        using var blade = new SolidBrush(Color.FromArgb(220,154,162,160));
        for (int row = 0; row < rowCount; row++)
        {
            var plate = PlayerHudAllyLayout.RowTray(row, _slots, _focus, _tray.Y, hasOverflow);
            if (plate.IsEmpty || !g.IsVisible(plate)) continue;
            Plate(g, plate);
            g.FillRectangle(blade, plate.X + 1.4f, plate.Y + 2.2f, 2f, plate.Height - 4.4f);
        }
        bool dense=PlayerHudAllyLayout.Dense(_slots,_focus);
        foreach (var a in Rows)
        {
            var r=Cell(a.Slot);
            if (!g.IsVisible(r)) continue;
            var face=dense ? new RectangleF(r.X,r.Y,r.Width,19f) : new RectangleF(r.X+3.5f,r.Y+1,20,20);
            double ratio = Math.Clamp(a.Hp / a.HpMax,0,1);
            bool critical = a.Down || ratio < .30;
            bool calm = !a.Down && ratio > .60;
            if (!dense && a.Slot > 0)
            {
                using var divider = new Pen(Color.FromArgb(72,200,208,206),.75f);
                g.DrawLine(divider,r.X+1,r.Top+1,r.X-1,r.Bottom-1);
            }
            g.FillRectangle(Brushes.Black,face);
            var portrait=a.PortraitKey;
            if (_icons!=null && portrait.Length!=0 &&
                (_icons.TryGet(portrait,out var pictures) || (a.Doll==null && _icons.TryGet("敌人-"+portrait,out pictures))) && pictures?.First is {} image)
                _portraits.Draw(g,image,face,Scale,calm,dense);
            else g.DrawString(StringInfo.GetNextTextElement(a.Name),_font,Brushes.Gainsboro,face,_center);
            if (a.Role == "pet")
                g.FillRectangle(Brushes.Silver,face.Left+.5f,dense ? face.Top+.5f : face.Bottom-3,2.5f,2.5f);
            float barX=dense?r.X:face.Right+4.5f;
            var track=new RectangleF(barX,dense ? r.Bottom-3.6f : r.Bottom-4f,r.Right-barX,dense ? 3.2f : 3.4f);
            g.FillRectangle(Brushes.Black,track);
            using var color=new SolidBrush(HealthColor(a));
            float fill=track.Width*(float)ratio;
            if (fill > 0)
                g.FillPolygon(color,new PointF[] {new(track.X+Math.Min(1,fill),track.Top),new(track.X+fill,track.Top),
                    new(track.X+Math.Max(0,fill-1),track.Bottom),new(track.X,track.Bottom)});
            if (a.ShieldMax>0 && a.Shield>0) g.FillRectangle(Brushes.SteelBlue,track.X,track.Y-(dense ? 1.4f : 1.5f),track.Width*(float)Math.Clamp(a.Shield/a.ShieldMax,0,1),dense ? 1.2f : 1.25f);
            if (!dense)
            {
                Text(g,a.Name,new RectangleF(barX,r.Y,Math.Max(1,track.Width-29),14),Brushes.Gainsboro);
                string percent=Math.Round(ratio*100,MidpointRounding.AwayFromZero).ToString("0",CultureInfo.InvariantCulture)+"%";
                _numbers.DrawRight(g,percent,r.Right-2,r.Y+10,9.2f,Scale,26,color.Color);
            }
            if (critical)
            {
                NativeHudTheme.DrawSlotBrackets(g,face,Color.FromArgb(255,102,86),3.6f,1);
                var tag=new RectangleF(face.Right-7.5f,face.Top,7.5f,8.5f);
                using var red=new SolidBrush(Color.FromArgb(217,43,34));
                g.FillRectangle(red,tag);
                g.DrawString(a.Down ? "×" : "!",_font,Brushes.WhiteSmoke,tag,_center);
            }
            else if (!calm)
                g.FillPolygon(Brushes.Goldenrod,new PointF[] {new(face.Right-4.2f,face.Top),new(face.Right,face.Top),new(face.Right,face.Top+4.2f)});
            if (a.Protected && !critical) Text(g,"◆",face,Brushes.Gold);
            if (_flashes.TryGetValue(a.Slot,out int remaining))
            {
                using var flash=new Pen(Color.FromArgb(40+remaining*200/180,253,202,150));
                g.DrawRectangle(flash,r.X,r.Y,r.Width-1,r.Height-1);
            }
        }
        if (Overflow.Length>0)
        {
            var t=PlayerHudAllyLayout.Toggle(_tray.Y);
            using var capsule=new GraphicsPath();
            capsule.AddRoundedRectangle(t,new SizeF(2.6f,2.6f));
            using var metal=new SolidBrush(Color.FromArgb(230,20,25,27));
            using var rim=new Pen(Color.FromArgb(140,123,133,132),.8f);
            g.FillPath(metal,capsule);
            g.DrawPath(rim,capsule);
            g.DrawString("+"+Overflow.Length,_font,Overflow.Any(a=>a.Down || a.Hp/a.HpMax<.3)?Brushes.Coral:Brushes.Gainsboro,t,_center);
        }
        if (_open)
        {
            var panel=Drawer;Plate(g,panel);
            Text(g,$"其余友军  {_page+1}/{1+(Overflow.Length-1)/PageSize}   ›",new(panel.X+4,panel.Y+2,panel.Width-7,16),Brushes.Gainsboro);
            int i=0;
            foreach (var a in Overflow.Skip(_page*PageSize).Take(PageSize))
            {
                using var b=new SolidBrush(HealthColor(a));
                Text(g,$"{a.Name}  {Math.Floor(a.Hp)}/{Math.Floor(a.HpMax)}",new(panel.X+4,panel.Y+18+14*i++,panel.Width-7,14),b);
            }
        }
        else if (Array.Find(Rows,a=>a.Slot==_hoverSlot) is {} hover)
        {
            var hint=Hint;Plate(g,hint);
            Text(g,$"{RoleLabel(hover.Role)} {hover.Name}  {Math.Floor(hover.Hp)}/{Math.Floor(hover.HpMax)}",new(hint.X+5,hint.Y+2,hint.Width-9,hint.Height-4),Brushes.Gainsboro);
        }
    }
    public object? CapturePointerTarget(Point screen)
    {
        if (!Visible) return null;
        var p=Logical(screen);
        if (Overflow.Length>0 && PlayerHudAllyLayout.Toggle(_tray.Y).Contains(p)) return (_epoch,"toggle",_open);
        if (_open && Drawer.Contains(p)) return (_epoch,"page",_page);
        foreach (var row in Rows) if (Cell(row.Slot).Contains(p)) return (_epoch,row.Id,row.Generation,row.Slot);
        return null;
    }
    public override bool TryHitTest(Point screenPt) => CapturePointerTarget(screenPt)!=null;
    public override void OnMouseEvent(MouseEventArgs e, MouseEventKind kind)
    {
        var p=Logical(new Point(e.X,e.Y));
        if (kind==MouseEventKind.Click && e.Button==MouseButtons.Left && Overflow.Length>0)
        {
            if (PlayerHudAllyLayout.Toggle(_tray.Y).Contains(p)) { _open=!_open; _page=0; }
            else if (_open && Drawer.Contains(p)) _page=(_page+1)%(1+(Overflow.Length-1)/PageSize);
            else return;
            ReportBounds(); NotifyVisualChange(EventArgs.Empty); return;
        }
        if (kind is not (MouseEventKind.Move or MouseEventKind.Enter or MouseEventKind.Cancel or MouseEventKind.Leave)) return;
        int slot = kind==MouseEventKind.Cancel || kind==MouseEventKind.Leave ? -1 : Array.Find(Rows,a=>Cell(a.Slot).Contains(p))?.Slot??-1;
        if (slot==_hoverSlot) return;
        _hoverSlot=slot; ReportBounds(); NotifyVisualChange(EventArgs.Empty);
    }
    public override void Dispose()
    {
        HudZoneLayout.ReportAllyBottom(0);
        _portraits.Dispose();
        _numbers.Dispose();
        _font.Dispose();
        _label.Dispose();
        _center.Dispose();
        base.Dispose();
    }
}
