namespace CF7Launcher.Guardian
{
    public sealed record PerformanceDisplayState(string Preset,string Mode,string Status,
        int Width,int Height,string Quality,int EffectLevel,string Reason)
    {
        public static PerformanceDisplayState Initial { get; } = new("balanced","auto","waiting",0,0,"",0,"");
        public string StatusLabel => Status switch {
            "ready" => "已生效", "paused" => "暂停", "inactive" => "后台",
            "disconnected" => "连接中断", "unavailable" => "呈现异常", "stale" => "数据过期", "waiting" => "等待状态", _ => "切换中"
        };
        public string Compact => Height>0 ? Height+"p/"+(Quality.Length>0 ? Quality.Substring(0,1) : "?")
            +" "+(Status=="ready" ? (Mode=="fixed" ? "固定" : "自动") : StatusLabel) : StatusLabel;
        private string ReasonLabel => Reason switch {
            "panic" => "严重掉帧", "sustained_low_fps" => "持续低帧率", "sustained_headroom" => "稳定恢复",
            "policy_changed" => "方案应用", "viewport_changed" => "窗口变化", _ => ""
        };
        public string Details => (Preset=="quality" ? "画质" : Preset=="performance" ? "性能" : "通用")
            +" · "+(Mode=="fixed" ? "固定" : "自动")+" · "+StatusLabel
            +(Height>0 ? " · "+Width+"×"+Height+" "+Quality : "")
            +" · 效果 "+(EffectLevel==0 ? "完整" : EffectLevel==1 ? "适中" : "精简")
            +(ReasonLabel.Length>0 ? " · "+ReasonLabel : "");
    }
}
