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
    private readonly bool _buffsOnly;
    private PlayerHudBuffCard? _lastBuffCard;
    private PlayerHudFocusTarget? _lastFocusTarget;
    internal NativeTooltipWidget Widget { get; }

    internal PlayerHudResourceTooltip(Control anchor,PlayerHudController controller,bool buffsOnly=false)
    {
        _buffsOnly=buffsOnly;_controller=controller;Widget=new NativeTooltipWidget(anchor);
        controller.ResourceTooltipRequested+=OnRequest;
        controller.State.Changed+=Refresh;
        Widget.BoundsOrVisibilityChanged+=OnVisibility;
    }
    private void OnRequest(PlayerHudTarget? target)
    {
        Close();
        if(target==null || (target.Kind is "buff" or "focusTarget")!=_buffsOnly)return;
        _target=target;_requestId="player-hud-resource:"+_nonce+":"+(++_sequence);
        Refresh();
    }
    private void Refresh()
    {
        if(_target==null)return;
        var snapshot=_controller.State.Snapshot;
        if(!_controller.CanInteract || snapshot==null || snapshot.Epoch!=_target.Epoch
            || _target.ConnectionGeneration!=_controller.Generation) { Close();return; }
        PlayerHudBuffCard? card = null;
        PlayerHudFocusTarget? focus = null;
        if (_target.Kind == "buff")
        {
            if (_target.Slot < 0 || _target.Slot >= snapshot.BuffCards.Length || snapshot.BuffCards[_target.Slot].Id != _target.Key)
            {
                Close(); return;
            }
            card = snapshot.BuffCards[_target.Slot];
            if (PlayerHudBuffCard.SameDisplay(card, _lastBuffCard)) return;
        }
        else if (_target.Kind == "focusTarget")
        {
            var rowIndex = System.Array.FindIndex(snapshot.TargetList, t => t.Id.ToString(CultureInfo.InvariantCulture) == _target.Key);
            if (rowIndex < 0)
            {
                Close(); return;
            }
            focus = snapshot.TargetList[rowIndex];
            var currentAnchor = PlayerHudFocusTargetWidget.RowBounds(snapshot.BuffCards.Length, rowIndex);
            if (focus == _lastFocusTarget && _target.Anchor == currentAnchor) return;
            _target = _target with { Slot = rowIndex, Anchor = currentAnchor };
        }
        else if (snapshot.Vitals==_lastVitals && _lastCombat?.Mode==snapshot.Combat.Mode
            && _lastCombat.Ammo.SequenceEqual(snapshot.Combat.Ammo)
            && (_lastCombat.AmmoDetails??Array.Empty<PlayerHudAmmoDetail?>())
                .SequenceEqual(snapshot.Combat.AmmoDetails??Array.Empty<PlayerHudAmmoDetail?>())) return;
        _updating=true;
        try
        {
            if(Widget.Show(Build(snapshot,_target,_requestId!))){_lastVitals=snapshot.Vitals;_lastCombat=snapshot.Combat;_lastBuffCard=card;_lastFocusTarget=focus;}
            else Close();
        }
        finally { _updating=false; }
    }
    private void OnVisibility(object? sender,EventArgs e)
    {
        // Host suppression finishes the hover; a later snapshot must not revive it.
        if(!_updating&&Widget.ActiveDocument==null){_target=null;_requestId=null;_lastVitals=null;_lastCombat=null;_lastBuffCard=null;_lastFocusTarget=null;}
    }
    private void Close()
    {
        _target=null;_lastVitals=null;_lastCombat=null;_lastBuffCard=null;_lastFocusTarget=null;
        var request=_requestId;_requestId=null;
        if(request!=null)Widget.Hide(request);
    }
    internal static JObject Build(PlayerHudSnapshot snapshot,PlayerHudTarget target,string requestId)
    {
        var result=Build(snapshot.Vitals,snapshot.Epoch,snapshot.Sequence,target,requestId);
        if (target.Kind == "focusTarget")
        {
            var lines = (JArray)result["document"]!["sections"]![0]!["runs"]!; lines.Clear();
            void Add(string text,bool bold=false) => lines.Add(new JObject{["text"]=text+"\n",["bold"]=bold});
            result["placement"]="bottom";
            var focus = snapshot.TargetList.FirstOrDefault(t => t.Id.ToString(CultureInfo.InvariantCulture) == target.Key) ?? snapshot.FocusTarget;
            if (focus != null)
            {
                Add(focus.Name.Replace('\r', ' ').Replace('\n', ' '), true);
                Add(focus.Role switch
                {
                    "boss" => "关卡首领（Boss）",
                    "protect" => "保护目标（需存活）",
                    _ => "当前交战目标"
                });
                Add("生命："+PlayerHudFocusTargetWidget.HealthText(focus)+"（"+PlayerHudResourceStyle.Percent(focus.Hp,focus.HpMax)+"）");
                if (focus.Hp > focus.HpMax) Add("超额：+"+Number(Math.Max(0,focus.Hp-focus.HpMax)));
                if (focus.Hits > 0) Add("当前连击："+focus.Hits.ToString(CultureInfo.InvariantCulture)+" Hit");
                if (focus.Hp > 0 && focus.Hp / focus.HpMax <= 0.25)
                    Add(focus.Role == "protect" ? "状态：保护目标生命危急，请注意掩护" : "状态：目标生命危急");
            }
            return result;
        }
        if (target.Kind == "buff")
        {
            var lines = (JArray)result["document"]!["sections"]![0]!["runs"]!; lines.Clear();
            void Add(string text,bool bold=false) => lines.Add(new JObject{["text"]=text+"\n",["bold"]=bold});
            result["placement"]="bottom";
            var buff = snapshot.BuffCards.FirstOrDefault(b=>b.Id==target.Key);
            if (buff != null)
            {
                Add(buff.Name.Length>0?buff.Name:"未命名状态",true);
                if(buff.Polarity is "benefit" or "harm")Add(buff.Polarity=="benefit"?"增益状态":"减益状态");
                if(buff.PhaseLabel.Length>0)Add(buff.PhaseLabel);
                Add(buff.Description.Length>0?buff.Description:"此状态尚未提供效果说明。");
                if (buff.Stacks>1) Add("层数："+buff.Stacks);
                if (buff.Mods is { } mods)
                {
                    if (mods.Length==0) Add("当前修正：无已注入属性修正");
                    else
                    {
                        Add("当前修正",true);
                        foreach(var mod in mods)Add(mod.Property+"："+PlayerHudBuffCard.DescribeMod(mod));
                    }
                }
                if (buff.Timed) Add("剩余约 "+PlayerHudBuffCard.Seconds(buff.Remaining).ToString("0",CultureInfo.InvariantCulture)+" 秒");
                if (buff.Activation is { } activation)
                {
                    if (activation.Active) Add(activation.Total>0
                        ? "激活剩余约 "+PlayerHudBuffCard.Seconds(activation.Remaining).ToString("0",CultureInfo.InvariantCulture)+" 秒"
                        : "激活效果由条件维持");
                    else if (activation.Total>0) Add("触发后持续约 "+PlayerHudBuffCard.Seconds(activation.Total).ToString("0",CultureInfo.InvariantCulture)+" 秒");
                }
                else if (!buff.Timed) Add("持续时间由效果条件决定");
            }
            return result;
        }
        var combat=snapshot.Combat;
        var ammoRuns=(JArray)result["document"]!["sections"]![0]!["runs"]!;
        if(target.Kind=="ammo")ammoRuns.Clear();
        if(combat.Mode is "手枪" or "手枪2" or "长枪" or "双枪" or "长枪副武器" or "手雷")
        {
            var runs=(JArray)result["document"]!["sections"]![0]!["runs"]!;
            void Line(string value,bool bold=false)=>runs.Add(new JObject{["text"]=value+"\n",["bold"]=bold});
            string Ammo(int index)=>combat.Ammo[index].Length==0?"--":combat.Ammo[index];
            Line("弹药 · "+combat.Mode,true);
            if(combat.Mode=="手雷")Line("剩余数量："+Ammo(1));
            else
            {
                var dual = combat.Mode is "双枪" or "长枪副武器";
                Line((dual ? "主手（上排）：" : "弹内余弹：")+Ammo(0)+"　备用弹夹："+Ammo(1));
                if(dual)Line("副手（下排）："+Ammo(2)+"　备用弹夹："+Ammo(3));
                if(combat.AmmoDetails is { } details)
                {
                    for(var i=0;i<details.Length;i++)
                    {
                        if(details[i] is not { } detail || target.Kind=="ammo" && target.Slot!=i)continue;
                        Line((i==0?"主手":"副手")+"装填",true);
                        Line("普通："+detail.Normal+" / "+detail.Capacity+"　留膛："+detail.Chamber);
                        Line("幽灵："+detail.Ghost+"　奖励："+detail.Reward+"　合计："+detail.Loaded);
                        Line("超额装填：+"+detail.Overflow);
                        Line("已拆包余量："+detail.Reserve+" 发（已扣除库存，可继续装填）");
                        if(detail.Ghost>0)Line("幽灵散射倍率："+detail.Spread.ToString("0.##",CultureInfo.InvariantCulture)+"，随幽灵弹消耗恢复");
                    }
                }
            }
        }
        return result;
    }

    internal static JObject Build(PlayerHudVitals v,long epoch,long sequence,PlayerHudTarget target,string requestId)
    {
        var runs=new JArray();
        void Line(string text,bool bold=false) => runs.Add(new JObject { ["text"]=text+"\n",["bold"]=bold });
        void Resource(string name,double value,double maximum)
        {
            Line(name+"："+Number(value)+" / "+Number(maximum)+"（"+PlayerHudResourceStyle.Percent(value,maximum)+"）");
            Line("超额："+(maximum>0?"+"+Number(Math.Max(0,value-maximum)):"未就绪"));
        }
        Line(v.Name.Length > 0 ? v.Name+" · 资源详情" : "资源详情",true);
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
