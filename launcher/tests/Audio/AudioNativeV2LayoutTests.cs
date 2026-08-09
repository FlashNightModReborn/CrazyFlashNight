using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using CF7Launcher.Audio;
using Xunit;

namespace CF7Launcher.Tests.Audio
{
    public sealed class AudioNativeV2LayoutTests
    {
        [Fact]
        public void CrossBoundaryStructs_HaveFrozenPrefixPackAndSize()
        {
            Dictionary<Type, int> expectedSizes = new Dictionary<Type, int>
            {
                { typeof(AudioNativeV2.StructHeader), 12 },
                { typeof(AudioNativeV2.Version), 24 },
                { typeof(AudioNativeV2.Utf8Buffer), 40 },
                { typeof(AudioNativeV2.Utf16Buffer), 40 },
                { typeof(AudioNativeV2.ArrayBuffer), 40 },
                { typeof(AudioNativeV2.Result), 136 },
                { typeof(AudioNativeV2.Capability), 216 },
                { typeof(AudioNativeV2.RuntimeSnapshot), 312 },
                { typeof(AudioNativeV2.MeterSnapshot), 112 },
                { typeof(AudioNativeV2.SourceSnapshot), 256 },
                { typeof(AudioNativeV2.SfxCounters), 120 },
                { typeof(AudioNativeV2.InitializeCommand), 112 },
                { typeof(AudioNativeV2.BgmCommand), 168 },
                { typeof(AudioNativeV2.SfxCatalogItem), 96 },
                { typeof(AudioNativeV2.SfxCatalogCommand), 104 },
                { typeof(AudioNativeV2.SfxPlayItem), 64 },
                { typeof(AudioNativeV2.SfxBatchCommand), 112 },
                { typeof(AudioNativeV2.GainCommand), 72 },
                { typeof(AudioNativeV2.RuntimeProbeCommand), 192 },
                { typeof(AudioNativeV2.OfflineProbeCommand), 144 },
                { typeof(AudioNativeV2.ProbeResult), 232 },
                { typeof(AudioNativeV2.ShutdownCommand), 64 }
            };

            foreach (KeyValuePair<Type, int> pair in expectedSizes)
            {
                StructLayoutAttribute layout = pair.Key.StructLayoutAttribute;
                Assert.NotNull(layout);
                Assert.Equal(LayoutKind.Sequential, layout.Value);
                Assert.Equal(8, layout.Pack);
                Assert.Equal(0, Marshal.OffsetOf(pair.Key, "structSize").ToInt32());
                Assert.Equal(4, Marshal.OffsetOf(pair.Key, "abiMajor").ToInt32());
                Assert.Equal(8, Marshal.OffsetOf(pair.Key, "abiMinor").ToInt32());
                Assert.Equal(pair.Value, Marshal.SizeOf(pair.Key));

                Assert.Equal(typeof(uint), GetField(pair.Key, "structSize").FieldType);
                Assert.Equal(typeof(uint), GetField(pair.Key, "abiMajor").FieldType);
                Assert.Equal(typeof(uint), GetField(pair.Key, "abiMinor").FieldType);

                foreach (FieldInfo field in pair.Key.GetFields(
                    BindingFlags.Instance |
                    BindingFlags.Public |
                    BindingFlags.NonPublic))
                {
                    Assert.False(field.FieldType.IsEnum);
                    Assert.NotEqual(typeof(bool), field.FieldType);
                    Assert.NotEqual(typeof(IntPtr), field.FieldType);
                    Assert.NotEqual(typeof(UIntPtr), field.FieldType);
                    Assert.NotEqual(typeof(string), field.FieldType);
                    Assert.False(string.Equals(
                        "generation",
                        field.Name,
                        StringComparison.OrdinalIgnoreCase));
                }
            }
        }

