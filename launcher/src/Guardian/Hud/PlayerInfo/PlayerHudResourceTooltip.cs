#nullable enable
using System;
using System.Globalization;
using System.Linq;
using System.Windows.Forms;
using CF7Launcher.Guardian.Hud.Tooltip;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian.Hud.PlayerInfo;

/// <summary>Read-only details from the adopted HUD snapshot, on the existing bottom surface.</summary>
internal sealed class PlayerHudResourceTooltip : IDisposable
{
    private readonly PlayerHudController _controller;
    private readonly string _nonce=Guid.NewGuid().ToString("N");
    private PlayerHudTarget? _target;
    private PlayerHudVitals? _lastVitals;
    private PlayerHudCombat? _lastCombat;
    private string? _requestId;
    private long _sequence;
    private bool _updating;
    internal NativeTooltipWidget Widget { get; }

    internal PlayerHudResourceTooltip(Control anchor,PlayerHudController controller)
    {
        _controller=controller;Widget=new NativeTooltipWidget(anchor);
        controller.ResourceTooltipRequested+=OnRequest;
        controller.State.Changed+=Refresh;
        Widget.BoundsOrVisibilityChanged+=OnVisibility;
    }
    private void OnRequest(PlayerHudTarget? target)
    {
        Close();
        if(target==null)return;
        _target=target;_requestId="player-hud-resource:"+_nonce+":"+(++_sequence);
        Refresh();
    }
    private void Refresh()
    {
        if(_target==null)return;
        var snapshot=_controller.State.Snapshot;
        if(!_controller.CanInteract || snapshot==null || snapshot.Epoch!=_target.Epoch
            || _target.ConnectionGeneration!=_controller.Generation) { Close();return; }
        if(snapshot.Vitals==_lastVitals && _lastCombat?.Mode==snapshot.Combat.Mode &&
            _lastCombat.Ammo.SequenceEqual(snapshot.Combat.Ammo))return;
        _updating=true;
        try
        {
            if(Widget.Show(Build(snapshot,_target,_requestId!))){_lastVitals=snapshot.Vitals;_lastCombat=snapshot.Combat;}
            else Close();
        }
        finally { _updating=false; }
    }
    private void OnVisibility(object? sender,EventArgs e)
    {
        // Host suppression finishes the hover; a later snapshot must not revive it.
        if(!_updating&&Widget.ActiveDocument==null){_target=null;_requestId=null;_lastVitals=null;_lastCombat=null;}
    }
    private void Close()
    {
        _target=null;_lastVitals=null;_lastCombat=null;
        var request=_requestId;_requestId=null;
        if(request!=null)Widget.Hide(request);
    }
    internal static JObject Build(PlayerHudSnapshot snapshot,PlayerHudTarget target,string requestId)
    {
        var result=Build(snapshot.Vitals,snapshot.Epoch,snapshot.Sequence,target,requestId);
        var combat=snapshot.Combat;
        if(combat.Mode is "手枪" or "手枪2" or "长枪" or "双枪" or "长枪副武器" or "手雷")
        {
            var runs=(JArray)result["document"]!["sections"]![0]!["runs"]!;
            void Line(string value,bool bold=false)=>runs.Add(new JObject{["text"]=value+"\n",["bold"]=bold,["fontSize"]=16});
            string Ammo(int index)=>combat.Ammo[index].Length==0?"--":combat.Ammo[index];
            Line("弹药 · "+combat.Mode,true);
            if(combat.Mode=="手雷")Line("剩余数量："+Ammo(1));
            else
            {
                Line("弹内余弹："+Ammo(0)+"　备用弹夹："+Ammo(1));
                if(combat.Mode is "双枪" or "长枪副武器")Line("副手余弹："+Ammo(2)+"　备用弹夹："+Ammo(3));
            }
        }
        return result;
    }

