using System;
using System.Collections.Generic;
using CF7Launcher.Guardian;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class HostLifecycleSignalTests
    {
        [Theory]
        [InlineData(0UL, 5UL, true)]
        [InlineData(5UL, 5UL, false)]
        [InlineData(5UL, 6UL, true)]
        [InlineData(5UL, 0UL, false)]
        public void WebDocumentAdvanceOccursOnceAtNavigationStart(
            ulong currentNavigationId,
            ulong startingNavigationId,
            bool expected)
        {
            Assert.Equal(
                expected,
                WebOverlayForm
                    .ShouldAdvanceDocumentOnNavigationStart(
                        currentNavigationId,
                        startingNavigationId));
        }

        [Fact]
        public void PanelHostPublishesOpenRebindAndRetire()
        {
            var pumps = new Queue<Action>();
            var changed =
                new List<(string Name, string Instance)>();
            using var host = new PanelHostController(
                pumps.Enqueue,
                fire => fire());
            host.PanelChanged += (name, instance) =>
                changed.Add((name, instance));

            Assert.True(
                host.TryOpenPanel(
                    "help",
                    null,
                    null,
                    null));
            PumpOne(pumps);
            string firstInstance =
                host.ActivePanelInstanceId;

            Assert.True(
                host.TryOpenPanel(
                    "help",
                    null,
                    null,
                    null));
            PumpOne(pumps);
            string secondInstance =
                host.ActivePanelInstanceId;

            host.ClosePanel();
            PumpOne(pumps);

            Assert.NotEqual(
                firstInstance,
                secondInstance);
            Assert.Collection(
                changed,
                opened =>
                {
                    Assert.Equal("help", opened.Name);
                    Assert.Equal(
                        firstInstance,
                        opened.Instance);
                },
                rebound =>
                {
                    Assert.Equal("help", rebound.Name);
                    Assert.Equal(
                        secondInstance,
                        rebound.Instance);
                },
                retired =>
                {
                    Assert.Null(retired.Name);
                    Assert.Null(retired.Instance);
                });
        }

        [Fact]
        public void PanelChangedFailureDoesNotBreakHostCommand()
        {
            var pumps = new Queue<Action>();
            int healthySubscriberCalls = 0;
            using var host = new PanelHostController(
                pumps.Enqueue,
                fire => fire());
            host.PanelChanged += delegate
            {
                throw new InvalidOperationException(
                    "subscriber failure");
            };
            host.PanelChanged += delegate
            {
                healthySubscriberCalls++;
            };

            Assert.True(
                host.TryOpenPanel(
                    "help",
                    null,
                    null,
                    null));
            PumpOne(pumps);

            Assert.True(host.IsPanelOpen);
            Assert.Equal(
                "help",
                host.ActivePanelName);
            Assert.Equal(
                1,
                healthySubscriberCalls);
        }

        private static void PumpOne(
            Queue<Action> pumps)
        {
            Action pump = Assert.Single(pumps);
            pumps.Clear();
            pump();
        }
    }
}
