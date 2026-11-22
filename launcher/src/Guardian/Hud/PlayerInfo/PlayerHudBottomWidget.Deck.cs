#nullable enable
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Globalization;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

internal sealed partial class PlayerHudBottomWidget
{
    private readonly ImageAttributes _quietCold = QuietColdSkill();
    private (int Physical, int VisibleDrugs, int Skills) _lights;
    private static readonly RectangleF CoatingRect = new(745.5f,515.5f,191,12);
    private static readonly Color SourceIvory = Color.FromArgb(237,243,241);
    private static readonly Color BankA = Color.FromArgb(255,212,90), BankB = Color.FromArgb(154,209,245);

    private static ImageAttributes QuietColdSkill()
    {
        var attr = new ImageAttributes();
        // Half saturation keeps the original icon recognizable under the main shortcut row.
        attr.SetColorMatrix(new ColorMatrix([
            [.607f,.107f,.107f,0,0], [.358f,.858f,.358f,0,0], [.035f,.035f,.535f,0,0],
            [0,0,0,.72f,0], [0,0,0,0,1]]));
        return attr;
    }

    internal static (int Physical, int VisibleDrugs, int Skills) SourceLights(PlayerHudSnapshot? s)
    {
        if (s == null) return default;
        int physical = 0, drugs = 0, skills = 0;
        foreach (var card in s.BuffCards)
        {
            if (card.Activation is { Active:false } || card.DisplayTimed && card.DisplayRemaining <= 0) continue;
            if (card.Source is { Kind:"drug", Slot: >= 0 and < 8 } drug)
            {
                physical |= 1 << drug.Slot;
                int lane = drug.Slot % 4;
                if (drug.Slot / 4 == s.Loadout.Bank && lane < s.Loadout.Drugs.Length &&
                    s.Loadout.Drugs[lane].Name == drug.Key) drugs |= 1 << lane;
            }
            else if (card.Source is { Kind:"skill" } skill)
                foreach (var slot in s.Loadout.Skills)
                    if (slot.Equipped && slot.Key == skill.Key) skills |= 1 << (slot.Slot-1);
        }
        return (physical, drugs, skills);
    }

    private void PaintBankMatrix(Graphics g, int bank)
    {
        var r=SwitchRect;
        using var ink=new SolidBrush(Color.FromArgb(13,17,20));
        g.FillRectangle(ink,r.X+1,r.Y+1,r.Width-2,19);
        ink.Color=bank==0?BankA:BankB;
        g.FillRectangle(ink,r.X+4,r.Y+1,18,1.1f);
        for (int row=0;row<2;row++)
        {
            for (int col=0;col<4;col++)
            {
                bool active=row==bank, linked=(_lights.Physical & 1 << (row*4+col))!=0;
                float size=active?3.8f:linked?2.6f:2, x=r.X+4+col*6, y=r.Y+5.8f+row*7;
                ink.Color=active || linked ? (row==0?BankA:BankB) :
                    (row==0?Color.FromArgb(124,110,70):Color.FromArgb(84,109,135));
                g.FillRectangle(ink,x-size/2,y-size/2,size,size);
                if (linked && !active)
                {
                    ink.Color=SourceIvory;
                    g.FillRectangle(ink,x-1.7f,y+size/2+.9f,3.4f,1.15f);
                }
            }
        }
    }

    private static void PaintSourceLight(Graphics g,RectangleF r)
    {
        g.FillRectangle(Brushes.Black,r.X+4.8f,r.Y+23.9f,16.4f,3.1f);
        using var ink=new SolidBrush(SourceIvory);
        g.FillRectangle(ink,r.X+6,r.Y+24.6f,14,1.7f);
    }

    private static RectangleF StanceArea(PlayerHudCombat combat) =>
        new(PlayerHudAmmoPainter.CardLeft,515.5f,combat.Mode=="手雷" && !HasWeaponSlot(combat)?104:69,48);