        [Fact]
        public void FrozenConstants_MatchH1Manifest()
        {
            Assert.Equal(2u, AudioNativeV2.AbiMajor);
            Assert.Equal(0u, AudioNativeV2.AbiMinor);
            Assert.Equal(2u, AudioNativeV2.WireRevision);
            Assert.Equal(17u, AudioNativeV2.ResultInternalError);
            Assert.Equal(7u, AudioNativeV2.BackendMaskProduction);
            Assert.Equal(
                0u,
                AudioNativeV2.BackendMaskProduction &
                    AudioNativeV2.BackendMaskTestOnlyNull);
            Assert.Equal(2000u, AudioNativeV2.RuntimeProbeMaxWallMs);
            Assert.Equal(96000uL, AudioNativeV2.RuntimeProbeMaxDecodedFrames);
            Assert.Equal(8388608uL, AudioNativeV2.RuntimeProbeMaxInputBytes);
            Assert.Equal(536870912uL, AudioNativeV2.RuntimeProbeMaxFileBytes);
            Assert.Equal(2u, AudioNativeV2.RuntimeProbeStableObservations);
            Assert.Equal(1000u, AudioNativeV2.RuntimeProbeStableIntervalMs);
            Assert.Equal(120000u, AudioNativeV2.OfflineProbeMaxWallMs);
            Assert.NotEqual(
                AudioNativeV2.ProbeIncompatible,
                AudioNativeV2.ProbeInconclusiveTimeoutNotUnsupported);
        }

        [Fact]
        public void KeyOffsets_MatchNativeHeaderExactly()
        {
            AssertOffset<AudioNativeV2.Utf8Buffer>("dataAddress", 16);
            AssertOffset<AudioNativeV2.Utf8Buffer>("capacityBytes", 24);
            AssertOffset<AudioNativeV2.Utf8Buffer>("lengthBytes", 28);
            AssertOffset<AudioNativeV2.Utf8Buffer>("requiredBytes", 32);
            AssertOffset<AudioNativeV2.Utf8Buffer>("flags", 36);

            AssertOffset<AudioNativeV2.Result>("audioSessionId", 40);
            AssertOffset<AudioNativeV2.Result>("audioReadyGeneration", 80);
            AssertOffset<AudioNativeV2.Result>("deviceGeneration", 88);
            AssertOffset<AudioNativeV2.Result>("messageKey", 96);

            AssertOffset<AudioNativeV2.RuntimeSnapshot>("audioStatus", 12);
            AssertOffset<AudioNativeV2.RuntimeSnapshot>("audioSessionId", 16);
            AssertOffset<AudioNativeV2.RuntimeSnapshot>("audioReadyGeneration", 56);
            AssertOffset<AudioNativeV2.RuntimeSnapshot>("deviceGeneration", 64);
            AssertOffset<AudioNativeV2.RuntimeSnapshot>("selectedBackend", 72);
            AssertOffset<AudioNativeV2.RuntimeSnapshot>("lastStructuredFailure", 176);

            AssertOffset<AudioNativeV2.BgmCommand>("wireRevision", 12);
            AssertOffset<AudioNativeV2.BgmCommand>("requestId", 16);
            AssertOffset<AudioNativeV2.BgmCommand>("audioSessionId", 56);
            AssertOffset<AudioNativeV2.BgmCommand>("audioReadyGeneration", 96);
            AssertOffset<AudioNativeV2.BgmCommand>("operation", 104);

            AssertOffset<AudioNativeV2.SfxBatchCommand>("wireRevision", 12);
            AssertOffset<AudioNativeV2.SfxBatchCommand>("audioSessionId", 16);
            AssertOffset<AudioNativeV2.SfxBatchCommand>("audioReadyGeneration", 56);
            AssertOffset<AudioNativeV2.SfxBatchCommand>("batchSequence", 64);
            AssertOffset<AudioNativeV2.SfxBatchCommand>("linkageIds", 72);
        }

        [Fact]
        public void Imports_AreExactCdeclSymbols()
        {
            Dictionary<string, string> expected = new Dictionary<string, string>
            {
                { "QueryCapability", "cf7_audio_bridge_v2_query_capability" },
                { "Initialize", "cf7_audio_bridge_v2_initialize" },
                { "QueryRuntime", "cf7_audio_bridge_v2_query_runtime" },
                { "QueryMeter", "cf7_audio_bridge_v2_query_meter" },
                { "QueryBgmSource", "cf7_audio_bridge_v2_query_bgm_source" },
                { "QuerySfxCounters", "cf7_audio_bridge_v2_query_sfx_counters" },
                { "SubmitBgm", "cf7_audio_bridge_v2_submit_bgm" },
                { "RebuildSfxCatalog", "cf7_audio_bridge_v2_rebuild_sfx_catalog" },
                { "SubmitSfxBatch", "cf7_audio_bridge_v2_submit_sfx_batch" },
                { "SetGain", "cf7_audio_bridge_v2_set_gain" },
                { "ProbeRuntimeCompatibility", "cf7_audio_bridge_v2_probe_runtime_compatibility" },
                { "ProbeOfflineQualification", "cf7_audio_bridge_v2_probe_offline_qualification" },
                { "Shutdown", "cf7_audio_bridge_v2_shutdown" }
            };

            MethodInfo[] imports = typeof(AudioNativeV2)
                .GetMethods(BindingFlags.Static | BindingFlags.NonPublic)
                .Where(method => method.GetCustomAttribute<DllImportAttribute>() != null)
                .ToArray();
            Assert.Equal(expected.Count, imports.Length);

            foreach (MethodInfo method in imports)
            {
                DllImportAttribute attribute =
                    method.GetCustomAttribute<DllImportAttribute>();
                Assert.True(expected.ContainsKey(method.Name));
                Assert.Equal(AudioNativeV2.DllName, attribute.Value);
                Assert.Equal(expected[method.Name], attribute.EntryPoint);
                Assert.Equal(CallingConvention.Cdecl, attribute.CallingConvention);
                Assert.True(attribute.ExactSpelling);
                Assert.Equal(typeof(uint), method.ReturnType);
            }
        }