    internal static JObject Build(PlayerHudVitals v,long epoch,long sequence,PlayerHudTarget target,string requestId)
    {
        var runs=new JArray();
        void Line(string text,bool bold=false) => runs.Add(new JObject { ["text"]=text+"\n",["bold"]=bold,["fontSize"]=16 });
        void Resource(string name,double value,double maximum)
        {
            Line(name+"："+Number(value)+" / "+Number(maximum)+"（"+PlayerHudResourceStyle.Percent(value,maximum)+"）");
            Line("超额："+(maximum>0?"+"+Number(Math.Max(0,value-maximum)):"未就绪"));
        }
        Line("资源详情",true);
        Resource("生命",v.Hp,v.HpMax);Resource("魔力",v.Mp,v.MpMax);
        if(!v.ShieldReady)Line("护盾：未就绪");
        else if(!v.ShieldPresent)Line("护盾：无护盾");
        else
        {
            Resource("护盾",v.Shield,v.ShieldMax);
            var shield=v.ShieldDetail;
            Line("护盾强度："+(shield?.StrengthKind=="unlimited"?"无强度上限":shield?.StrengthKind=="finite"?
                shield.Strength.ToString("0.##",CultureInfo.InvariantCulture):"未就绪"));
            Line(shield==null?"抗真伤：未就绪":shield.ResistsBypass?"可抵抗真伤，仍受强度与剩余盾量限制":"普通护盾：真伤可绕过");
            Line(RecoveryCaption(shield?.Recovery));
        }
        Line("韧性",true);
        Line(PlayerHudResourceStyle.Percent(v.Poise,1)+" · "+PlayerHudResourceStyle.PoiseCaption(v.PoiseDetail));
        if(v.PoiseVisual is {Airborne:true,Rigid:true})Line("浮空与刚体同时存在；斜纹为浮空，金属槽底为刚体。");
        else if(v.PoiseVisual is {Airborne:true} or {Down:true})Line("遮纹下的条形仅为韧性参考，当前不提供普通韧性保护。");
        var detail=v.PoiseDetail;
        Line(detail==null || detail.Phase=="unavailable" ? "踉跄分界：未就绪"
            : !detail.HasStaggerBand ? "踉跄分界：无踉跄区间"
            : "踉跄分界：约 "+(detail.Threshold*100).ToString("0.#",CultureInfo.InvariantCulture)+"%"
                +(detail.Phase is "rigid" or "air" or "down" ? "（当前不适用）" : ""));
        Line("等级与经验",true);
        Line("等级："+v.Level.ToString(CultureInfo.InvariantCulture)+"    技能点："+Number(v.SkillPoints));
        var (earned,required)=PlayerHudResourceStyle.LevelExperience(v);
        if(required>0)
        {
            Line("本级经验："+Number(earned)+" / "+Number(required)+"（"+PlayerHudResourceStyle.Percent(earned,required)+"）");
            Line("距升级："+Number(Math.Max(0,v.ExperienceEnd-v.Experience)));
        }
        else { Line("本级经验：区间未就绪");Line("累计经验："+Number(v.Experience)+"    距升级：--"); }
        // No title/icon selects the existing content-sized plain tooltip layout.
        return new JObject { ["version"]=1,["requestId"]=requestId,["sceneId"]="player-hud:"+epoch,
            ["owner"]="player-hud-resources",["revision"]=sequence,["placement"]="top",
            ["x"]=target.Anchor.Left+target.Anchor.Width/2,["y"]=target.Anchor.Top,
            ["anchorRect"]=new JObject{["x"]=target.Anchor.X,["y"]=target.Anchor.Y,["width"]=target.Anchor.Width,["height"]=target.Anchor.Height},
            ["document"]=new JObject{["version"]=1,["profile"]="simple",["sections"]=new JArray(new JObject{["role"]="body",["runs"]=runs})} };
    }
    private static string Number(double value)=>Math.Floor(value).ToString("0",CultureInfo.InvariantCulture);
    internal static string RecoveryCaption(PlayerHudShieldRecovery? recovery)=>recovery?.State switch
    {
        "waiting"=>"下次回充：约 "+(recovery.RemainingMs/1000).ToString("0.0",CultureInfo.InvariantCulture)+" 秒后（多层取最早，受击可能重置）",
        "charging"=>"恢复中（装备供能护盾会消耗对应资源）",
        "health"=>"恢复受阻：破盾后需要生命回满",
        "mp"=>"恢复受阻：MP不足以启动或继续供能",
        "conditions"=>"恢复受阻：不同护盾层仍需满足生命或MP条件",
        "full"=>"已达到当前回充目标",
        "manual"=>"无自动回充，需技能或其他来源补充",
        "none"=>"无护盾",
        _=>"恢复信息：未就绪"
    };
    public void Dispose()
    {
        _controller.ResourceTooltipRequested-=OnRequest;_controller.State.Changed-=Refresh;
        Widget.BoundsOrVisibilityChanged-=OnVisibility;Close();Widget.Dispose();
    }
}
