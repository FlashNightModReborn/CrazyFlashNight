#nullable enable
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.Collections.Generic;
using System.Windows.Forms;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal sealed class PlayerHudBuffWidget : PlayerHudWidgetBase, INativeHudPointerSnapshot
{
    private readonly Font _label = NativeHudFonts.CreateRoleFont("native.player-info.body", 9.2f, FontStyle.Bold, GraphicsUnit.Pixel);
    private readonly Font _small = NativeHudFonts.CreateRoleFont("native.player-info.body", 8, FontStyle.Bold, GraphicsUnit.Pixel);
    private readonly Font _urgent = NativeHudFonts.CreateRoleFont("native.player-info.body", 8.6f, FontStyle.Bold, GraphicsUnit.Pixel);
    private readonly StringFormat _center = new(StringFormat.GenericTypographic)
    { Alignment=StringAlignment.Center, LineAlignment=StringAlignment.Center, FormatFlags=StringFormatFlags.NoWrap, Trimming=StringTrimming.EllipsisCharacter };
    private readonly StringFormat _right = new(StringFormat.GenericTypographic)
    { Alignment=StringAlignment.Far, LineAlignment=StringAlignment.Center, FormatFlags=StringFormatFlags.NoWrap };
    private readonly Dictionary<(string, Font, SizeF, bool), GraphicsPath> _outlines = new();
    private readonly Pen _stroke = new(Color.FromArgb(240,6,8,10), 1.9f) { LineJoin = LineJoin.Round };
    private long _epoch;
    private int _bank;
    private readonly Font _tag=NativeHudFonts.CreateRoleFont("native.player-info.body",6.1f,FontStyle.Bold,GraphicsUnit.Pixel);
    private Bitmap? _neutralPlate, _priorityPlate;
    private int _platePixels;
    private bool _hasCold, _open, _wasSuppressed;
    private int _page;
    private PlayerHudTarget? _press, _hover;
    private bool _upMatches;
    private PlayerHudBuffCard[] _cards = Array.Empty<PlayerHudBuffCard>();
    internal const double BuffExpiringFrames = 90;
    internal static readonly Color BuffBenefitRail = Color.FromArgb(86,136,143), BuffHarmRail = NativeHudTheme.AnchorCoral, BuffNeutralRail = Color.FromArgb(150,154,152);
    protected override PlayerHudGroups ConsumedGroups => PlayerHudGroups.Buffs | PlayerHudGroups.ColdSkills | PlayerHudGroups.Loadout;
    protected override bool HasContent => _cards.Length > 0;
    protected override RectangleF LogicalBounds => PlayerHudBuffLayout.Bounds(_cards.Length,_hasCold,_open);
    private int Shown => PlayerHudBuffLayout.RailCount(_cards.Length,_hasCold);
    internal int CurrentPage => _page;
    internal static RectangleF SlotRect(int index) => PlayerHudBuffLayout.SlotRect(index);
    internal PlayerHudBuffWidget(Control anchor, PlayerHudController controller) : base(anchor,controller) { OnStateChanged(); }

    protected override void OnStateChanged()
    {
        var s=Snapshot;
        var cards=s?.BuffCards ?? Array.Empty<PlayerHudBuffCard>();
        bool cold=PlayerHudBottomWidget.VisibleColdSkills(s).Length!=0;
        long epoch=s?.Epoch??0;
        int bank=s?.Loadout.Bank??0;
        if (ReferenceEquals(cards,_cards) && cold==_hasCold && epoch==_epoch && _wasSuppressed==Suppressed &&
            (_bank==bank || !Array.Exists(cards,c=>c.Source?.Kind=="drug"))) return;
        if (!Suppressed && !_wasSuppressed && epoch==_epoch && bank==_bank && cold==_hasCold &&
            cards.Length==_cards.Length && TryUpdateSingleCard(cards)) return;
        _bank=bank;
        if (epoch!=_epoch || Suppressed) { _open=false; _page=0; }
        if (_cards.Length!=cards.Length || cold!=_hasCold || epoch!=_epoch) CancelPress();
        _cards=cards; _hasCold=cold; _epoch=epoch; _wasSuppressed=Suppressed;
        if (Shown>=cards.Length) _open=false;
        _page=_open ? Math.Min(_page,PlayerHudBuffLayout.PageCount(cards.Length)-1) : 0;
        if (_hover is {} h && (h.Epoch!=epoch || !Visible || h.Slot>=cards.Length ||
            h.Key!=cards[h.Slot].Id || !(h.Slot<Shown && h.Anchor==SlotRect(h.Slot) ||
                _open && h.Slot/PlayerHudBuffLayout.PageSize==_page && h.Anchor==PlayerHudBuffLayout.DrawerSlot(h.Slot%PlayerHudBuffLayout.PageSize)))) ClearHover();
        base.OnStateChanged();
    }

    // List order and hit targets stay stable. Retain changes off the current page for the next navigation.
    private bool TryUpdateSingleCard(PlayerHudBuffCard[] cards)
    {
        int changed=-1, shown=Shown, first=_page*PlayerHudBuffLayout.PageSize;
        for (int i=0;i<cards.Length;i++)
        {
            var old=_cards[i]; var next=cards[i];
            if (old.Id!=next.Id) return false;
            bool inDrawer=_open && i>=first && i<first+PlayerHudBuffLayout.PageSize;
            if (i>=shown && !inDrawer || SameCardInk(old,next)) continue;
            if (changed>=0) return false;
            changed=i;
        }
        _cards=cards;
        if (changed<0) return true;
        var viewport=Viewport;
        float scale=viewport.Height/576f;
        if (scale<=0) { base.OnStateChanged(); return true; }
        Rectangle Damage(RectangleF r)
        {
            int pad=(int)Math.Ceiling(scale*.5f+.5f);
            return Rectangle.FromLTRB(viewport.Left+(int)Math.Floor(r.Left*scale)-pad,
                viewport.Top+(int)Math.Floor(r.Top*scale)-pad,
                viewport.Left+(int)Math.Ceiling(r.Right*scale)+pad,
                viewport.Top+(int)Math.Ceiling(r.Bottom*scale)+pad);
        }
        bool rail=changed<shown;
        bool drawer=_open && changed>=first && changed<first+PlayerHudBuffLayout.PageSize;
        var regions=new Rectangle[(rail?1:0)+(drawer?1:0)];
        if(rail)
        {
            var rect=Damage(SlotRect(changed));
            rect.Height=Math.Min(rect.Bottom,viewport.Top+(int)Math.Ceiling(512f*scale))-rect.Top;
            regions[0]=rect;
        }
        if(drawer)regions[^1]=Damage(PlayerHudBuffLayout.DrawerSlot(changed%PlayerHudBuffLayout.PageSize));
        NotifyVisualChange(new HudRepaintRegions(regions));
        return true;
    }

    private static bool SameCardInk(PlayerHudBuffCard a,PlayerHudBuffCard b) =>
        a.Role==b.Role && a.Name==b.Name && a.Polarity==b.Polarity && a.Stacks==b.Stacks && a.Source==b.Source &&
        a.DisplayTimed==b.DisplayTimed && a.DisplayTotal==b.DisplayTotal && a.DisplayRemaining==b.DisplayRemaining &&
        a.Activation?.Active==b.Activation?.Active;

    private static void Plate(Graphics g, RectangleF r, Color top, Color bottom, Color edge, float chamfer)
    {
        var points=new PointF[] {new(r.Left,r.Top),new(r.Right-chamfer,r.Top),new(r.Right,r.Top+chamfer),
            new(r.Right,r.Bottom),new(r.Left,r.Bottom)};
        using var fill=new LinearGradientBrush(r,top,bottom,LinearGradientMode.Vertical);
        using var pen=new Pen(edge,.72f);
        g.FillPolygon(fill,points);g.DrawPolygon(pen,points);
    }
    protected override void PaintLogical(Graphics g)
    {
        int n=Shown;
        if(n==0)return;
        var bed=PlayerHudBuffLayout.Bed(n);
        if(g.IsVisible(bed))
        {
            Plate(g,bed,Color.FromArgb(165,24,29,31),Color.FromArgb(165,8,11,12),Color.FromArgb(64,214,217,215),4);
            for(int i=0;i<n;i++) DrawCard(g,i,SlotRect(i),false);
        }
        if(n==_cards.Length)return;
        var toggle=PlayerHudBuffLayout.Toggle(_hasCold);
        if(g.IsVisible(toggle))
        {
            Plate(g,toggle,Color.FromArgb(40,45,47),Color.FromArgb(17,20,21),NativeHudTheme.AnchorRim,4.5f);
            NativeHudTheme.DrawSlotBrackets(g,toggle,NativeHudTheme.AnchorRim,4,.9f);
            g.DrawString("+"+(_cards.Length-n),_label,Brushes.WhiteSmoke,new RectangleF(toggle.X,toggle.Y+1,toggle.Width,15),_center);
            g.DrawString(_open?"收起 ▾":"全部 ▴",_small,Brushes.Silver,new RectangleF(toggle.X,toggle.Y+14,toggle.Width,11),_center);
        }
        var drawer=PlayerHudBuffLayout.Drawer;
        if(!_open || !g.IsVisible(drawer))return;
        Plate(g,drawer,Color.FromArgb(249,34,39,40),Color.FromArgb(250,12,15,16),NativeHudTheme.AnchorRim,8);
        using var blade=new SolidBrush(Color.FromArgb(220,154,162,160));
        g.FillRectangle(blade,drawer.X+1.5f,drawer.Y+1.5f,2.2f,drawer.Height-3);
        g.DrawLine(Pens.Black,drawer.Left+4,drawer.Bottom-1.5f,drawer.Right-1,drawer.Bottom-1.5f);
        g.DrawString("全部状态 · 共 "+_cards.Length+" 项",_label,Brushes.WhiteSmoke,drawer.X+10,drawer.Y+4);
        g.DrawString("细银顶线＝首行已显示（"+n+" 项）",_small,Brushes.Silver,drawer.X+128,drawer.Y+5);
        int pages=PlayerHudBuffLayout.PageCount(_cards.Length);
        g.DrawString((_page+1)+" / "+pages,_small,Brushes.WhiteSmoke,new RectangleF(drawer.Right-51,drawer.Top+2,33,16),_center);
        g.DrawString("◂",_label,_page>0?Brushes.WhiteSmoke:Brushes.DimGray,PlayerHudBuffLayout.PreviousPageRect(_cards.Length),_center);
        g.DrawString("▸",_label,_page+1<pages?Brushes.WhiteSmoke:Brushes.DimGray,PlayerHudBuffLayout.NextPageRect(_cards.Length),_center);
        int first=_page*PlayerHudBuffLayout.PageSize;
        for(int j=0;j<PlayerHudBuffLayout.PageSize && first+j<_cards.Length;j++)
            DrawCard(g,first+j,PlayerHudBuffLayout.DrawerSlot(j),first+j<n);
    }
    private readonly Dictionary<(GraphicsPath Path,int Ink,float Scale,float X,float Y),Bitmap> _stamps=new();
    private long _stampBytes;

    private void Outlined(Graphics g,string value,Font font,SolidBrush fill,RectangleF box,bool right=false)
    {
        var key=(value,font,box.Size,right);
        if (!_outlines.TryGetValue(key,out var path))
        {
            if (_outlines.Count>=256) ClearOutlines();
            path=new GraphicsPath();
            path.AddString(value,font.FontFamily,(int)font.Style,font.Size,new RectangleF(PointF.Empty,box.Size),right?_right:_center);
            _outlines.Add(key,path);
        }
        using var matrix=g.Transform;
        float scale=matrix.Elements[0];
        var point=new[]{box.Location};
        matrix.TransformPoints(point);
        int left=(int)Math.Floor(point[0].X),top=(int)Math.Floor(point[0].Y);
        float dx=point[0].X-left,dy=point[0].Y-top;
        int pad=(int)Math.Ceiling(2*scale)+1;
        int w=(int)Math.Ceiling(box.Width*scale)+2*pad+1;
        int h=(int)Math.Ceiling(box.Height*scale)+2*pad+1;
        var stampKey=(path,fill.Color.ToArgb(),scale,dx,dy);
        var saved=g.Save();
        try
        {
            if ((long)w*h*4>256*1024)
            {
                g.TranslateTransform(box.X,box.Y);
                g.DrawPath(_stroke,path); g.FillPath(fill,path);
                return;
            }
            if (!_stamps.TryGetValue(stampKey,out var tile))
            {
                if (_stampBytes+(long)w*h*4>1024*1024) ClearStamps();
                tile=new Bitmap(w,h,System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
                using var local=Graphics.FromImage(tile);
                local.SmoothingMode=g.SmoothingMode;
                local.TranslateTransform(pad+dx,pad+dy);
                local.ScaleTransform(scale,scale);
                local.DrawPath(_stroke,path); local.FillPath(fill,path);
                _stamps.Add(stampKey,tile); _stampBytes+=(long)w*h*4;
            }
            g.ResetTransform();
            g.DrawImageUnscaled(tile,left-pad,top-pad);
        }
        finally { g.Restore(saved); }
    }
    private void ClearStamps()
    {
        foreach (var tile in _stamps.Values) tile.Dispose();
        _stamps.Clear(); _stampBytes=0;
    }
    private void ClearOutlines()
    {
        ClearStamps();
        foreach (var path in _outlines.Values) path.Dispose();
        _outlines.Clear();
    }
    private void DrawCard(Graphics g,int index,RectangleF r,bool marked)
    {
        var inkBounds=RectangleF.Inflate(r,1,1);
        if(marked) inkBounds=RectangleF.FromLTRB(inkBounds.Left,r.Top-3.5f,inkBounds.Right,inkBounds.Bottom);
        if(!g.IsVisible(inkBounds))return;
        var card=_cards[index];
        bool timed=card.DisplayTimed, harm=card.Polarity=="harm", hovered=_hover?.Anchor==r;
        double seconds=timed?card.DisplayRemaining*PlayerHudCooldownText.StepMilliseconds/1000:0;
        bool warning=timed && seconds<=5, urgent=timed && seconds<=3;
        string role=card.Role.Length>0?card.Role:card.Id;
        bool priority=role=="poison" || urgent && (harm || role=="eres");
        var rail=harm?BuffHarmRail:card.Polarity=="benefit"?BuffBenefitRail:BuffNeutralRail;
        PaintCardPlate(g,r,priority);
        using var edge=new Pen(priority?BuffHarmRail:Color.FromArgb(93,150,158,156),.7f);
        g.DrawRectangle(edge,r.X,r.Y,r.Width,r.Height);
        if(timed && card.DisplayTotal>0)
        {
            float elapsed=(r.Height-4.2f)*(1-(float)Math.Clamp(card.DisplayRemaining/card.DisplayTotal,0,1));
            if(elapsed>.6f){using var veil=new SolidBrush(Color.FromArgb(128,0,0,0));g.FillRectangle(veil,r.X+1,r.Y+1.2f,r.Width-2,elapsed);}
        }
        string name=string.IsNullOrEmpty(card.Name)?"状态":card.Name;
        var chars=new StringInfo(name);
        if(chars.LengthInTextElements>2)name=chars.SubstringByTextElements(0,2);
        using var text=new SolidBrush(priority?Color.FromArgb(255,198,188):harm?Color.FromArgb(240,200,192):Color.FromArgb(226,231,229));
        string tag=card.Source is { Kind:"drug" } source && source.Slot/4!=_bank
            ? (source.Slot<4?"A":"B")+(7+source.Slot%4)%10 : card.Stacks>1?"×"+card.Stacks:"";
        if (tag.Length>0)
        {
            g.FillRectangle(Brushes.Black,r.X+.9f,r.Y+.6f,11.1f,6.4f);
            Outlined(g,tag,_tag,(SolidBrush)Brushes.Gainsboro,new RectangleF(r.X+1,r.Y+.1f,11,7));
            if (card.Stacks>1 && tag[0]!='×')
            {
                g.FillRectangle(Brushes.Black,r.X+13.2f,r.Y+.8f,11.8f,6.2f);
                Outlined(g,"×"+card.Stacks,_tag,(SolidBrush)Brushes.WhiteSmoke,new RectangleF(r.X+13,r.Y+.1f,11.6f,7),true);
            }
        }
        var labelRect=new RectangleF(r.X+1,r.Y+(timed?(tag.Length>0?6.1f:3.5f):(tag.Length>0?7f:5f)),r.Width-2,10);
        Outlined(g,name,_label,text,labelRect);
        {
            string time=timed?Countdown(card.DisplayRemaining):"常驻";
            using var ink=new SolidBrush(warning?Color.FromArgb(255,210,117):Color.FromArgb(205,212,210));
            var rect=new RectangleF(r.X+1,r.Bottom-11.3f,r.Width-3,9.3f);
            Outlined(g,time,urgent?_urgent:_small,ink,rect,true);
        }
        NativeHudTheme.DrawSlotBrackets(g,r,hovered?Color.WhiteSmoke:priority?BuffHarmRail:NativeHudTheme.AnchorRim,4,.9f);
        using var strip=new SolidBrush(warning?NativeHudTheme.AnchorAmber:rail);
        g.FillRectangle(strip,r.X+2,r.Bottom-2.6f,r.Width-4,1.7f);
        if(harm && !priority)
        {
            using var coral=new SolidBrush(BuffHarmRail);
            g.FillPolygon(coral,[new PointF(r.Right-4.8f,r.Y+1.2f),new(r.Right-1.2f,r.Y+1.2f),new(r.Right-1.2f,r.Y+4.8f)]);
        }
        if(urgent)g.FillRectangle(Brushes.LightCoral,r.X+1,r.Bottom-4,2.4f,2.4f);
        if(card.Activation?.Active==true){using var p=new Pen(BuffBenefitRail);g.DrawLine(p,r.Right-7,r.Y+1.4f,r.Right-1.5f,r.Y+1.4f);}
        if(marked)g.DrawLine(Pens.Silver,r.Left+4,r.Top-2.6f,r.Right-4,r.Top-2.6f);
    }
    internal static string Countdown(double frames)
    {
        double seconds=frames*PlayerHudCooldownText.StepMilliseconds/1000;
        return (seconds<=3 ? seconds.ToString("0.0",CultureInfo.InvariantCulture) :
            Math.Ceiling(seconds).ToString("0",CultureInfo.InvariantCulture))+"s";
    }
    private void PaintCardPlate(Graphics g,RectangleF r,bool priority)
    {
        int pixels=Math.Clamp((int)Math.Ceiling(26*Scale),1,256);
        if (_platePixels!=pixels) { _neutralPlate?.Dispose();_priorityPlate?.Dispose();_neutralPlate=_priorityPlate=null;_platePixels=pixels; }
        ref var plate=ref (priority?ref _priorityPlate:ref _neutralPlate);
        if (plate==null)
        {
            plate=new Bitmap(pixels,pixels,System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
            using var local=Graphics.FromImage(plate);
            var box=new Rectangle(0,0,pixels,pixels);
            using var fill=new LinearGradientBrush(box,priority?Color.FromArgb(58,31,28):Color.FromArgb(36,42,44),
                priority?Color.FromArgb(27,14,14):Color.FromArgb(14,17,19),LinearGradientMode.Vertical);
            local.FillRectangle(fill,box);
        }
        g.DrawImage(plate,r);
    }
    private PlayerHudTarget? Hit(Point screen)
    {
        if(!Visible || !Controller.CanInteract || Snapshot is not {} s || Scale<=0)return null;
        var p=Logical(screen);
        PlayerHudTarget Card(int i,RectangleF r) => new("buff",i,_cards[i].Id,_epoch,0,s.Loadout.Bank,r,Controller.Generation,s.Vitals.Paused);
        PlayerHudTarget Button(string kind,int value,RectangleF r) => new(kind,value,$"{_open}:{_page}:{_cards.Length}:{Shown}",_epoch,0,s.Loadout.Bank,r,Controller.Generation,s.Vitals.Paused);
        if(_open && PlayerHudBuffLayout.Drawer.Contains(p))
        {
            int first=_page*PlayerHudBuffLayout.PageSize;
            for(int i=first;i<Math.Min(first+PlayerHudBuffLayout.PageSize,_cards.Length);i++)
            {var r=PlayerHudBuffLayout.DrawerSlot(i-first);if(r.Contains(p))return Card(i,r);}
            var prev=PlayerHudBuffLayout.PreviousPageRect(_cards.Length);var next=PlayerHudBuffLayout.NextPageRect(_cards.Length);
            if(_page>0 && prev.Contains(p))return Button("buffPage",_page-1,prev);
            if(_page+1<PlayerHudBuffLayout.PageCount(_cards.Length) && next.Contains(p))return Button("buffPage",_page+1,next);
        }
        for(int i=0;i<Shown;i++){var r=SlotRect(i);if(r.Contains(p))return Card(i,r);}
        var toggle=PlayerHudBuffLayout.Toggle(_hasCold);
        return Shown<_cards.Length && toggle.Contains(p)?Button("buffDrawer",0,toggle):null;
    }
    public override bool TryHitTest(Point p)=>Hit(p)!=null;
    public object? CapturePointerTarget(Point p)=>Hit(p);
    public bool NeedsPointerClick=>Shown<_cards.Length;
    public override void OnMouseEvent(MouseEventArgs e,MouseEventKind kind)
    {
        if(kind is MouseEventKind.Cancel or MouseEventKind.Leave){CancelPress();ClearHover();return;}
        var target=Hit(new Point(e.X,e.Y));
        if(kind is MouseEventKind.Move or MouseEventKind.Enter)
        {
            if(target?.Kind!="buff"){ClearHover();return;}
            if(_hover==target)return;
            _hover=target;Controller.ShowTooltip(target);Repaint();return;
        }
        if(e.Button!=MouseButtons.Left)return;
        if(kind==MouseEventKind.Down){_press=target?.Kind is "buffDrawer" or "buffPage"?target:null;_upMatches=false;}
        if(kind==MouseEventKind.Up)_upMatches=_press!=null && _press==target;
        if(kind==MouseEventKind.Click)
        {
            if(_upMatches && target!=null && _press==target)
            {
                ClearHover();
                if(target.Kind=="buffDrawer"){_open=!_open;_page=0;}else _page=target.Slot;
                base.OnStateChanged();
            }
            CancelPress();
        }
    }
    private void CancelPress(){_press=null;_upMatches=false;}
    private void ClearHover(){if(_hover==null)return;_hover=null;Controller.HideTooltip();Repaint();}
    public override void SetHostSuppressed(bool value){if(value){CancelPress();ClearHover();}base.SetHostSuppressed(value);}
    public override void Dispose(){ClearHover();ClearOutlines();_stroke.Dispose();_neutralPlate?.Dispose();_priorityPlate?.Dispose();_tag.Dispose();_label.Dispose();_small.Dispose();_urgent.Dispose();_center.Dispose();_right.Dispose();base.Dispose();}
}