        [Fact]
        public void PrefixValidation_IsFailClosedForUndersizedOrWrongVersion()
        {
            uint size = (uint)Marshal.SizeOf<AudioNativeV2.Capability>();
            Assert.True(AudioNativeV2.IsPrefixAccepted(
                size,
                AudioNativeV2.AbiMajor,
                AudioNativeV2.AbiMinor,
                size));
            Assert.True(AudioNativeV2.IsPrefixAccepted(
                size + 8u,
                AudioNativeV2.AbiMajor,
                AudioNativeV2.AbiMinor,
                size));
            Assert.False(AudioNativeV2.IsPrefixAccepted(
                size - 1u,
                AudioNativeV2.AbiMajor,
                AudioNativeV2.AbiMinor,
                size));
            Assert.False(AudioNativeV2.IsPrefixAccepted(
                size,
                AudioNativeV2.AbiMajor - 1u,
                AudioNativeV2.AbiMinor,
                size));
            Assert.False(AudioNativeV2.IsPrefixAccepted(
                size,
                AudioNativeV2.AbiMajor + 1u,
                AudioNativeV2.AbiMinor,
                size));
            Assert.False(AudioNativeV2.IsPrefixAccepted(
                size,
                AudioNativeV2.AbiMajor,
                AudioNativeV2.AbiMinor + 1u,
                size));
        }

        [Fact]
        public void Utf8Capacity_UndersizedWritePreservesCanaries()
        {
            IntPtr allocation = Marshal.AllocHGlobal(9);
            try
            {
                Fill(allocation, 9, 0xA5);
                AudioNativeV2.Utf8Buffer buffer;
                Assert.True(AudioNativeV2.TryCreateUtf8Buffer(
                    IntPtr.Add(allocation, 2),
                    4u,
                    AudioNativeV2.BufferWriteOnly,
                    out buffer));

                Assert.False(AudioNativeV2.TryWriteUtf8ToCallerOwnedMemory(
                    ref buffer,
                    "abcd"));
                Assert.Equal(5u, buffer.requiredBytes);
                Assert.Equal(0u, buffer.lengthBytes);
                AssertAllBytes(allocation, 9, 0xA5);

                buffer.capacityBytes = 5u;
                Assert.True(AudioNativeV2.TryWriteUtf8ToCallerOwnedMemory(
                    ref buffer,
                    "abcd"));
                Assert.Equal(5u, buffer.requiredBytes);
                Assert.Equal(4u, buffer.lengthBytes);
                Assert.Equal(0xA5, Marshal.ReadByte(allocation, 0));
                Assert.Equal(0xA5, Marshal.ReadByte(allocation, 1));
                Assert.Equal((byte)'a', Marshal.ReadByte(allocation, 2));
                Assert.Equal((byte)'d', Marshal.ReadByte(allocation, 5));
                Assert.Equal(0, Marshal.ReadByte(allocation, 6));
                Assert.Equal(0xA5, Marshal.ReadByte(allocation, 7));
                Assert.Equal(0xA5, Marshal.ReadByte(allocation, 8));

                Fill(allocation, 9, 0xA5);
                buffer.structSize -= 1u;
                Assert.False(AudioNativeV2.TryWriteUtf8ToCallerOwnedMemory(
                    ref buffer,
                    "abcd"));
                AssertAllBytes(allocation, 9, 0xA5);
            }
            finally
            {
                Marshal.FreeHGlobal(allocation);
            }
        }

