#nullable enable
using System;
using System.Globalization;
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
        if(snapshot.Vitals==_lastVitals)return;
        _updating=true;
        try
        {
            if(Widget.Show(Build(snapshot,_target,_requestId!)))_lastVitals=snapshot.Vitals;
            else Close();
        }
        finally { _updating=false; }
    }
    private void OnVisibility(object? sender,EventArgs e)
    {
        // Host suppression finishes the hover; a later snapshot must not revive it.
        if(!_updating&&Widget.ActiveDocument==null){_target=null;_requestId=null;_lastVitals=null;}
    }
    private void Close()
    {
        _target=null;_lastVitals=null;
        var request=_requestId;_requestId=null;
        if(request!=null)Widget.Hide(request);
    }
    internal static JObject Build(PlayerHudSnapshot snapshot,PlayerHudTarget target,string requestId)
        => Build(snapshot.Vitals, snapshot.Epoch, snapshot.Sequence, target, requestId);

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
        else Resource("护盾",v.Shield,v.ShieldMax);
        Line("韧性",true);
        Line(PlayerHudResourceStyle.Percent(v.Poise,1)+" · "+PlayerHudResourceStyle.PoiseCaption(v.PoiseDetail));
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
    public void Dispose()
    {
        _controller.ResourceTooltipRequested-=OnRequest;_controller.State.Changed-=Refresh;
        Widget.BoundsOrVisibilityChanged-=OnVisibility;Close();Widget.Dispose();
    }
}
