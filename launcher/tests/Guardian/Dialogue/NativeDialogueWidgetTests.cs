using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;
using CF7Launcher.Guardian.Hud.Dialogue;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    /// <summary>
    /// NativeDialogueWidget 定向回归。
    ///
    /// 覆盖合同关键点：
    /// - ShowFrame 整帧替换 / 同会话迟到修订拒绝 / 换人换句（立绘身份变化 → pending，
    ///   旧图保留到新图到达，无闪烁清屏）。
    /// - TryAdvance 先补全打字再发 advance；TryClose 直发 close；InputRequested 携带帧快照。
    /// - 鼠标 Down 绑定 (requestId, revision, zone)，Up 同修订同 zone 才生效：
    ///   跨修订迟到 Up 不推进；快速双击第二击只补全新句打字不跳过。
    /// - SetPortrait/SetSceneImage 迟到图（requestId/revision 不匹配）拒绝；
    ///   配图 keep/show/clear 语义。
    /// - SetHostSuppressed 压隐只取消手势+隐藏+暂停打字，不终结会话；恢复后继续。
    /// - 长文本排版：CJK 折行、标点禁断、行数超容量自动滚底不越界、打完停 tick。
    /// - 1024×576 逻辑坐标随 viewport 缩放（1.0 / 1.875）。
    /// - 原版 UI 复刻：关闭/拖动/推进热区 = XFL stageRect；拖动柄 startDrag 平移
    ///   面板（不产生 verb、偏移跨句保持、钳制不出舞台）；头条死区点击不推进；
    ///   立绘 mask 裁剪矩形与底锚注册；DialogueUiSkin 夹具加载与光栅缓存。
    /// </summary>
    public sealed class NativeDialogueWidgetTests
    {
        private static NativeDialogueFrame Frame(
            string req = "nd:1", string scene = "sceneA", int rev = 1,
            string name = "Blue", string text = "你好，世界。",
            int line = 0, int lines = 2, string portrait = "Blue",
            string expr = "普通", string imageAction = "keep", string imagePath = "")
        {
            return new NativeDialogueFrame
            {
                RequestId = req,
                SceneId = scene,
                Revision = rev,
                LineIndex = line,
                LineCount = lines,
                Name = name,
                Title = "测试称号",
                Text = text,
                PortraitKey = portrait,
                Expression = expr,
                IsDoll = false,
                ImageAction = imageAction,
                ImagePath = imagePath
            };
        }

        /// <summary>viewport 可变容器：provider 读 R，测试中途换分辨率。</summary>
        private sealed class Vp
        {
            internal Rectangle R;
            internal Vp(int w, int h) { R = new Rectangle(0, 0, w, h); }
        }

        private static NativeDialogueWidget MakeWidget(Vp vp)
        {
            return new NativeDialogueWidget(new Control(), delegate { return vp.R; });
        }

        private static Bitmap Bmp(int w, int h)
        {
            Bitmap b = new Bitmap(w, h);
            using (Graphics g = Graphics.FromImage(b)) g.Clear(Color.DarkBlue);
            return b;
        }

        private static MouseEventArgs LeftAt(int x, int y)
        {
            return new MouseEventArgs(MouseButtons.Left, 1, x, y, 0);
        }

        /// <summary>把正文打字打完（直接 Tick 大步长）。</summary>
        private static void FinishTyping(NativeDialogueWidget w)
        {
            w.TypingIntervalMs = 1;
            for (int i = 0; i < 200 && !w.TypingCompleteForTest; i++) w.Tick(50);
            Assert.True(w.TypingCompleteForTest, "typing did not finish");
        }

        /// <summary>「下一句」透明热区中心（原版 Symbol 1881 stageRect）。</summary>
        private static Point PanelCenter(NativeDialogueWidget.Layout L)
        {
            return new Point(L.Next.X + L.Next.Width / 2,
                L.Next.Y + L.Next.Height / 2);
        }

        // ──────────────── 帧生命周期 ────────────────

        private sealed class DialogueOwner : Form
        {
            public void SetActive(bool active)
            {
                if (active) OnActivated(EventArgs.Empty);
                else OnDeactivate(EventArgs.Empty);
            }
        }

        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public void HostVisibilityAndPanelSuppression_ResumeOnlyAfterBothClear(bool resumePanelFirst)
        {
            using var owner = new DialogueOwner();
            using var anchor = new Control();
            using var hud = new NativeHudOverlay(owner, anchor);
            using var w = new NativeDialogueWidget(anchor, () => new Rectangle(0, 0, 1024, 576));
            hud.AddWidget(w);
            var frame = Frame(text: "窗口隐藏期间这段对白应该保留当前位置，回来再继续。", portrait: "");
            int inputs = 0;
            w.InputRequested = (f, verb) => inputs++;
            w.ShowFrame(frame);
            w.Tick(50);
            int typed = w.VisibleCharsForTest;
            Assert.True(typed > 0);

            owner.SetActive(false);
            Assert.False(w.Visible);
            Assert.False(w.WantsAnimationTick);
            Assert.False(w.TryAdvance());
            w.Tick(10000);
            Assert.Equal(typed, w.VisibleCharsForTest);
            Assert.Same(frame, w.CurrentFrame);
            hud.Suspend();
            if (resumePanelFirst) hud.Resume();
            else owner.SetActive(true);
            Assert.False(w.Visible);
            Assert.False(w.WantsAnimationTick);
            w.Tick(10000);
            Assert.Equal(typed, w.VisibleCharsForTest);

            if (resumePanelFirst) owner.SetActive(true);
            else hud.Resume();
            Assert.True(w.Visible);
            Assert.True(w.WantsAnimationTick);
            Assert.Equal(typed, w.VisibleCharsForTest);
            w.Tick(50);
            Assert.True(w.VisibleCharsForTest > typed);
            Assert.Equal(0, inputs);
            Assert.Same(frame, w.CurrentFrame);
        }

        [Fact]
        public void HostHiddenBeforeRegistration_NewDialogueWaitsForOwnerActivation()
        {
            using var owner = new DialogueOwner();
            using var anchor = new Control();
            using var hud = new NativeHudOverlay(owner, anchor);
            owner.SetActive(false);
            using var w = new NativeDialogueWidget(anchor, () => new Rectangle(0, 0, 1024, 576));
            hud.AddWidget(w);
            w.ShowFrame(Frame(portrait: ""));
            w.Tick(10000);
            Assert.False(w.Visible);
            Assert.Equal(0, w.VisibleCharsForTest);
            owner.SetActive(true);
            Assert.True(w.Visible);
            w.Tick(50);
            Assert.True(w.VisibleCharsForTest > 0);
        }

        [Fact]
        public void ShowFrame_SetsCurrentAndVisible()
        {
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                Assert.False(w.Visible);
                Assert.True(w.ShowFrame(Frame()));
                Assert.True(w.Visible);
                Assert.NotNull(w.CurrentFrame);
                Assert.Equal("nd:1", w.CurrentFrame.RequestId);
                Assert.True(w.ScreenBounds.Width > 0);
            }
        }

        [Fact]
        public void ShowFrame_StaleRevisionSameSession_Rejected()
        {
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                Assert.True(w.ShowFrame(Frame(rev: 5)));
                Assert.False(w.ShowFrame(Frame(rev: 4)));
                Assert.Equal(5, w.CurrentFrame.Revision);
                // 同 revision 重推接受（幂等刷新）
                Assert.True(w.ShowFrame(Frame(rev: 5, text: "刷新文本")));
                Assert.Equal("刷新文本", w.CurrentFrame.Text);
                // 新 RequestId = 新会话
                Assert.True(w.ShowFrame(Frame(req: "nd:2", rev: 0)));
                Assert.Equal("nd:2", w.CurrentFrame.RequestId);
            }
        }

        [Fact]
        public void HideFrame_RequiresExactIdentity()
        {
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                w.ShowFrame(Frame());
                Assert.False(w.HideFrame("nd:1", "otherScene"));
                Assert.False(w.HideFrame("nd:9", "sceneA"));
                Assert.True(w.Visible);
                Assert.True(w.HideFrame("nd:1", "sceneA"));
                Assert.False(w.Visible);
                Assert.Null(w.CurrentFrame);
                Assert.Equal(Rectangle.Empty, w.ScreenBounds);
            }
        }

        [Fact]
        public void Reset_ClearsSilently()
        {
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                List<string> verbs = new List<string>();
                w.InputRequested = (f, v) => verbs.Add(v);
                w.ShowFrame(Frame(imageAction: "show", imagePath: "a.png"));
                w.SetSceneImage("nd:1", 1, Bmp(100, 80));
                using (Bitmap p = Bmp(200, 400)) w.SetPortrait("nd:1", 1, p);
                w.Reset();
                Assert.False(w.Visible);
                Assert.False(w.HasPortraitForTest);
                Assert.False(w.HasSceneImageForTest);
                Assert.Empty(verbs);    // Reset 不发任何 verb
            }
        }

        // ──────────────── 打字 / 推进 ────────────────

        [Fact]
        public void TryAdvance_FirstCompletesTyping_ThenFiresAdvance()
        {
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                List<string> verbs = new List<string>();
                List<int> revs = new List<int>();
                w.InputRequested = (f, v) => { verbs.Add(v); revs.Add(f.Revision); };
                w.ShowFrame(Frame(text: "这是一句需要逐字显示的中文对白。"));

                Assert.False(w.TypingCompleteForTest);
                Assert.True(w.TryAdvance());            // 第 1 击：补全
                Assert.True(w.TypingCompleteForTest);
                Assert.Empty(verbs);                    // 补全不发 verb

                Assert.True(w.TryAdvance());            // 第 2 击：发 advance
                Assert.Equal(new[] { "advance" }, verbs);
                Assert.Equal(new[] { 1 }, revs);
            }
        }

        [Fact]
        public void Tick_RevealsCharsThenStopsAnimation()
        {
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                w.ShowFrame(Frame(text: "ABCDE"));
                Assert.True(w.WantsAnimationTick);
                w.TypingIntervalMs = 10;
                w.Tick(25);                              // +2 字
                Assert.Equal(2, w.VisibleCharsForTest);
                Assert.True(w.WantsAnimationTick);
                FinishTyping(w);
                Assert.False(w.WantsAnimationTick);      // 打完停 tick
                int before = w.VisibleCharsForTest;
                w.Tick(5000);                            // 空转不再推进/报错
                Assert.Equal(before, w.VisibleCharsForTest);
            }
        }

        [Fact]
        public void TryClose_FiresClose_RegardlessOfTyping()
        {
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                List<string> verbs = new List<string>();
                w.InputRequested = (f, v) => verbs.Add(v);
                w.ShowFrame(Frame());
                Assert.False(w.TypingCompleteForTest);
                Assert.True(w.TryClose());
                Assert.Equal(new[] { "close" }, verbs);
                // 无会话后调用安全返回
                w.Reset();
                Assert.False(w.TryClose());
                Assert.False(w.TryAdvance());
            }
        }

        // ──────────────── 图片：迟到拒绝 / keep-show-clear / 换人 ────────────────

        [Fact]
        public void Portrait_LateOrWrongRevision_Rejected()
        {
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                w.ShowFrame(Frame(rev: 2));
                Assert.True(w.PortraitPendingForTest);
                using (Bitmap late = Bmp(10, 10))
                    Assert.False(w.SetPortrait("nd:1", 1, late));    // 迟到修订
                using (Bitmap wrongReq = Bmp(10, 10))
                    Assert.False(w.SetPortrait("nd:9", 2, wrongReq)); // 错会话
                Assert.True(w.PortraitPendingForTest);
                Assert.False(w.HasPortraitForTest);
                using (Bitmap ok = Bmp(200, 400))
                    Assert.True(w.SetPortrait("nd:1", 2, ok));
                Assert.True(w.HasPortraitForTest);
                Assert.False(w.PortraitPendingForTest);
            }
        }

        [Fact]
        public void Portrait_SameIdentityNextLine_KeepsBitmap()
        {
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                w.ShowFrame(Frame(rev: 1));
                using (Bitmap p = Bmp(200, 400)) w.SetPortrait("nd:1", 1, p);
                // 同一人同一表情下一行：无需重投，旧图保留
                Assert.True(w.ShowFrame(Frame(rev: 2, text: "下一句")));
                Assert.True(w.HasPortraitForTest);
                Assert.False(w.PortraitPendingForTest);
            }
        }

        [Fact]
        public void Portrait_DifferentKeyOrExpression_DropsOtherActorWhilePending()
        {
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                w.ShowFrame(Frame(rev: 1));
                using (Bitmap p = Bmp(200, 400)) w.SetPortrait("nd:1", 1, p);
                // 换人后不能在新名字下继续显示上一位角色。
                Assert.True(w.ShowFrame(Frame(rev: 2, portrait: "小F")));
                Assert.False(w.HasPortraitForTest);
                Assert.True(w.PortraitPendingForTest);
                using (Bitmap q = Bmp(180, 360))
                    Assert.True(w.SetPortrait("nd:1", 2, q));
                Assert.False(w.PortraitPendingForTest);
                // 换表情也算换人（key|expr|doll 三元组）
                Assert.True(w.ShowFrame(Frame(rev: 3, portrait: "小F", expr: "微笑")));
                Assert.True(w.PortraitPendingForTest);
            }
        }

        [Fact]
        public void Portrait_DollExpressionRefresh_KeepsSameAppearanceButNeverOldEquipment()
        {
            using var w = MakeWidget(new Vp(1024, 576));
            var first = Frame(portrait: "hero");
            first.IsDoll = true;
            first.AppearanceIdentity = "male-titanium";
            w.ShowFrame(first);
            using var bitmap = Bmp(768, 768);
            Assert.True(w.SetPortrait("nd:1", 1, bitmap));
            var next = first.Snapshot();
            next.Revision = 2;
            next.Expression = "愤怒";
            w.ShowFrame(next);
            Assert.True(w.HasPortraitForTest);
            Assert.True(w.PortraitPendingForTest);
            Assert.False(w.SetPortrait("nd:1", 1, bitmap));
            Assert.True(w.SetPortrait("nd:1", 2, bitmap));
            next = next.Snapshot();
            next.Revision = 3;
            next.AppearanceIdentity = "female-leather";
            w.ShowFrame(next);
            Assert.False(w.HasPortraitForTest);
            Assert.True(w.PortraitPendingForTest);
        }

        [Fact]
        public void Portrait_EmptyKey_HidesPortrait()
        {
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                w.ShowFrame(Frame(rev: 1));
                using (Bitmap p = Bmp(200, 400)) w.SetPortrait("nd:1", 1, p);
                Assert.True(w.ShowFrame(Frame(rev: 2, portrait: "")));
                Assert.False(w.HasPortraitForTest);
                Assert.False(w.PortraitPendingForTest);
                // 无立绘句投递图 = 多余，拒绝
                using (Bitmap x = Bmp(10, 10))
                    Assert.False(w.SetPortrait("nd:1", 2, x));
            }
        }

        [Fact]
        public void SceneImage_ShowKeepClear()
        {
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                // show：pending → 图到 → 显示
                Assert.True(w.ShowFrame(Frame(rev: 1,
                    imageAction: "show", imagePath: "img/a.png")));
                Assert.True(w.ScenePendingForTest);
                Assert.False(w.HasSceneImageForTest);
                using (Bitmap img = Bmp(300, 200))
                    Assert.True(w.SetSceneImage("nd:1", 1, img));
                Assert.True(w.HasSceneImageForTest);

                // keep：沿用
                Assert.True(w.ShowFrame(Frame(rev: 2, imageAction: "keep")));
                Assert.True(w.HasSceneImageForTest);
                Assert.False(w.ScenePendingForTest);

                // show 不同 path：清旧等新
                Assert.True(w.ShowFrame(Frame(rev: 3,
                    imageAction: "show", imagePath: "img/b.png")));
                Assert.False(w.HasSceneImageForTest);
                Assert.True(w.ScenePendingForTest);

                // clear：清除
                using (Bitmap img2 = Bmp(10, 10))
                    Assert.True(w.SetSceneImage("nd:1", 3, img2));
                Assert.True(w.ShowFrame(Frame(rev: 4, imageAction: "clear")));
                Assert.False(w.HasSceneImageForTest);
                Assert.False(w.ScenePendingForTest);
                // clear 后 keep 不复活
                Assert.True(w.ShowFrame(Frame(rev: 5, imageAction: "keep")));
                Assert.False(w.HasSceneImageForTest);
            }
        }

        [Fact]
        public void SceneImage_LateAfterClear_Rejected()
        {
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                w.ShowFrame(Frame(rev: 1, imageAction: "show", imagePath: "a.png"));
                w.ShowFrame(Frame(rev: 2, imageAction: "clear"));
                using (Bitmap late = Bmp(10, 10))
                    Assert.False(w.SetSceneImage("nd:1", 2, late));   // rev2 不要图
                Assert.False(w.HasSceneImageForTest);
            }
        }

        // ──────────────── 鼠标手势 ────────────────

        [Fact]
        public void Mouse_DownUpOnBody_CompletesTypingThenAdvances()
        {
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                List<string> verbs = new List<string>();
                w.InputRequested = (f, v) => verbs.Add(v);
                w.ShowFrame(Frame(text: "长按对白测试文本"));
                NativeDialogueWidget.Layout L = w.ComputeLayoutForTest(vp.R);
                Point pt = PanelCenter(L);

                w.OnMouseEvent(LeftAt(pt.X, pt.Y), MouseEventKind.Down);
                Assert.True(w.GestureArmedForTest);
                w.OnMouseEvent(LeftAt(pt.X, pt.Y), MouseEventKind.Up);
                Assert.True(w.TypingCompleteForTest);   // 第 1 击补全
                Assert.Empty(verbs);

                w.OnMouseEvent(LeftAt(pt.X, pt.Y), MouseEventKind.Down);
                w.OnMouseEvent(LeftAt(pt.X, pt.Y), MouseEventKind.Up);
                Assert.Equal(new[] { "advance" }, verbs);
            }
        }

        [Fact]
        public void Mouse_CrossRevisionUp_DoesNotAdvance()
        {
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                List<string> verbs = new List<string>();
                w.InputRequested = (f, v) => verbs.Add(v);
                w.ShowFrame(Frame(rev: 1));
                NativeDialogueWidget.Layout L = w.ComputeLayoutForTest(vp.R);
                Point pt = PanelCenter(L);

                w.OnMouseEvent(LeftAt(pt.X, pt.Y), MouseEventKind.Down);   // armed@rev1
                Assert.True(w.ShowFrame(Frame(rev: 2, text: "新句")));      // 期间换句
                w.OnMouseEvent(LeftAt(pt.X, pt.Y), MouseEventKind.Up);     // 迟到 Up
                Assert.Empty(verbs);                                      // 不推进
                Assert.False(w.GestureArmedForTest);
                // 旧手势的 Up 不补全新句打字（跨修订手势整体作废）
                Assert.False(w.TypingCompleteForTest);
            }
        }

        [Fact]
        public void Mouse_FastSecondClick_OnlyCompletesNewLine()
        {
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                List<string> verbs = new List<string>();
                w.InputRequested = (f, v) => verbs.Add(v);
                w.ShowFrame(Frame(rev: 1, text: "第一句"));
                FinishTyping(w);
                NativeDialogueWidget.Layout L = w.ComputeLayoutForTest(vp.R);
                Point pt = PanelCenter(L);

                // 第 1 击：advance
                w.OnMouseEvent(LeftAt(pt.X, pt.Y), MouseEventKind.Down);
                w.OnMouseEvent(LeftAt(pt.X, pt.Y), MouseEventKind.Up);
                Assert.Equal(new[] { "advance" }, verbs);

                // AS2 推新句；双击第 2 击落在 rev2 打字上 → 只补全不 advance
                Assert.True(w.ShowFrame(Frame(rev: 2, line: 1, text: "第二句未读完")));
                w.OnMouseEvent(LeftAt(pt.X, pt.Y), MouseEventKind.Down);
                w.OnMouseEvent(LeftAt(pt.X, pt.Y), MouseEventKind.Up);
                Assert.Equal(new[] { "advance" }, verbs);   // 仍只有 1 次
                Assert.True(w.TypingCompleteForTest);
            }
        }

        [Fact]
        public void Mouse_DownBodyUpClose_MismatchIgnored()
        {
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                List<string> verbs = new List<string>();
                w.InputRequested = (f, v) => verbs.Add(v);
                w.ShowFrame(Frame());
                FinishTyping(w);
                NativeDialogueWidget.Layout L = w.ComputeLayoutForTest(vp.R);
                Point body = PanelCenter(L);
                Point close = new Point(L.Close.X + L.Close.Width / 2,
                    L.Close.Y + L.Close.Height / 2);

                w.OnMouseEvent(LeftAt(body.X, body.Y), MouseEventKind.Down);
                w.OnMouseEvent(LeftAt(close.X, close.Y), MouseEventKind.Up);  // zone 换边
                Assert.Empty(verbs);

                // 干净按下关闭钮 → close
                w.OnMouseEvent(LeftAt(close.X, close.Y), MouseEventKind.Down);
                w.OnMouseEvent(LeftAt(close.X, close.Y), MouseEventKind.Up);
                Assert.Equal(new[] { "close" }, verbs);
            }
        }

        [Fact]
        public void Mouse_CancelAndLeave_DisarmWithoutVerb()
        {
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                List<string> verbs = new List<string>();
                w.InputRequested = (f, v) => verbs.Add(v);
                w.ShowFrame(Frame());
                NativeDialogueWidget.Layout L = w.ComputeLayoutForTest(vp.R);
                Point pt = PanelCenter(L);
                w.OnMouseEvent(LeftAt(pt.X, pt.Y), MouseEventKind.Down);
                w.OnMouseEvent(LeftAt(pt.X, pt.Y), MouseEventKind.Cancel);   // 失焦
                Assert.False(w.GestureArmedForTest);
                w.OnMouseEvent(LeftAt(pt.X, pt.Y), MouseEventKind.Up);       // 无 armed → 无动作
                Assert.Empty(verbs);
                Assert.True(w.Visible);                                     // 会话保留
            }
        }

        // ──────────────── 压隐/恢复 ────────────────

        [Fact]
        public void Suppress_HidesKeepsSession_ResumeContinues()
        {
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                List<string> verbs = new List<string>();
                w.InputRequested = (f, v) => verbs.Add(v);
                w.ShowFrame(Frame(text: "压隐恢复测试"));
                NativeDialogueWidget.Layout L = w.ComputeLayoutForTest(vp.R);
                Point pt = PanelCenter(L);
                w.OnMouseEvent(LeftAt(pt.X, pt.Y), MouseEventKind.Down);    // armed
                w.Tick(50);
                int typedMid = w.VisibleCharsForTest;

                w.SetHostSuppressed(true);
                Assert.True(w.SuppressedForTest);
                Assert.False(w.Visible);
                Assert.Equal(Rectangle.Empty, w.ScreenBounds);
                Assert.False(w.GestureArmedForTest);                      // 手势取消
                Assert.False(w.WantsAnimationTick);                       // 打字暂停
                Assert.NotNull(w.CurrentFrame);                           // 会话保留
                Assert.Empty(verbs);                                      // 压隐不发 close
                w.Tick(500);                                              // 压隐中 tick 不推进
                Assert.Equal(typedMid, w.VisibleCharsForTest);
                Assert.False(w.TryAdvance());                             // 压隐中输入无效

                w.SetHostSuppressed(false);
                Assert.True(w.Visible);
                Assert.True(w.ScreenBounds.Width > 0);
                Assert.True(w.WantsAnimationTick);                        // 打字恢复
                FinishTyping(w);
                Assert.True(w.TypingCompleteForTest);
            }
        }

        // ──────────────── 缩放 / 版面 / 长文 ────────────────

        [Fact]
        public void Layout_ScalesWithViewport()
        {
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                w.ShowFrame(Frame());
                using (Bitmap p = Bmp(200, 400)) w.SetPortrait("nd:1", 1, p);
                NativeDialogueWidget.Layout a = w.ComputeLayoutForTest(vp.R);

                // 原版 stageRect（1024×576 逻辑，scale=1.0 时 ≈ 屏幕 px，边缘取整）
                Assert.Equal(Rectangle.FromLTRB(842, 340, 916, 422), a.Close);   // [841.57,339.57,916.23,421.91]
                Assert.Equal(Rectangle.FromLTRB(26, 382, 101, 465), a.Drag);     // [25.72,382.26,100.60,464.92]
                Assert.Equal(Rectangle.FromLTRB(96, 439, 897, 582), a.Next);     // [95.95,438.98,896.88,582.10]
                Assert.Equal(Rectangle.FromLTRB(101, 443, 884, 562), a.Text);    // 正文字段 [101.25,443.3,883.8,561.66]
                // 名/称号字段（深色头条内白字）
                Assert.Equal(Rectangle.FromLTRB(110, 406, 338, 438), a.Name);    // [109.65,406,337.55,437.7]
                Assert.Equal(Rectangle.FromLTRB(346, 418, 534, 437), a.Title);   // [346.4,418.25,533.5,436.7]
                // 立绘 mask 矩形（路径外接框近似）
                Assert.Equal(Rectangle.FromLTRB(30, 30, 910, 419), a.PortraitClip);

                vp.R = new Rectangle(0, 0, 1920, 1080);                     // 1080p: scale=1.875
                NativeDialogueWidget.Layout b = w.ComputeLayoutForTest(vp.R);

                // 两边各自取整后再求宽，不等于把已取整的宽再次缩放，容许一像素差。
                Assert.InRange(Math.Abs(a.Panel.Width * 1.875 - b.Panel.Width), 0, 1.5);
                // 立绘 AR 适配进 560×352 逻辑框：200×400 → 176×352，底锚 405
                Assert.Equal(352, (int)Math.Round(a.Portrait.Height / 1.0, 0));
                Assert.Equal(352, (int)Math.Round(b.Portrait.Height / 1.875, 0));
                Assert.True(a.Portrait.Height >= 300);
                Assert.True(b.Portrait.Height >= 560);
                Assert.Equal(405, (int)Math.Round((double)a.Portrait.Bottom, 0));
                // 面板美术仍在视口内（底可略超 576，原版即出血）
                Assert.True(a.Panel.Bottom <= 600);
            }
        }

        [Fact]
        public void Layout_PortraitFitsWideBitmap()
        {
            // 横图：宽封顶 560 逻辑，底锚 405、中心 x=325（原外部立绘注册）。
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                w.ShowFrame(Frame());
                NativeDialogueWidget.Layout L = w.ComputeLayoutForTest(vp.R);
                Rectangle r = NativeDialogueWidget.ComputePortraitDest(
                    new Size(600, 300), L);
                Assert.Equal(560, r.Width);
                Assert.Equal(280, r.Height);
                Assert.Equal(405, r.Bottom);
                Assert.Equal(325, r.X + r.Width / 2);
            }
        }

        [Fact]
        public void LongText_WrapsAndScrolls_NoOverflow()
        {
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                string longText = new string('汉', 300);
                w.ShowFrame(Frame(text: longText));
                int lines = w.PlanLineCountForTest;
                Assert.True(lines > 4, "expected >4 wrapped lines, got " + lines);
                // 容量 = 皮肤字段局部高 / 局部行高（与 PaintBody 同公式，与 viewport 无关）
                int capacity = w.BodyCapacityLines;
                NativeDialogueWidget.Layout L = w.ComputeLayoutForTest(vp.R);
                FinishTyping(w);
                int first = w.FirstVisibleLineForTest(int.MaxValue, capacity);
                Assert.Equal(Math.Max(0, lines - capacity), first);
                Assert.True(w.OnMouseWheel(new Point(L.Panel.X + 30, L.Panel.Y + 70), 120));
                Assert.True(w.FirstVisibleLineForTest(int.MaxValue, capacity) < first);
                Assert.False(w.OnMouseWheel(new Point(0, 0), 120));
                // 渲染不抛、不越界（clip 内）
                using (Bitmap bmp = new Bitmap(1024, 576))
                using (Graphics g = Graphics.FromImage(bmp))
                    w.Paint(g, 1f, w.ScreenBounds.Location);
            }
        }

        [Fact]
        public void EmptyText_TypingInstantlyComplete()
        {
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                w.ShowFrame(Frame(text: ""));
                Assert.True(w.TypingCompleteForTest);
                Assert.False(w.WantsAnimationTick);
            }
        }

        // ──────────────── HTML 子集排版（注入确定性 measure）────────────────

        [Fact]
        public void TextLayout_FontColorAndBr_ParsedToRunsAndLines()
        {
            NativeDialogueTextLayout.Plan plan = NativeDialogueTextLayout.Build(
                "白色<font color='#FF0000'>红色</font><BR>第二行", 10000,
                c => 10f);
            Assert.True(plan.Lines.Count >= 2);
            // 第 1 行含红色 run
            bool hasRed = false;
            foreach (NativeDialogueTextLayout.Line l in plan.Lines)
                foreach (NativeDialogueTextLayout.Run r in l.Runs)
                    if (r.Color.R == 255 && r.Color.G == 0 && r.Color.B == 0)
                        hasRed = true;
            Assert.True(hasRed);
            // glyph 总数 = 可见字 + '\n'（"白色"+"红色"+\n+"第二行"）
            Assert.Equal(2 + 2 + 1 + 3, plan.TotalGlyphs);
        }

        [Fact]
        public void TextLayout_WrapsPerChar_AndRespectsPunctRules()
        {
            // 每字 10px、行宽 105：第 11 字触发折行
            NativeDialogueTextLayout.Plan plan = NativeDialogueTextLayout.Build(
                "一二三四五六七八九十，不可断", 105, c => 10f);
            // "，" 是闭标点不能行首 → "十" 被回溯到下行
            Assert.Equal(2, plan.Lines.Count);
            Assert.Equal("一二三四五六七八九", Concat(plan.Lines[0]));
            Assert.Equal("十，不可断", Concat(plan.Lines[1]));
        }

        [Fact]
        public void TextLayout_OpeningPunct_MovesDown()
        {
            NativeDialogueTextLayout.Plan plan = NativeDialogueTextLayout.Build(
                "一二三四五六七八九（开元", 105, c => 10f);
            Assert.Equal(2, plan.Lines.Count);
            Assert.Equal("一二三四五六七八九", Concat(plan.Lines[0]));
            Assert.Equal("（开元", Concat(plan.Lines[1]));
        }

        [Fact]
        public void TextLayout_LongLatinRun_HardWrapsNoOverflow()
        {
            NativeDialogueTextLayout.Plan plan = NativeDialogueTextLayout.Build(
                new string('x', 25), 100, c => 10f);
            Assert.Equal(3, plan.Lines.Count);
            foreach (NativeDialogueTextLayout.Line l in plan.Lines)
                Assert.True(l.WidthF <= 100.5f);
        }

        [Fact]
        public void TextLayout_EmptyAndTagOnly_ZeroGlyphs()
        {
            Assert.Equal(0, NativeDialogueTextLayout.Build("", 100, c => 10f).TotalGlyphs);
            Assert.Equal(0, NativeDialogueTextLayout.Build("<b></b>", 100, c => 10f).TotalGlyphs);
        }

        private static string Concat(NativeDialogueTextLayout.Line line)
        {
            System.Text.StringBuilder sb = new System.Text.StringBuilder();
            foreach (NativeDialogueTextLayout.Run r in line.Runs) sb.Append(r.Text);
            return sb.ToString();
        }

        // ──────────────── 原版热区 / 拖动 / 皮肤 ────────────────

        [Fact]
        public void Zones_OriginalStageRects_AndDeadStrip()
        {
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                List<string> verbs = new List<string>();
                w.InputRequested = (f, v) => verbs.Add(v);
                w.ShowFrame(Frame());
                NativeDialogueWidget.Layout L = w.ComputeLayoutForTest(vp.R);

                // 三个原版热区可命中；面板吸收区整体也命中（点击不透到游戏世界），
                // 但死区 Down/Up 不派发任何动作。
                Assert.True(w.TryHitTest(new Point(
                    L.Close.X + L.Close.Width / 2, L.Close.Y + L.Close.Height / 2)));
                Assert.True(w.TryHitTest(new Point(
                    L.Drag.X + L.Drag.Width / 2, L.Drag.Y + L.Drag.Height / 2)));
                Assert.True(w.TryHitTest(PanelCenter(L)));
                Point dead = new Point(L.Panel.X + L.Panel.Width / 2, L.Panel.Y + 15);
                Assert.True(w.TryHitTest(dead));

                // 死区点击：不武装手势、不推进、不补全打字
                w.OnMouseEvent(LeftAt(dead.X, dead.Y), MouseEventKind.Down);
                w.OnMouseEvent(LeftAt(dead.X, dead.Y), MouseEventKind.Up);
                Assert.False(w.GestureArmedForTest);
                Assert.False(w.TypingCompleteForTest);
                Assert.Empty(verbs);
            }
        }

        [Fact]
        public void Drag_HandleTranslatesPanel_NoVerb_PersistsAcrossLines()
        {
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                List<string> verbs = new List<string>();
                w.InputRequested = (f, v) => verbs.Add(v);
                w.ShowFrame(Frame(rev: 1));
                FinishTyping(w);
                NativeDialogueWidget.Layout L0 = w.ComputeLayoutForTest(vp.R);
                Point grab = new Point(L0.Drag.X + L0.Drag.Width / 2,
                    L0.Drag.Y + L0.Drag.Height / 2);

                w.OnMouseEvent(LeftAt(grab.X, grab.Y), MouseEventKind.Down);
                Assert.True(w.GestureArmedForTest);
                w.OnMouseEvent(LeftAt(grab.X + 50, grab.Y + 20), MouseEventKind.Move);
                w.OnMouseEvent(LeftAt(grab.X + 50, grab.Y + 20), MouseEventKind.Up);
                // scale=1：屏幕 50/20px = 逻辑 50/20
                Assert.Equal(50, (int)Math.Round(w.DragOffsetForTest.X));
                Assert.Equal(20, (int)Math.Round(w.DragOffsetForTest.Y));
                Assert.Empty(verbs);    // 拖动柄不产生 advance/close

                NativeDialogueWidget.Layout L1 = w.ComputeLayoutForTest(vp.R);
                Assert.Equal(L0.Panel.Left + 50, L1.Panel.Left);
                Assert.Equal(L0.Close.Left + 50, L1.Close.Left);   // 关闭钮随面板
                Assert.Equal(L0.Next.Top + 20, L1.Next.Top);

                // 原版 clip 位置常驻：跨句不回弹
                Assert.True(w.ShowFrame(Frame(rev: 2, line: 1, text: "换句后仍在拖动位")));
                NativeDialogueWidget.Layout L2 = w.ComputeLayoutForTest(vp.R);
                Assert.Equal(L1.Panel.Left, L2.Panel.Left);
                Assert.Equal(L1.Panel.Top, L2.Panel.Top);
            }
        }

        [Fact]
        public void Drag_OffsetClamped_PanelNeverLost()
        {
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                w.ShowFrame(Frame());
                NativeDialogueWidget.Layout L0 = w.ComputeLayoutForTest(vp.R);
                Point grab = new Point(L0.Drag.X + 5, L0.Drag.Y + 5);
                w.OnMouseEvent(LeftAt(grab.X, grab.Y), MouseEventKind.Down);
                // 狂甩出界：钳制后面板仍至少 64×40 逻辑 px 留在舞台内
                w.OnMouseEvent(LeftAt(grab.X + 5000, grab.Y + 5000), MouseEventKind.Move);
                NativeDialogueWidget.Layout L = w.ComputeLayoutForTest(vp.R);
                Assert.True(L.Panel.Left <= vp.R.Right - 60);
                Assert.True(L.Panel.Top <= vp.R.Bottom - 35);
                w.OnMouseEvent(LeftAt(grab.X + 5000, grab.Y + 5000), MouseEventKind.Cancel);
                Assert.False(w.GestureArmedForTest);
            }
        }

        [Fact]
        public void Scene_DoesNotFollowDrag()
        {
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                w.ShowFrame(Frame(imageAction: "show", imagePath: "a.png"));
                using (Bitmap s = Bmp(200, 100)) w.SetSceneImage("nd:1", 1, s);
                NativeDialogueWidget.Layout L0 = w.ComputeLayoutForTest(vp.R);
                Point grab = new Point(L0.Drag.X + 5, L0.Drag.Y + 5);
                w.OnMouseEvent(LeftAt(grab.X, grab.Y), MouseEventKind.Down);
                w.OnMouseEvent(LeftAt(grab.X + 40, grab.Y), MouseEventKind.Move);
                w.OnMouseEvent(LeftAt(grab.X + 40, grab.Y), MouseEventKind.Cancel);
                NativeDialogueWidget.Layout L1 = w.ComputeLayoutForTest(vp.R);
                Assert.Equal(L0.Scene, L1.Scene);      // 配图在 _root.图片容器，不随拖动
                Assert.NotEqual(L0.Panel, L1.Panel);
            }
        }

        [Fact]
        public void Skin_Fixture_LoadsLayoutAndRasters()
        {
            string dir = System.IO.Path.Combine(
                System.IO.Path.GetTempPath(), "cf7-dialogue-ui-fixture-" + Guid.NewGuid().ToString("N"));
            try
            {
                System.IO.Directory.CreateDirectory(System.IO.Path.Combine(dir, "buttons"));
                System.IO.File.WriteAllText(System.IO.Path.Combine(dir, "source.svg"),
                    "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1024 576\">"
                    + "<path d=\"M0 0L1024 0L1024 576L0 576Z\" fill=\"#E5E5E5\"/></svg>");
                System.IO.File.WriteAllText(System.IO.Path.Combine(dir, "layout.json"),
                    "{\"fields\":[],\"buttons\":[{\"id\":\"next\",\"hitTestOnly\":true,"
                    + "\"stageRect\":[10,20,500,60]}]}");
                using (DialogueUiSkin skin = DialogueUiSkin.TryLoad(dir))
                {
                    Assert.NotNull(skin);
                    Assert.True(skin.HasStageArt);
                    // layout.json 覆盖默认热区
                    Assert.Equal(10, skin.NextHit.Left, 3);
                    Assert.Equal(500, skin.NextHit.Right, 3);
                    // 光栅缓存归皮肤所有：同尺寸重取应返回同一实例，不可由调用方释放
                    Bitmap stage = skin.RasterStage(1f);
                    Assert.NotNull(stage);
                    Assert.Equal(1024, stage.Width);
                    Assert.Equal(576, stage.Height);
                    Assert.Same(stage, skin.RasterStage(1f));
                    Assert.NotSame(stage, skin.RasterStage(2f));
                }
            }
            finally
            {
                try { System.IO.Directory.Delete(dir, true); } catch { }
            }
        }

        [Fact]
        public void Skin_MissingDir_ReturnsNullAndWidgetStillPaints()
        {
            Assert.Null(DialogueUiSkin.TryLoad(
                System.IO.Path.Combine(System.IO.Path.GetTempPath(),
                    "cf7-no-such-dir-" + Guid.NewGuid().ToString("N"))));
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))   // skin=null → 保底装饰
            {
                w.ShowFrame(Frame(text: "无资产保底渲染"));
                FinishTyping(w);
                using (Bitmap bmp = new Bitmap(1024, 576))
                using (Graphics g = Graphics.FromImage(bmp))
                    w.Paint(g, 1f, new Point(0, 0));    // 不抛
            }
        }

        // ──────────────── 渲染烟测（快照产物存 tmp）────────────────

        /// <summary>保底路径（skin=null → GDI 原版近似装饰）。SVG 路径由 Skin_Fixture 覆盖。</summary>
        [Fact]
        public void Paint_FullFrame_DoesNotThrow()
        {
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                w.ShowFrame(Frame(
                    text: "中文长句渲染测试：辽远的<font color='#FFD700'>废土</font>上，风还在吹。<BR>第二行内容。",
                    imageAction: "show", imagePath: "img/x.png"));
                using (Bitmap p = Bmp(220, 420)) w.SetPortrait("nd:1", 1, p);
                using (Bitmap s = Bmp(400, 240)) w.SetSceneImage("nd:1", 1, s);
                FinishTyping(w);
                using (Bitmap bmp = new Bitmap(1024, 576))
                {
                    using (Graphics g = Graphics.FromImage(bmp))
                    {
                        g.Clear(Color.FromArgb(30, 30, 34));
                        // hudOrigin=(0,0)：按真实舞台坐标画进全画布，便于人眼核对布局
                        w.Paint(g, 1f, new Point(0, 0));
                    }
                    // 快照：供主控/人工抽查视觉
                    try
                    {
                        string dir = System.IO.Path.Combine(
                            AppDomain.CurrentDomain.BaseDirectory,
                            "..", "..", "..", "..", "tmp", "u2-dialogue-20260913", "C");
                        System.IO.Directory.CreateDirectory(dir);
                        bmp.Save(System.IO.Path.Combine(dir, "dialogue-paint-smoke.png"),
                            System.Drawing.Imaging.ImageFormat.Png);
                    }
                    catch { /* 快照失败不影响测试结论 */ }
                }
            }
        }

        // ──────────────── J5：作者取景 / 纸娃娃窗 / separate 钮 / 文本与命中合同 ────────────────

        [Fact]
        public void Portrait_ExternalSwfStageRect_PreservesAuthorCrops()
        {
            // F1：两个不同 union∩window crop 各自按作者取景 1:1 落舞台，
            // 不归一到 560×352/cx325 统一 fit。
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                w.ShowFrame(Frame(rev: 1));
                using (Bitmap a = Bmp(100, 100))
                    Assert.True(w.SetPortrait("nd:1", 1, a,
                        new RectangleF(89f, 71.5f, 472f, 333.5f)));
                NativeDialogueWidget.Layout la = w.ComputeLayoutForTest(vp.R);
                Assert.Equal(Rectangle.FromLTRB(89, 72, 561, 405), la.Portrait);
                Assert.Equal(Rectangle.FromLTRB(30, 30, 910, 419), la.PortraitClip); // 外部 mask

                Assert.True(w.ShowFrame(Frame(rev: 2, portrait: "The Girl")));   // 换人 → 重等
                using (Bitmap b = Bmp(80, 60))
                    Assert.True(w.SetPortrait("nd:1", 2, b,
                        new RectangleF(172f, 53f, 294f, 352f)));
                NativeDialogueWidget.Layout lb = w.ComputeLayoutForTest(vp.R);
                Assert.Equal(Rectangle.FromLTRB(172, 53, 466, 405), lb.Portrait);
                Assert.NotEqual(la.Portrait, lb.Portrait);
            }
        }

        [Fact]
        public void Portrait_StaleRevisionMetadata_CannotReframeNewLine()
        {
            // 旧 revision 的（位图, 取景）整包被拒：新句取景不被动。
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                w.ShowFrame(Frame(rev: 1));
                using (Bitmap p = Bmp(100, 100))
                    Assert.True(w.SetPortrait("nd:1", 1, p, new RectangleF(60f, 30f, 300f, 375f)));
                NativeDialogueWidget.Layout before = w.ComputeLayoutForTest(vp.R);

                // 同身份下一行：位图与取景保留；此时迟到的 rev1 投递必须整包丢弃。
                Assert.True(w.ShowFrame(Frame(rev: 2, text: "同一立绘的下一行")));
                using (Bitmap late = Bmp(50, 50))
                    Assert.False(w.SetPortrait("nd:1", 1, late,
                        new RectangleF(400f, 0f, 500f, 500f)));
                NativeDialogueWidget.Layout after = w.ComputeLayoutForTest(vp.R);
                Assert.Equal(before.Portrait, after.Portrait);
            }
        }

        [Fact]
        public void Portrait_Doll_UsesInternalPortraitWindow()
        {
            // 纸娃娃栅格覆盖原作窗口左上角的 425.2² 逻辑区域；
            // 高度超出内部 mask 的部分由原作 365.25 高的窗口裁掉。
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                NativeDialogueFrame f = Frame(rev: 1, portrait: "self");
                f.IsDoll = true;
                w.ShowFrame(f);
                using (Bitmap p = Bmp(768, 768))
                    Assert.True(w.SetPortrait("nd:1", 1, p));
                NativeDialogueWidget.Layout L = w.ComputeLayoutForTest(vp.R);

                Assert.InRange(L.PortraitClip.Left, 29, 31);      // ≈29.55
                Assert.InRange(L.PortraitClip.Top, 40, 42);       // ≈40.95
                Assert.InRange(L.PortraitClip.Right, 454, 456);   // ≈454.75
                Assert.InRange(L.PortraitClip.Bottom, 405, 407);  // ≈406.2
                // 固定作者窗口还原骨架尺寸，禁止再次按人物包围盒适配。
                Assert.InRange(L.Portrait.Width, 424, 427);
                Assert.InRange(L.Portrait.Height, 424, 427);
                Assert.Equal(L.PortraitClip.Left, L.Portrait.Left);
                Assert.Equal(L.PortraitClip.Top, L.Portrait.Top);
                Assert.InRange(L.Portrait.Left + L.Portrait.Width / 2, 241, 243);
                Assert.InRange(L.Portrait.Bottom, 465, 468);
                Assert.True(L.Portrait.Bottom > L.PortraitClip.Bottom);
            }
        }

        [Fact]
        public void HitTest_ClippedToViewport()
        {
            // F8：next 热区底缘探出舞台底（≈582>576），viewport 外的点不命中。
            Vp vp = new Vp(1024, 576);
            using (NativeDialogueWidget w = MakeWidget(vp))
            {
                w.ShowFrame(Frame());
                NativeDialogueWidget.Layout L = w.ComputeLayoutForTest(vp.R);
                Assert.True(L.Next.Bottom > vp.R.Bottom);   // 原版热区确实出血

                int midX = L.Next.X + L.Next.Width / 2;
                Assert.False(w.TryHitTest(new Point(midX, vp.R.Bottom + 2)));
                Assert.True(w.TryHitTest(new Point(midX, vp.R.Bottom - 2)));
                // zone 派发同样被裁：出血带按下不武装手势
                w.OnMouseEvent(LeftAt(midX, vp.R.Bottom + 2), MouseEventKind.Down);
                Assert.False(w.GestureArmedForTest);
            }
        }

        [Fact]
        public void TextLayout_HtmlFalse_KeepsLiteralMarkup()
        {
            // F5：name 字段 html=false → 原文直排，<b> 标签按字面保留不剥离。
            Assert.False(DialogueUiSkin.CreateSpecOnly().Name.Html);
            Assert.True(DialogueUiSkin.CreateSpecOnly().Body.Html);

            NativeDialogueTextLayout.Plan raw = NativeDialogueTextLayout.Build(
                "A<b>B</b>", 10000, c => 10f, null, false);
            Assert.Equal(9, raw.TotalGlyphs);   // "A<b>B</b>" 全 9 字符都是可见 glyph
            Assert.Equal("A<b>B</b>", Concat(raw.Lines[0]));

            NativeDialogueTextLayout.Plan html = NativeDialogueTextLayout.Build(
                "A<b>B</b>", 10000, c => 10f, null, true);
            Assert.Equal("AB", Concat(html.Lines[0]));   // 对照：html 路径仍剥离
        }

        [Fact]
        public void Skin_SeparateButtons_SelectedStateOnly_HitRectAndDollClip()
        {
            // H6 合同：buttonRendering="separate" → source.svg 无 up 底图，
            // widget 只画所选唯一状态；hitRect 优先于 stageRect；internalPortraitClip 覆盖内部窗。
            string dir = System.IO.Path.Combine(
                System.IO.Path.GetTempPath(), "cf7-dialogue-sep-" + Guid.NewGuid().ToString("N"));
            try
            {
                System.IO.Directory.CreateDirectory(System.IO.Path.Combine(dir, "buttons"));
                System.IO.File.WriteAllText(System.IO.Path.Combine(dir, "source.svg"),
                    "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1024 576\">"
                    + "<path d=\"M0 0L1024 0L1024 576L0 576Z\" fill=\"#E5E5E5\"/></svg>");
                System.IO.File.WriteAllText(System.IO.Path.Combine(dir, "layout.json"),
                    "{\"buttonRendering\":\"separate\",\"fields\":[],"
                    + "\"buttons\":["
                    + "{\"id\":\"close\",\"stageRect\":[10,10,50,50],\"hitRect\":[12,14,48,46],"
                    + "\"matrix\":[1,0,0,1,30,40]},"
                    + "{\"id\":\"drag\",\"stageRect\":[60,60,100,100],\"matrix\":[1,0,0,1,200,60]}"
                    + "],"
                    + "\"clips\":{\"internalPortraitClip\":\"M0 0L100 0L100 80L0 80Z\"}}");
                // up=红、down=蓝的 20×20 钮（viewBox 局部 (-10,-10,20,20)，matrix 平移到舞台）
                string btnSvg = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"-10 -10 20 20\">"
                    + "<rect x=\"-10\" y=\"-10\" width=\"20\" height=\"20\" fill=\"{0}\"/></svg>";
                foreach (string id in new[] { "close", "drag" })
                {
                    System.IO.File.WriteAllText(System.IO.Path.Combine(
                        dir, "buttons", id + "-up.svg"), string.Format(btnSvg, "#FF0000"));
                    System.IO.File.WriteAllText(System.IO.Path.Combine(
                        dir, "buttons", id + "-down.svg"), string.Format(btnSvg, "#0000FF"));
                }

                using (DialogueUiSkin skin = DialogueUiSkin.TryLoad(dir))
                {
                    Assert.NotNull(skin);
                    Assert.True(skin.ButtonsSeparate);
                    Assert.True(skin.HasStageArt);
                    // hitRect 覆盖 stageRect；未给 hitRect 的 drag 用 stageRect
                    Assert.Equal(12, skin.Close.Hit.Left, 3);
                    Assert.Equal(48, skin.Close.Hit.Right, 3);
                    Assert.Equal(60, skin.Drag.Hit.Left, 3);
                    // internalPortraitClip 覆盖内置纸娃娃窗
                    Assert.Equal(100, skin.DollClip.Right, 3);
                    Assert.Equal(80, skin.DollClip.Bottom, 3);

                    using (NativeDialogueWidget w = new NativeDialogueWidget(
                        new Control(), delegate { return new Rectangle(0, 0, 1024, 576); }, skin))
                    {
                        w.ShowFrame(Frame(text: "", portrait: ""));
                        using (Bitmap bmp = new Bitmap(1024, 576))
                        {
                            using (Graphics g = Graphics.FromImage(bmp))
                            {
                                g.Clear(Color.Black);
                                w.Paint(g, 1f, new Point(0, 0));
                            }
                            // 无悬停也画 up 态：close 钮 up=红，落在 matrix(30,40)+viewBox 偏移
                            // → 舞台 (20,30)-(40,50)，中心 (30,40)。
                            Color up = bmp.GetPixel(30, 40);
                            Assert.True(up.R > 200 && up.G < 80 && up.B < 80,
                                "separate 模式未画所选 up 态: " + up);
                        }

                        // 按下后只画 down 态（蓝），不残留 up 底色
                        NativeDialogueWidget.Layout L = w.ComputeLayoutForTest(
                            new Rectangle(0, 0, 1024, 576));
                        Point close = new Point(L.Close.X + L.Close.Width / 2,
                            L.Close.Y + L.Close.Height / 2);
                        w.OnMouseEvent(LeftAt(close.X, close.Y), MouseEventKind.Down);
                        using (Bitmap bmp = new Bitmap(1024, 576))
                        {
                            using (Graphics g = Graphics.FromImage(bmp))
                            {
                                g.Clear(Color.Black);
                                w.Paint(g, 1f, new Point(0, 0));
                            }
                            Color down = bmp.GetPixel(30, 40);
                            Assert.True(down.B > 200 && down.R < 80,
                                "按下态不应残留 up 红色: " + down);
                        }
                        w.OnMouseEvent(LeftAt(close.X, close.Y), MouseEventKind.Cancel);
                    }
                }
            }
            finally
            {
                try { System.IO.Directory.Delete(dir, true); } catch { }
            }
        }

        [Fact]
        public void Skin_BakedUpContract_KeepsOverlayOnlyBehavior()
        {
            // 旧合同（无 buttonRendering 标志）：up 烘焙在 source.svg，无悬停/按下不叠画任何态。
            string dir = System.IO.Path.Combine(
                System.IO.Path.GetTempPath(), "cf7-dialogue-baked-" + Guid.NewGuid().ToString("N"));
            try
            {
                System.IO.Directory.CreateDirectory(System.IO.Path.Combine(dir, "buttons"));
                // source.svg 自带红色钮底（up 已烘焙）
                System.IO.File.WriteAllText(System.IO.Path.Combine(dir, "source.svg"),
                    "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1024 576\">"
                    + "<path d=\"M0 0L1024 0L1024 576L0 576Z\" fill=\"#E5E5E5\"/>"
                    + "<rect x=\"20\" y=\"30\" width=\"20\" height=\"20\" fill=\"#FF0000\"/></svg>");
                System.IO.File.WriteAllText(System.IO.Path.Combine(dir, "layout.json"),
                    "{\"fields\":[],\"buttons\":[]}");
                using (DialogueUiSkin skin = DialogueUiSkin.TryLoad(dir))
                {
                    Assert.NotNull(skin);
                    Assert.False(skin.ButtonsSeparate);
                    using (NativeDialogueWidget w = new NativeDialogueWidget(
                        new Control(), delegate { return new Rectangle(0, 0, 1024, 576); }, skin))
                    {
                        w.ShowFrame(Frame(text: "", portrait: ""));
                        using (Bitmap bmp = new Bitmap(1024, 576))
                        {
                            using (Graphics g = Graphics.FromImage(bmp))
                            {
                                g.Clear(Color.Black);
                                w.Paint(g, 1f, new Point(0, 0));
                            }
                            // 烘焙 up 照常可见（没有被 widget 额外叠画改动色相）
                            Color up = bmp.GetPixel(30, 40);
                            Assert.True(up.R > 200 && up.G < 80,
                                "baked-up 底色应原样保留: " + up);
                        }
                    }
                }
            }
            finally
            {
                try { System.IO.Directory.Delete(dir, true); } catch { }
            }
        }
    }
}