        [Fact]
        public void Utf16AndArrayCapacity_RejectUndersizedOrInvalidDescriptors()
        {
            IntPtr allocation = Marshal.AllocHGlobal(14);
            try
            {
                Fill(allocation, 14, 0xA5);
                AudioNativeV2.Utf16Buffer buffer;
                Assert.True(AudioNativeV2.TryCreateUtf16Buffer(
                    IntPtr.Add(allocation, 2),
                    4u,
                    AudioNativeV2.BufferWriteOnly,
                    out buffer));
                Assert.False(AudioNativeV2.TryWriteUtf16ToCallerOwnedMemory(
                    ref buffer,
                    "abcd"));
                Assert.Equal(5u, buffer.requiredCodeUnits);
                Assert.Equal(0u, buffer.lengthCodeUnits);
                AssertAllBytes(allocation, 14, 0xA5);

                buffer.capacityCodeUnits = 5u;
                Assert.True(AudioNativeV2.TryWriteUtf16ToCallerOwnedMemory(
                    ref buffer,
                    "abcd"));
                Assert.Equal(0xA5, Marshal.ReadByte(allocation, 0));
                Assert.Equal(0xA5, Marshal.ReadByte(allocation, 1));
                Assert.Equal((byte)'a', Marshal.ReadByte(allocation, 2));
                Assert.Equal(0, Marshal.ReadByte(allocation, 3));
                Assert.Equal(0, Marshal.ReadInt16(allocation, 10));
                Assert.Equal(0xA5, Marshal.ReadByte(allocation, 12));
                Assert.Equal(0xA5, Marshal.ReadByte(allocation, 13));
            }
            finally
            {
                Marshal.FreeHGlobal(allocation);
            }

            AudioNativeV2.ArrayBuffer array;
            Assert.True(AudioNativeV2.TryCreateArrayBuffer(
                new IntPtr(0x1000),
                (uint)Marshal.SizeOf<AudioNativeV2.SfxPlayItem>(),
                2u,
                2u,
                out array));
            Assert.True(AudioNativeV2.IsArrayBufferValid(
                ref array,
                (uint)Marshal.SizeOf<AudioNativeV2.SfxPlayItem>()));
            array.countElements = 3u;
            Assert.False(AudioNativeV2.IsArrayBufferValid(
                ref array,
                (uint)Marshal.SizeOf<AudioNativeV2.SfxPlayItem>()));
            Assert.False(AudioNativeV2.TryCreateArrayBuffer(
                IntPtr.Zero,
                (uint)Marshal.SizeOf<AudioNativeV2.SfxPlayItem>(),
                1u,
                0u,
                out array));
        }

        [Fact]
        public void ProductionCapabilityHandshake_RequiresCompleteH1Surface()
        {
            using (NativeBuffers buffers = new NativeBuffers())
            {
                AudioNativeV2.Capability capability =
                    CreateCapability(buffers);
                Assert.True(AudioNativeV2.IsProductionCapabilityAccepted(
                    ref capability));

                AudioNativeV2.Capability mutated = capability;
                mutated.structSize -= 1u;
                Assert.False(AudioNativeV2.IsProductionCapabilityAccepted(
                    ref mutated));

                mutated = capability;
                mutated.abiMajor += 1u;
                Assert.False(AudioNativeV2.IsProductionCapabilityAccepted(
                    ref mutated));

                mutated = capability;
                mutated.compiledBackendMask |=
                    AudioNativeV2.BackendMaskTestOnlyNull;
                Assert.False(AudioNativeV2.IsProductionCapabilityAccepted(
                    ref mutated));

                mutated = capability;
                mutated.testOnlyNullEnabled = AudioNativeV2.True;
                Assert.False(AudioNativeV2.IsProductionCapabilityAccepted(
                    ref mutated));

                mutated = capability;
                mutated.decoderBackends &=
                    ~AudioNativeV2.DecoderBackendLibOpus;
                Assert.False(AudioNativeV2.IsProductionCapabilityAccepted(
                    ref mutated));

                mutated = capability;
                mutated.codecs |= 0x8000000000000000uL;
                Assert.False(AudioNativeV2.IsProductionCapabilityAccepted(
                    ref mutated));

                mutated = capability;
                mutated.supportsSfxMeter = AudioNativeV2.False;
                Assert.False(AudioNativeV2.IsProductionCapabilityAccepted(
                    ref mutated));

                mutated = capability;
                mutated.capabilityDigestSha256.requiredBytes =
                    mutated.capabilityDigestSha256.capacityBytes + 1u;
                mutated.capabilityDigestSha256.lengthBytes = 0u;
                Assert.False(AudioNativeV2.IsProductionCapabilityAccepted(
                    ref mutated));
            }
        }

