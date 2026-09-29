using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using CF7Launcher.Guardian.WorldCompositor;
using Xunit;

namespace CF7Launcher.Tests.Guardian
{
    public sealed class ProjectileVisualCapabilityTests
    {
        [Fact]
        public void LateOldDisconnectCannotRevokeTheNewBulletConnection()
        {
            var sent = new List<(string Message, int Generation)>();
            var publisher = new BulletCapabilityPublisher("bullet-on", "bullet-off", "chain-on", "chain-off",
                (message, generation) => { sent.Add((message, generation)); return true; });
            Assert.True(publisher.Ready(11));
            Assert.True(publisher.Ready(12));
            sent.Clear();
            Assert.False(publisher.Disconnected(11));
            Assert.True(publisher.Publish(true));
            Assert.Equal(new[] { ("bullet-on", 12), ("chain-on", 12) }, sent);
            Assert.True(publisher.Disconnected(12));
            sent.Clear();
            Assert.False(publisher.Publish(true));
            Assert.Empty(sent);
        }

        [Fact]
        public void LateReadyCannotReplaceANewerConnectionOrReopenARetiredGeneration()
        {
            var sent = new List<(string Message, int Generation)>();
            var publisher = new BulletCapabilityPublisher("bullet-on", "bullet-off", "chain-on", "chain-off",
                (message, generation) => { sent.Add((message, generation)); return true; });
            Assert.True(publisher.Ready(11));
            Assert.True(publisher.Ready(12));
            sent.Clear();
            Assert.False(publisher.Ready(11));
            Assert.True(publisher.Ready(12));
            Assert.Empty(sent);
            Assert.True(publisher.Disconnected(12));
            Assert.False(publisher.Ready(12));
            Assert.False(publisher.Publish(true));
            Assert.Empty(sent);
            Assert.True(publisher.Ready(13));
            Assert.Equal(new[] { ("bullet-off", 13), ("chain-off", 13) }, sent);
        }

        [Fact]
        public void PartialBulletRevokeStillSendsChainRevokeAndRetriesBeforeRegrant()
        {
            var sent = new List<string>();
            bool failBullet = false;
            var publisher = new BulletCapabilityPublisher("bullet-on", "bullet-off", "chain-on", "chain-off",
                (message, generation) => { sent.Add(message); return !(failBullet && message == "bullet-off"); });
            Assert.True(publisher.Ready(4));
            Assert.True(publisher.Publish(true));
            sent.Clear();
            failBullet = true;
            var revoke = new VisualCapabilityRevocation();
            revoke.Request();
            Assert.False(revoke.TrySend(1000, () => publisher.Publish(false)));
            Assert.True(revoke.Pending);
            Assert.Equal(new[] { "bullet-off", "chain-off" }, sent);
            Assert.False(revoke.TrySend(1499, () => publisher.Publish(false)));
            Assert.Equal(2, sent.Count);
            failBullet = false;
            Assert.True(revoke.TrySend(1500, () => publisher.Publish(false)));
            Assert.False(revoke.Pending);
            Assert.Equal(new[] { "bullet-off", "chain-off", "bullet-off", "chain-off" }, sent);
        }

        [Fact]
        public void ThrowingSenderDoesNotForgetThePendingRevoke()
        {
            var revoke = new VisualCapabilityRevocation();
            revoke.Request();
            Assert.Throws<InvalidOperationException>(() => revoke.TrySend(0,
                () => throw new InvalidOperationException("local write failed")));
            Assert.True(revoke.Pending);
            Assert.False(revoke.TrySend(499, () => throw new Exception("must remain rate limited")));
            Assert.True(revoke.TrySend(500, () => true));
            Assert.False(revoke.Pending);
        }

        [Fact]
        public void SenderRunsOutsideStateLockAndCannotClearANewerRequest()
        {
            var revoke = new VisualCapabilityRevocation();
            revoke.Request();
            Assert.False(revoke.TrySend(0, () => {
                Assert.True(Task.Run(revoke.Request).Wait(TimeSpan.FromSeconds(3)),
                    "A callback must be able to enter state from another thread.");
                return true;
            }));
            Assert.True(revoke.Pending);
            Assert.True(revoke.TrySend(1, () => true));
            Assert.False(revoke.Pending);
        }

        [Fact]
        public void DisconnectionResetCancelsTheRetiredConnectionRetry()
        {
            var revoke = new VisualCapabilityRevocation();
            revoke.Request();
            Assert.False(revoke.TrySend(0, () => false));
            revoke.Reset();
            Assert.False(revoke.Pending);
            Assert.False(revoke.TrySend(1000, () => throw new Exception("retired connection must not send")));
        }

        [Theory]
        [InlineData(true, true, false, 7, 7, true)]
        [InlineData(false, true, false, 7, 7, false)]
        [InlineData(true, false, false, 7, 7, false)]
        [InlineData(true, true, true, 7, 7, false)]
        [InlineData(true, true, false, 8, 7, false)]
        public void CaptureOfTheOldSceneCannotGrantProjectileOwnership(bool captureReady, bool sceneReady,
            bool waiting, long scene, long capturedScene, bool expected)
        {
            Assert.Equal(expected, WorldCompositorController.CanGrantProjectileCapability(
                captureReady, sceneReady, waiting, scene, capturedScene));
        }
    }
}
