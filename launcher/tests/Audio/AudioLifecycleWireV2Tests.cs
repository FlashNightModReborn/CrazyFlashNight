using System.Collections.Generic;
using CF7Launcher.Audio;
using Newtonsoft.Json.Linq;
using Xunit;

namespace CF7Launcher.Tests.Audio
{
    public sealed class AudioLifecycleWireV2Tests
    {
        [Fact]
        public void Ready_UsesExactNineKeyEnvelopeAndDecimalEpochStrings()
        {
            string json;
            string error;
            Assert.True(AudioLifecycleWireV2.TrySerialize(
                Snapshot(AudioCoordinatorStatusV2.Ready, 7uL, 9uL,
                    AudioNativeV2.ResultOk, "audio.ready"),
                out json,
                out error), error);
            JObject value = JObject.Parse(json);
            Assert.Equal(9, value.Count);
            Assert.Equal("audio_ready", (string)value["task"]);
            Assert.Equal(2, (int)value["wireRevision"]);
            Assert.Equal("7", (string)value["audioReadyGeneration"]);
            Assert.Equal("9", (string)value["deviceGeneration"]);
            Assert.Equal(2, (int)value["loaded"]);
            Assert.Equal(0, (int)value["failed"]);
            Assert.Equal(1, (int)value["overrides"]);
            Assert.Null(value["generation"]);
            Assert.Null(value["connectionGeneration"]);
        }

        [Fact]
        public void Unavailable_UsesExactSevenKeyEnvelopeAndClosedCategory()
        {
            string json;
            string error;
            Assert.True(AudioLifecycleWireV2.TrySerialize(
                Snapshot(AudioCoordinatorStatusV2.Unavailable, 3uL, 0uL,
                    AudioNativeV2.ResultDeviceUnavailable,
                    "audio.device_unavailable"),
                out json,
                out error), error);
            JObject value = JObject.Parse(json);
            Assert.Equal(7, value.Count);
            Assert.Equal("audio_unavailable", (string)value["task"]);
            Assert.Equal("device_unavailable", (string)value["category"]);
            Assert.Equal("3", (string)value["audioReadyGeneration"]);
            Assert.Equal("0", (string)value["deviceGeneration"]);
        }

        [Theory]
        [InlineData(0uL, 1uL)]
        [InlineData(1uL, 0uL)]
        public void Ready_RejectsZeroEpochs(ulong ready, ulong device)
        {
            string json;
            string error;
            Assert.False(AudioLifecycleWireV2.TrySerialize(
                Snapshot(AudioCoordinatorStatusV2.Ready, ready, device,
                    AudioNativeV2.ResultOk, "audio.ready"),
                out json,
                out error));
            Assert.Equal("audio.lifecycle.ready_invalid", error);
        }

        [Fact]
        public void InvalidNativeMessageKey_IsProjectedToSafeUnavailableKey()
        {
            string json;
            string error;
            Assert.True(AudioLifecycleWireV2.TrySerialize(
                Snapshot(AudioCoordinatorStatusV2.Unavailable, 1uL, 0uL,
                    999u, "bad key with spaces"),
                out json,
                out error), error);
            JObject value = JObject.Parse(json);
            Assert.Equal("internal_error", (string)value["category"]);
            Assert.Equal("audio.lifecycle_invalid_state",
                (string)value["messageKey"]);
        }

        private static AudioCoordinatorSnapshotV2 Snapshot(
            AudioCoordinatorStatusV2 status,
            ulong ready,
            ulong device,
            uint category,
            string messageKey)
        {
            return new AudioCoordinatorSnapshotV2(
                status,
                "123e4567-e89b-42d3-a456-426614174000",
                ready,
                device,
                "C:\\game",
                new string('A', 64),
                2,
                0,
                1,
                category,
                messageKey,
                0f,
                0f,
                0f,
                0f,
                false,
                "none",
                0uL,
                0uL,
                0uL,
                0uL,
                0uL,
                0uL,
                0uL,
                new Dictionary<string, int>());
        }
    }
}