        [Fact]
        public void ReadyHandshake_BindsSessionReadyAndRealDeviceEpochs()
        {
            const string sessionId = "01234567-89ab-4def-8abc-0123456789ab";
            const ulong readyEpoch = 7uL;
            using (NativeBuffers buffers = new NativeBuffers())
            {
                AudioNativeV2.Capability capability =
                    CreateCapability(buffers);
                AudioNativeV2.RuntimeSnapshot runtime =
                    CreateReadyRuntime(buffers, sessionId, readyEpoch);
                Assert.True(AudioNativeV2.IsProductionReadyHandshakeAccepted(
                    ref capability,
                    ref runtime,
                    sessionId,
                    readyEpoch));

                AudioNativeV2.RuntimeSnapshot mutated = runtime;
                mutated.audioStatus = AudioNativeV2.AudioFailedNoOutput;
                Assert.False(AudioNativeV2.IsProductionReadyHandshakeAccepted(
                    ref capability,
                    ref mutated,
                    sessionId,
                    readyEpoch));

                mutated = runtime;
                mutated.deviceGeneration = 0uL;
                Assert.False(AudioNativeV2.IsProductionReadyHandshakeAccepted(
                    ref capability,
                    ref mutated,
                    sessionId,
                    readyEpoch));

                mutated = runtime;
                mutated.selectedBackend = AudioNativeV2.BackendTestOnlyNull;
                Assert.False(AudioNativeV2.IsProductionReadyHandshakeAccepted(
                    ref capability,
                    ref mutated,
                    sessionId,
                    readyEpoch));

                Assert.False(AudioNativeV2.IsProductionReadyHandshakeAccepted(
                    ref capability,
                    ref runtime,
                    sessionId,
                    readyEpoch + 1uL));
                Assert.False(AudioNativeV2.IsProductionReadyHandshakeAccepted(
                    ref capability,
                    ref runtime,
                    sessionId.ToUpperInvariant(),
                    readyEpoch));
            }
        }

        private static AudioNativeV2.Capability CreateCapability(
            NativeBuffers buffers)
        {
            AudioNativeV2.Capability capability =
                default(AudioNativeV2.Capability);
            SetPrefix(ref capability);
            capability.abiVersion = CreateVersion(
                AudioNativeV2.AbiMajor,
                AudioNativeV2.AbiMinor,
                0u);
            capability.bridgeBuildId = buffers.WriteUtf8("audio-v2-test-build");
            capability.miniaudioVersion = CreateVersion(0u, 11u, 25u);
            capability.decoderBackends = AudioNativeV2.RequiredDecoderBackends;
            capability.containers = AudioNativeV2.RequiredContainers;
            capability.codecs = AudioNativeV2.RequiredCodecs;
            capability.extensions = AudioNativeV2.RequiredExtensions;
            capability.compiledBackendMask = AudioNativeV2.BackendMaskProduction;
            capability.supportsRuntimeCompatibilityProbe = AudioNativeV2.True;
            capability.supportsOfflineQualificationProbe = AudioNativeV2.True;
            capability.supportsSeek = AudioNativeV2.True;
            capability.supportsLoop = AudioNativeV2.True;
            capability.supportsDeviceRecovery = AudioNativeV2.True;
            capability.supportsBgmMeter = AudioNativeV2.True;
            capability.supportsSfxMeter = AudioNativeV2.True;
            capability.testOnlyNullEnabled = AudioNativeV2.False;
            capability.capabilityDigestSha256 = buffers.WriteUtf8(
                new string('A', 64));
            return capability;
        }

        private static AudioNativeV2.RuntimeSnapshot CreateReadyRuntime(
            NativeBuffers buffers,
            string sessionId,
            ulong readyEpoch)
        {
            AudioNativeV2.RuntimeSnapshot runtime =
                default(AudioNativeV2.RuntimeSnapshot);
            SetPrefix(ref runtime);
            runtime.audioStatus = AudioNativeV2.AudioReady;
            runtime.audioSessionId = buffers.WriteUtf8(sessionId);
            runtime.audioReadyGeneration = readyEpoch;
            runtime.deviceGeneration = 3uL;
            runtime.selectedBackend = AudioNativeV2.BackendWasapi;
            runtime.selectedDeviceIdDigest = buffers.WriteUtf8(
                new string('B', 64));
            runtime.selectedDeviceName = buffers.WriteUtf16("Speakers");
            runtime.sampleRate = 48000u;
            runtime.channels = 2u;
            runtime.sampleFormat = AudioNativeV2.SampleFormatF32;
            runtime.lastStructuredFailure = default(AudioNativeV2.Result);
            SetPrefix(ref runtime.lastStructuredFailure);
            runtime.lastStructuredFailure.category = AudioNativeV2.ResultOk;
            return runtime;
        }