    private void PaintStance(Graphics g,PlayerHudCombat combat)
    {
        var area=StanceArea(combat);
        var deck=combat.Deck;
        var power=deck is {Power:>=0}?Number(deck.Power):"—";
        string name=deck?.Equipment ?? "";
        if (name.Length==0) name=deck==null?"—":"未装备";
        using var label=new SolidBrush(Color.FromArgb(176,184,186));
        using var fit=new StringFormat(StringFormat.GenericTypographic) { Trimming=StringTrimming.EllipsisCharacter,FormatFlags=StringFormatFlags.NoWrap };
        bool grenade=combat.Mode=="手雷";
        var first=new RectangleF(area.Left,area.Top,area.Width,grenade?48:22);
        PlayerHudAmmoPainter.PaintTacticalCard(g,first,Scale,Color.Silver);
        if (!grenade) PlayerHudAmmoPainter.PaintTacticalCard(g,new(area.X,541.5f,area.Width,22),Scale,Color.SlateGray);
        if (grenade)
        {
            float x=area.X+5.1f, y=521.2f;
            using var pin=new Pen(Color.FromArgb(192,202,203),1.15f);
            g.DrawLines(pin,[new PointF(x+3.1f,y+1),new(x+6.3f,y+1),new(x+8.5f,y+2.7f),new(x+9.2f,y+5.3f)]);
            g.DrawLine(pin,x+3.5f,y+1,x+3.5f,y+3.1f);
            using var canister=new GraphicsPath();
            canister.AddRoundedRectangle(new RectangleF(x+1.1f,y+3.1f,6.8f,7.7f),new SizeF(2.2f,2.2f));
            g.FillPath(label,canister);
            pin.Color=Color.FromArgb(70,80,84);pin.Width=.85f;
            g.DrawLine(pin,x+1.8f,y+6,x+7.1f,y+6);g.DrawLine(pin,x+2.1f,y+8.3f,x+6.8f,y+8.3f);
            var count=combat.Ammo[1];
            float countWidth=HasWeaponSlot(combat)?18:36;
            _numbers.Draw(g,count.Length==0?"—":count,area.X+18,532,12,Scale,countWidth,
                count=="0"?PlayerHudAmmoPainter.EmptyLoadedText:Color.Silver);
            if (!HasWeaponSlot(combat) && count.Length!=0)
                g.DrawString("枚",_small,label,area.X+20+_numbers.Width(count,12,countWidth),522.7f,StringFormat.GenericTypographic);
            fit.Alignment=StringAlignment.Far;
            g.DrawString("威力",_experienceLabel,label,new RectangleF(area.Right-40,516,35,10),fit);
            using var powerInk=new SolidBrush(Color.FromArgb(183,193,194));
            g.DrawString(power,_small,powerInk,new RectangleF(area.Right-44,525,39,12),fit);
            fit.Alignment=StringAlignment.Near;
        }
        else
        {
            // The signed design crops the existing mode art to this viewBox, excluding its old title.
            string id=combat.Mode=="兵器"?"mode-3":"mode-5";
            var bounds=PlayerHudArtData.Bounds(id);
            var image=_art.Get(id,(int)Math.Ceiling(bounds.Width*Scale),(int)Math.Ceiling(bounds.Height*Scale));
            float sx=image.Width/bounds.Width,sy=image.Height/bounds.Height;
            var crop=new RectangleF((-1.5f-bounds.X)*sx,(11.2f-bounds.Y)*sy,29*sx,27.5f*sy);
            g.DrawImage(image,new RectangleF(area.X+5.2f,521.2f,11.2f,10.6f),crop,GraphicsUnit.Pixel);
            _numbers.Draw(g,power,area.Left+20.5f,530.4f,12.6f,Scale,44,Color.Silver);
        }
        g.DrawString(name,_small,label,new RectangleF(area.X+5.5f,547.7f,area.Width-10.5f,13),fit);
    }

    private void PaintWeaponColumn(Graphics g,bool occupied)
    {
        using var bed=new SolidBrush(Color.FromArgb(22,26,28));
        using var edge=new Pen(Color.FromArgb(66,75,79),.8f);
        var head=new RectangleF(558.5f,515.5f,29.5f,13);
        g.FillRectangle(bed,head);
        g.DrawRectangle(edge,head.X,head.Y,head.Width,head.Height);
        g.DrawString("战技",_small,Brushes.LightGray,563,516.6f,StringFormat.GenericTypographic);
        if (occupied) return;
        g.FillRectangle(bed,WeaponRect);
        g.DrawRectangle(edge,WeaponRect.X,WeaponRect.Y,WeaponRect.Width,WeaponRect.Height);
        g.DrawString("+",_slotMark,Brushes.DimGray,WeaponRect.X+8,WeaponRect.Y+4);
    }

    private void PaintCoating(Graphics g,PlayerHudDeckFacts? deck)
    {
        var r=CoatingRect;
        bool active=deck?.Points>0, low=active && deck!.Points<=10, known=active && deck!.Initial>0;
        using var ink=new SolidBrush(active?Color.FromArgb(16,21,19):Color.FromArgb(51,18,22,24));
        using var edge=new Pen(!active?Color.FromArgb(51,255,255,255):low?Color.FromArgb(206,169,88):Color.FromArgb(104,124,112),active?.75f:.6f);
        PointF[] corners=[new(r.X+2,r.Y),new(r.Right,r.Y),new(r.Right-4,r.Bottom),new(r.X,r.Bottom)];
        g.FillPolygon(ink,corners);g.DrawPolygon(edge,corners);
        if (!active)
        {
            using var track=new Pen(Color.FromArgb(36,255,255,255),.7f);
            g.DrawLine(track,784,522,930,522);
            return;
        }
        ink.Color=low?Color.FromArgb(240,202,121):Color.FromArgb(148,193,161);
        using var drop=new GraphicsPath();
        drop.AddBezier(754.5f,518.4f,756,520.5f,757,522,757,523.1f);
        drop.AddArc(752,520.6f,5,5,0,180);
        drop.AddBezier(752,523.1f,752,522,753,520.5f,754.5f,518.4f);
        drop.CloseFigure();
        g.FillPath(ink,drop);
        g.DrawString("淬毒",_experienceLabel,ink,759.8f,516.6f,StringFormat.GenericTypographic);
        int lit=known?(int)Math.Ceiling(10*deck!.Points/deck.Initial):0;
        for(int i=0;i<10;i++)
        {
            ink.Color=!known?Color.FromArgb(85,91,88):i<lit?Color.FromArgb(110,171,133):Color.FromArgb(49,66,56);
            const float gap=1.6f, cell=(107-9*gap)/10;
            float x=784+i*(cell+gap);
            g.FillPolygon(ink,[new PointF(x+1.3f,519),new(x+cell,519),new(x+cell-1.3f,524),new(x,524)]);
        }
        if(low)g.DrawLine(edge,783,525.6f,891,525.6f);
        _numbers.DrawRight(g,Number(deck!.Points),931,525.5f,11.8f,Scale,36,Color.FromArgb(213,226,215));
    }
}
