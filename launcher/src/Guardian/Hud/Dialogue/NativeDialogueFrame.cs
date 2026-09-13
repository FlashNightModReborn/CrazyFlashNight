using System;

namespace CF7Launcher.Guardian.Hud.Dialogue
{
    /// <summary>
    /// native_dialogue 桥协议的单句快照 DTO（AS2 → Host Task → NativeDialogueWidget）。
    ///
    /// 语义边界：
    /// - 句序/人物/暂停责任/finish-cancel 权威在 AS2；本对象只是一句的呈现快照。
    /// - appearance（纸娃娃外观对象）由 Host Task 持有并翻译成 Bitmap，
    ///   经 NativeDialogueWidget.SetPortrait 投递；widget 不解析 appearance。
    /// - Revision 在同一会话（RequestId）内单调不减；widget 用它拒绝迟到图片与跨修订手势。
    /// - ImageAction ∈ "show" | "keep" | "clear"；show 的实际位图经 SetSceneImage 投递。
    /// </summary>
    public sealed class NativeDialogueFrame
    {
        /// <summary>会话身份，形如 "nd:&lt;正整数&gt;"。同 RequestId 的帧序列构成一次对白。</summary>
        public string RequestId;
        /// <summary>场景归属（AS2 生成，host 只透传）。</summary>
        public string SceneId;
        /// <summary>帧修订号；同 RequestId 内递增。</summary>
        public int Revision;
        /// <summary>当前句序号（0 基）。</summary>
        public int LineIndex;
        /// <summary>本轮总句数。</summary>
        public int LineCount;
        /// <summary>说话人名（已含 AS2 侧 $PC/角色名 特判结果）。</summary>
        public string Name;
        /// <summary>称号（可空）。</summary>
        public string Title;
        /// <summary>正文，可含有限 HTML 子集（&lt;font color='#RRGGBB'&gt; / &lt;BR&gt;），其余标签剥离。</summary>
        public string Text;
        /// <summary>立绘 key；空串/ null 表示本句无人物（隐藏立绘）。</summary>
        public string PortraitKey;
        /// <summary>表情名（AS2 已含 Andy Law 立绘类型后缀等投影）。</summary>
        public string Expression;
        /// <summary>true = 动态纸娃娃（Host Task 走 doll bake 链出图）；false = 静态立绘。</summary>
        public bool IsDoll;
        /// <summary>独立角色的外观身份；相同模板也不能沿用另一位佣兵的图。</summary>
        public string AppearanceIdentity;
        /// <summary>配图动作："show" 展示 ImagePath、"keep" 沿用上一张、"clear" 清除。</summary>
        public string ImageAction;
        /// <summary>配图路径（本地资源解析器处理；widget 只按值比较异同，不自行读盘）。</summary>
        public string ImagePath;

        /// <summary>回调/外发用的浅快照（字段均为值类型或不可变 string，浅拷贝即冻结）。</summary>
        public NativeDialogueFrame Snapshot()
        {
            return (NativeDialogueFrame)MemberwiseClone();
        }

        /// <summary>立绘身份：key + 表情 + 来源类型。换人/换表情即变，widget 据此决定重等新图。</summary>
        internal string PortraitIdentity
        {
            get
            {
                return (PortraitKey ?? "") + "\x1" + (Expression ?? "") + "\x1" + (IsDoll ? "1" : "0")
                    + "\x1" + (AppearanceIdentity ?? "");
            }
        }

        /// <summary>本句是否需要立绘（PortraitKey 非空）。</summary>
        internal bool WantsPortrait
        {
            get { return !string.IsNullOrEmpty(PortraitKey); }
        }

        /// <summary>本句是否声明配图（ImageAction=="show"）。</summary>
        internal bool WantsSceneImage
        {
            get
            {
                return string.Equals(ImageAction, "show", StringComparison.Ordinal)
                    && !string.IsNullOrEmpty(ImagePath);
            }
        }
    }
}