        private static AudioNativeV2.Version CreateVersion(
            uint major,
            uint minor,
            uint patch)
        {
            AudioNativeV2.Version version = default(AudioNativeV2.Version);
            version.structSize = (uint)Marshal.SizeOf<AudioNativeV2.Version>();
            version.abiMajor = AudioNativeV2.AbiMajor;
            version.abiMinor = AudioNativeV2.AbiMinor;
            version.major = major;
            version.minor = minor;
            version.patch = patch;
            return version;
        }

        private static void SetPrefix(ref AudioNativeV2.Capability value)
        {
            value.structSize = (uint)Marshal.SizeOf<AudioNativeV2.Capability>();
            value.abiMajor = AudioNativeV2.AbiMajor;
            value.abiMinor = AudioNativeV2.AbiMinor;
        }

        private static void SetPrefix(ref AudioNativeV2.RuntimeSnapshot value)
        {
            value.structSize = (uint)Marshal.SizeOf<AudioNativeV2.RuntimeSnapshot>();
            value.abiMajor = AudioNativeV2.AbiMajor;
            value.abiMinor = AudioNativeV2.AbiMinor;
        }

        private static void SetPrefix(ref AudioNativeV2.Result value)
        {
            value.structSize = (uint)Marshal.SizeOf<AudioNativeV2.Result>();
            value.abiMajor = AudioNativeV2.AbiMajor;
            value.abiMinor = AudioNativeV2.AbiMinor;
        }

        private static FieldInfo GetField(Type type, string name)
        {
            FieldInfo field = type.GetField(
                name,
                BindingFlags.Instance |
                BindingFlags.Public |
                BindingFlags.NonPublic);
            Assert.NotNull(field);
            return field;
        }

        private static void AssertOffset<T>(string fieldName, int expected)
            where T : struct
        {
            Assert.Equal(expected, Marshal.OffsetOf<T>(fieldName).ToInt32());
        }

        private static void Fill(IntPtr address, int length, byte value)
        {
            int index;
            for (index = 0; index < length; index++)
            {
                Marshal.WriteByte(address, index, value);
            }
        }

        private static void AssertAllBytes(
            IntPtr address,
            int length,
            byte expected)
        {
            int index;
            for (index = 0; index < length; index++)
            {
                Assert.Equal(expected, Marshal.ReadByte(address, index));
            }
        }

        private sealed class NativeBuffers : IDisposable
        {
            private readonly List<IntPtr> _allocations = new List<IntPtr>();

            internal AudioNativeV2.Utf8Buffer WriteUtf8(string value)
            {
                int byteCount = System.Text.Encoding.UTF8.GetByteCount(value);
                IntPtr allocation = Marshal.AllocHGlobal(byteCount + 1);
                _allocations.Add(allocation);
                AudioNativeV2.Utf8Buffer buffer;
                Assert.True(AudioNativeV2.TryCreateUtf8Buffer(
                    allocation,
                    checked((uint)byteCount + 1u),
                    AudioNativeV2.BufferWriteOnly,
                    out buffer));
                Assert.True(AudioNativeV2.TryWriteUtf8ToCallerOwnedMemory(
                    ref buffer,
                    value));
                return buffer;
            }

            internal AudioNativeV2.Utf16Buffer WriteUtf16(string value)
            {
                IntPtr allocation = Marshal.AllocHGlobal(
                    checked((value.Length + 1) * sizeof(char)));
                _allocations.Add(allocation);
                AudioNativeV2.Utf16Buffer buffer;
                Assert.True(AudioNativeV2.TryCreateUtf16Buffer(
                    allocation,
                    checked((uint)value.Length + 1u),
                    AudioNativeV2.BufferWriteOnly,
                    out buffer));
                Assert.True(AudioNativeV2.TryWriteUtf16ToCallerOwnedMemory(
                    ref buffer,
                    value));
                return buffer;
            }

            public void Dispose()
            {
                foreach (IntPtr allocation in _allocations)
                {
                    Marshal.FreeHGlobal(allocation);
                }
                _allocations.Clear();
            }
        }
    }
}
