[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('bgm_playback','sfx_playback','bgm_sfx_mix','device_recovery')]
    [string]$CaptureId,

    [Parameter(Mandatory=$true)]
    [ValidateSet('bgm_playback','sfx_playback','bgm_sfx_mix','device_recovery')]
    [string]$CaseId,

    [Parameter(Mandatory=$true)]
    [string]$CandidateRoot,

    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[A-F0-9]{64}$')]
    [string]$CandidateBuildIdentity,

    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[A-F0-9]{64}$')]
    [string]$CandidatePayloadClosure,

    [Parameter(Mandatory=$true)]
    [ValidateRange(1, 2147483647)]
    [int]$CandidateProcessId,

    [Parameter(Mandatory=$true)]
    [ValidateSet('wasapi','directsound','winmm')]
    [string]$SelectedBackend,

    [Parameter(Mandatory=$true)]
    [string]$EndpointId,

    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[A-F0-9]{64}$')]
    [string]$DeviceIdDigest,

    [Parameter(Mandatory=$true)]
    [ValidateRange(1.0, 5.0)]
    [double]$DurationSeconds,

    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$')]
    [string]$RunId,

    [Parameter(Mandatory=$true)]
    [string]$OutputWav,

    [Parameter(Mandatory=$true)]
    [string]$OutputConfiguration,

    [Parameter(Mandatory=$false)]
    [string]$ReadySignalPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:CaptureToolRelativePath = 'tools/audio-v2/capture-endpoint.ps1'
$script:MaximumCaptureBytes = 1MB
$script:MinimumPeakAbsolutePcm16 = 64
$script:MinimumNonZeroSampleRatio = 0.001
$script:PublishedWav = $false
$script:PublishedConfiguration = $false
$script:TemporaryWav = $null
$script:TemporaryConfiguration = $null

function Fail-Cf7AudioCapture {
    param([Parameter(Mandatory=$true)][string]$Message)
    throw "Audio v2 endpoint capture failed: $Message"
}

function Get-Cf7Sha256Bytes {
    param([Parameter(Mandatory=$true)][byte[]]$Bytes)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($algorithm.ComputeHash($Bytes))).Replace('-', '').ToUpperInvariant()
    } finally {
        $algorithm.Dispose()
    }
}

function Get-Cf7Utf8Sha256 {
    param([Parameter(Mandatory=$true)][string]$Text)
    return Get-Cf7Sha256Bytes -Bytes ([Text.Encoding]::UTF8.GetBytes($Text))
}

function Get-Cf7GitBlobOid {
    param([Parameter(Mandatory=$true)][byte[]]$Bytes)
    $header = [Text.Encoding]::UTF8.GetBytes(('blob {0}' -f $Bytes.Length) + [char]0)
    $algorithm = [Security.Cryptography.SHA1]::Create()
    try {
        [void]$algorithm.TransformBlock($header, 0, $header.Length, $header, 0)
        [void]$algorithm.TransformFinalBlock($Bytes, 0, $Bytes.Length)
        return ([BitConverter]::ToString($algorithm.Hash)).Replace('-', '').ToLowerInvariant()
    } finally {
        $algorithm.Dispose()
    }
}

function ConvertTo-Cf7JsonString {
    param([Parameter(Mandatory=$true)][string]$Value)
    $builder = New-Object Text.StringBuilder
    [void]$builder.Append('"')
    foreach ($character in $Value.ToCharArray()) {
        $code = [int][char]$character
        switch ($code) {
            8  { [void]$builder.Append('\b'); continue }
            9  { [void]$builder.Append('\t'); continue }
            10 { [void]$builder.Append('\n'); continue }
            12 { [void]$builder.Append('\f'); continue }
            13 { [void]$builder.Append('\r'); continue }
            34 { [void]$builder.Append('\"'); continue }
            92 { [void]$builder.Append('\\'); continue }
        }
        if ($code -lt 32) {
            [void]$builder.Append(('\u{0:x4}' -f $code))
        } else {
            [void]$builder.Append($character)
        }
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Format-Cf7JsonNumber {
    param([Parameter(Mandatory=$true)][double]$Value)
    if ([double]::IsNaN($Value) -or [double]::IsInfinity($Value)) {
        Fail-Cf7AudioCapture 'non-finite JSON number'
    }
    return $Value.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
}

function Assert-Cf7PlainFile {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Label
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Fail-Cf7AudioCapture "$Label is missing: $Path"
    }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        Fail-Cf7AudioCapture "$Label must not be a link/reparse point: $Path"
    }
    return $item
}

function Assert-Cf7PlainDirectoryChain {
    param([Parameter(Mandatory=$true)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    $probe = $full
    while ($probe -and (Test-Path -LiteralPath $probe)) {
        $item = Get-Item -LiteralPath $probe -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Fail-Cf7AudioCapture "output path traverses a link/reparse point: $probe"
        }
        $parent = [IO.Path]::GetDirectoryName($probe)
        if (-not $parent -or $parent -eq $probe) { break }
        $probe = $parent
    }
}

function Resolve-Cf7OutputPath {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Extension,
        [Parameter(Mandatory=$true)][string]$Label
    )
    if (-not [IO.Path]::IsPathRooted($Path)) {
        Fail-Cf7AudioCapture "$Label must be an absolute path"
    }
    $full = [IO.Path]::GetFullPath($Path)
    if ([IO.Path]::GetExtension($full) -cne $Extension) {
        Fail-Cf7AudioCapture "$Label must use $Extension"
    }
    if (Test-Path -LiteralPath $full) {
        Fail-Cf7AudioCapture "$Label already exists; capture artifacts are immutable: $full"
    }
    $parent = [IO.Path]::GetDirectoryName($full)
    if (-not $parent) { Fail-Cf7AudioCapture "$Label has no parent directory" }
    Assert-Cf7PlainDirectoryChain -Path $parent
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        [void](New-Item -ItemType Directory -Path $parent -Force)
    }
    Assert-Cf7PlainDirectoryChain -Path $parent
    return $full
}

function Get-Cf7CandidateManifestFields {
    param([Parameter(Mandatory=$true)][string]$ManifestPath)
    $manifestItem = Assert-Cf7PlainFile -Path $ManifestPath -Label 'candidate runtime manifest'
    if ($manifestItem.Length -le 0 -or $manifestItem.Length -gt 4MB) {
        Fail-Cf7AudioCapture 'candidate runtime manifest size is invalid'
    }
    $bytes = [IO.File]::ReadAllBytes($manifestItem.FullName)
    if ($bytes[$bytes.Length - 1] -ne 10 -or $bytes -contains 13) {
        Fail-Cf7AudioCapture 'candidate runtime manifest must be canonical LF text'
    }
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    $lines = $text.Split([char]10)
    if ($lines.Length -lt 3 -or $lines[0] -cne 'cf7-runtime-manifest-v2') {
        Fail-Cf7AudioCapture 'candidate runtime manifest header is invalid'
    }
    $fields = @{}
    foreach ($line in $lines[1..($lines.Length - 2)]) {
        if (-not $line) { Fail-Cf7AudioCapture 'candidate runtime manifest contains an interior blank line' }
        $parts = $line.Split([char]9)
        if ($parts[0] -ceq 'file') { continue }
        if ($parts.Length -ne 2 -or $fields.ContainsKey($parts[0])) {
            Fail-Cf7AudioCapture 'candidate runtime manifest has malformed or duplicate fields'
        }
        $fields[$parts[0]] = $parts[1]
    }
    return $fields
}

if ($CaptureId -cne $CaseId) {
    Fail-Cf7AudioCapture 'captureId must equal its unique endpoint caseId'
}
if ([string]::IsNullOrWhiteSpace($EndpointId) -or $EndpointId.Length -gt 4096) {
    Fail-Cf7AudioCapture 'EndpointId is empty or too long'
}
if ((Get-Cf7Utf8Sha256 -Text $EndpointId) -cne $DeviceIdDigest) {
    Fail-Cf7AudioCapture 'EndpointId does not match DeviceIdDigest (SHA-256 over exact UTF-8 endpoint ID)'
}
if (-not [IO.Path]::IsPathRooted($CandidateRoot)) {
    Fail-Cf7AudioCapture 'CandidateRoot must be absolute'
}
$candidateRootFull = [IO.Path]::GetFullPath($CandidateRoot).TrimEnd('\')
if (-not (Test-Path -LiteralPath $candidateRootFull -PathType Container)) {
    Fail-Cf7AudioCapture "CandidateRoot does not exist: $candidateRootFull"
}
$candidateRootItem = Get-Item -LiteralPath $candidateRootFull -Force
if (($candidateRootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        -not $candidateRootItem.FullName.TrimEnd('\').Equals($candidateRootFull, [StringComparison]::OrdinalIgnoreCase)) {
    Fail-Cf7AudioCapture 'CandidateRoot must be a canonical real directory'
}

$candidateCorePath = Join-Path $candidateRootFull 'runtime\CRAZYFLASHER7MercenaryEmpire.Core.exe'
$candidateMiniaudioPath = Join-Path $candidateRootFull 'runtime\miniaudio.dll'
$candidateManifestPath = Join-Path $candidateRootFull 'runtime\cf7-runtime-manifest.tsv'
[void](Assert-Cf7PlainFile -Path $candidateCorePath -Label 'candidate Core executable')
[void](Assert-Cf7PlainFile -Path $candidateMiniaudioPath -Label 'candidate miniaudio DLL')
$manifestFields = Get-Cf7CandidateManifestFields -ManifestPath $candidateManifestPath
if (-not $manifestFields.ContainsKey('buildIdentityHash') -or
        -not $manifestFields.ContainsKey('payloadClosureHash') -or
        [string]$manifestFields['buildIdentityHash'] -cne $CandidateBuildIdentity -or
        [string]$manifestFields['payloadClosureHash'] -cne $CandidatePayloadClosure) {
    Fail-Cf7AudioCapture 'candidate manifest identity/closure does not match the requested capture binding'
}

try {
    $candidateProcess = Get-Process -Id $CandidateProcessId -ErrorAction Stop
    $candidateProcessPath = [IO.Path]::GetFullPath($candidateProcess.Path)
    $candidateProcessStartUtc = $candidateProcess.StartTime.ToUniversalTime()
} catch {
    Fail-Cf7AudioCapture "candidate process is unavailable: $($_.Exception.Message)"
}
if (-not $candidateProcessPath.Equals([IO.Path]::GetFullPath($candidateCorePath), [StringComparison]::OrdinalIgnoreCase)) {
    Fail-Cf7AudioCapture "candidate PID does not execute the exact candidate Core: $candidateProcessPath"
}

$outputWavFull = Resolve-Cf7OutputPath -Path $OutputWav -Extension '.wav' -Label 'OutputWav'
$outputConfigurationFull = Resolve-Cf7OutputPath -Path $OutputConfiguration -Extension '.json' -Label 'OutputConfiguration'
if ($outputWavFull.Equals($outputConfigurationFull, [StringComparison]::OrdinalIgnoreCase)) {
    Fail-Cf7AudioCapture 'WAV and configuration outputs must be distinct'
}
$readySignalFull = $null
if (-not [string]::IsNullOrWhiteSpace($ReadySignalPath)) {
    if (-not [IO.Path]::IsPathRooted($ReadySignalPath)) {
        Fail-Cf7AudioCapture 'ReadySignalPath must be an absolute path'
    }
    $readySignalInputRoot = [IO.Path]::GetPathRoot($ReadySignalPath)
    if ($ReadySignalPath.Substring($readySignalInputRoot.Length).Contains(':')) {
        Fail-Cf7AudioCapture 'ReadySignalPath must not use an alternate data stream'
    }
    $readySignalCandidateFull = [IO.Path]::GetFullPath($ReadySignalPath)
    if ($readySignalCandidateFull.Equals($outputWavFull, [StringComparison]::OrdinalIgnoreCase) -or
            $readySignalCandidateFull.Equals($outputConfigurationFull, [StringComparison]::OrdinalIgnoreCase)) {
        Fail-Cf7AudioCapture 'ready signal output must be distinct from gate artifacts'
    }
    $readySignalFull = Resolve-Cf7OutputPath -Path $ReadySignalPath -Extension '.ready' -Label 'ReadySignalPath'
}
$script:TemporaryWav = Join-Path ([IO.Path]::GetDirectoryName($outputWavFull)) ('.' + [IO.Path]::GetFileName($outputWavFull) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
$script:TemporaryConfiguration = Join-Path ([IO.Path]::GetDirectoryName($outputConfigurationFull)) ('.' + [IO.Path]::GetFileName($outputConfigurationFull) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')

$toolBytesBefore = [IO.File]::ReadAllBytes($PSCommandPath)
if ($toolBytesBefore.Length -eq 0 -or
        $toolBytesBefore[$toolBytesBefore.Length - 1] -ne 10 -or
        $toolBytesBefore -contains 13 -or
        ($toolBytesBefore.Length -ge 3 -and $toolBytesBefore[0] -eq 0xEF -and $toolBytesBefore[1] -eq 0xBB -and $toolBytesBefore[2] -eq 0xBF)) {
    Fail-Cf7AudioCapture 'capture tool checkout must be UTF-8 without BOM and canonical LF so its digest equals the release-source Git blob'
}
$toolSha256 = Get-Cf7Sha256Bytes -Bytes $toolBytesBefore
$toolBlobOid = Get-Cf7GitBlobOid -Bytes $toolBytesBefore

$captureSource = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace Cf7.AudioV2.EndpointCapture
{
    public sealed class ReadySignalFile : IDisposable
    {
        public const string Token = "CF7_AUDIO_V2_CAPTURE_READY_V1\n";

        private readonly string path;
        private bool ownsPath;

        private ReadySignalFile(string path)
        {
            this.path = path;
        }

        public static ReadySignalFile CreateAfterSuccessfulStart(bool audioClientStarted, string path)
        {
            if (!audioClientStarted) throw new InvalidOperationException("ready signal requires a successful IAudioClient.Start");
            if (String.IsNullOrEmpty(path)) return null;

            ReadySignalFile signal = new ReadySignalFile(path);
            try
            {
                byte[] readyBytes = new UTF8Encoding(false).GetBytes(Token);
                using (FileStream readyStream = new FileStream(
                    path,
                    FileMode.CreateNew,
                    FileAccess.Write,
                    FileShare.Read,
                    4096,
                    FileOptions.WriteThrough))
                {
                    signal.ownsPath = true;
                    readyStream.Write(readyBytes, 0, readyBytes.Length);
                    readyStream.Flush(true);
                }
                return signal;
            }
            catch
            {
                signal.Dispose();
                throw;
            }
        }

        public void Dispose()
        {
            if (!ownsPath) return;
            ownsPath = false;
            if (File.Exists(path)) File.Delete(path);
        }
    }

    internal enum EDataFlow { Render = 0, Capture = 1, All = 2 }
    internal enum ERole { Console = 0, Multimedia = 1, Communications = 2 }

    [ComImport]
    [Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    internal class MMDeviceEnumeratorComObject { }

    [ComImport]
    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceEnumerator
    {
        [PreserveSig] int EnumAudioEndpoints(EDataFlow dataFlow, uint stateMask, out IntPtr devices);
        [PreserveSig] int GetDefaultAudioEndpoint(EDataFlow dataFlow, ERole role, out IMMDevice endpoint);
        [PreserveSig] int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice endpoint);
        [PreserveSig] int RegisterEndpointNotificationCallback(IntPtr callback);
        [PreserveSig] int UnregisterEndpointNotificationCallback(IntPtr callback);
    }

    [ComImport]
    [Guid("D666063F-1587-4E43-81F1-B948E807363F")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDevice
    {
        [PreserveSig] int Activate(ref Guid interfaceId, uint classContext, IntPtr activationParameters, [MarshalAs(UnmanagedType.IUnknown)] out object result);
        [PreserveSig] int OpenPropertyStore(uint access, out IntPtr properties);
        [PreserveSig] int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        [PreserveSig] int GetState(out uint state);
    }

    [ComImport]
    [Guid("1CB9AD4C-DBFA-4C32-B178-C2F568A703B2")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioClient
    {
        [PreserveSig] int Initialize(int shareMode, uint streamFlags, long bufferDuration, long periodicity, IntPtr format, IntPtr sessionGuid);
        [PreserveSig] int GetBufferSize(out uint bufferFrames);
        [PreserveSig] int GetStreamLatency(out long latency);
        [PreserveSig] int GetCurrentPadding(out uint paddingFrames);
        [PreserveSig] int IsFormatSupported(int shareMode, IntPtr format, out IntPtr closestMatch);
        [PreserveSig] int GetMixFormat(out IntPtr format);
        [PreserveSig] int GetDevicePeriod(out long defaultPeriod, out long minimumPeriod);
        [PreserveSig] int Start();
        [PreserveSig] int Stop();
        [PreserveSig] int Reset();
        [PreserveSig] int SetEventHandle(IntPtr eventHandle);
        [PreserveSig] int GetService(ref Guid interfaceId, [MarshalAs(UnmanagedType.IUnknown)] out object service);
    }

    [ComImport]
    [Guid("C8ADBD64-E71E-48A0-A4DE-185C395CD317")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IAudioCaptureClient
    {
        [PreserveSig] int GetBuffer(out IntPtr data, out uint frames, out uint flags, out ulong devicePosition, out ulong qpcPosition);
        [PreserveSig] int ReleaseBuffer(uint frames);
        [PreserveSig] int GetNextPacketSize(out uint frames);
    }

    [StructLayout(LayoutKind.Sequential, Pack = 2)]
    internal struct WaveFormatEx
    {
        public ushort FormatTag;
        public ushort Channels;
        public uint SampleRate;
        public uint AverageBytesPerSecond;
        public ushort BlockAlign;
        public ushort BitsPerSample;
        public ushort ExtraSize;
    }

    [StructLayout(LayoutKind.Sequential, Pack = 2)]
    internal struct WaveFormatExtensible
    {
        public WaveFormatEx Format;
        public ushort ValidBitsPerSample;
        public uint ChannelMask;
        public Guid SubFormat;
    }

    public sealed class CaptureResult
    {
        public string EndpointId { get; set; }
        public int SampleRate { get; set; }
        public int Channels { get; set; }
        public long Frames { get; set; }
        public double DurationSeconds { get; set; }
        public int PeakAbsolutePcm16 { get; set; }
        public double NonZeroSampleRatio { get; set; }
    }

    public static class WasapiLoopbackCapture
    {
        private const uint CLSCTX_ALL = 23;
        private const uint DEVICE_STATE_ACTIVE = 1;
        private const int AUDCLNT_SHAREMODE_SHARED = 0;
        private const uint AUDCLNT_STREAMFLAGS_LOOPBACK = 0x00020000;
        private const uint AUDCLNT_BUFFERFLAGS_SILENT = 0x00000002;
        private const int WAVE_FORMAT_PCM = 1;
        private const int WAVE_FORMAT_IEEE_FLOAT = 3;
        private const int WAVE_FORMAT_EXTENSIBLE = 0xFFFE;
        private static readonly Guid IAudioClientId = new Guid("1CB9AD4C-DBFA-4C32-B178-C2F568A703B2");
        private static readonly Guid IAudioCaptureClientId = new Guid("C8ADBD64-E71E-48A0-A4DE-185C395CD317");
        private static readonly Guid PcmSubFormat = new Guid("00000001-0000-0010-8000-00AA00389B71");
        private static readonly Guid FloatSubFormat = new Guid("00000003-0000-0010-8000-00AA00389B71");

        [DllImport("ole32.dll")]
        private static extern int CoInitializeEx(IntPtr reserved, uint concurrencyModel);

        [DllImport("ole32.dll")]
        private static extern void CoUninitialize();

        private static void Check(int result, string operation)
        {
            if (result < 0) throw new COMException(operation + " failed with HRESULT 0x" + result.ToString("X8"), result);
        }

        private static short ClampToPcm16(double sample)
        {
            if (Double.IsNaN(sample) || Double.IsInfinity(sample)) throw new InvalidDataException("endpoint PCM contains a non-finite sample");
            if (sample >= 1.0) return Int16.MaxValue;
            if (sample <= -1.0) return Int16.MinValue;
            return (short)Math.Round(sample * 32767.0, MidpointRounding.AwayFromZero);
        }

        private static short ReadSample(byte[] raw, int offset, int formatTag, int bitsPerSample, int validBits)
        {
            if (formatTag == WAVE_FORMAT_IEEE_FLOAT && bitsPerSample == 32)
                return ClampToPcm16(BitConverter.ToSingle(raw, offset));
            if (formatTag == WAVE_FORMAT_IEEE_FLOAT && bitsPerSample == 64)
                return ClampToPcm16(BitConverter.ToDouble(raw, offset));
            if (formatTag != WAVE_FORMAT_PCM) throw new NotSupportedException("WASAPI mix format is neither PCM nor IEEE float");
            if (bitsPerSample == 8) return ClampToPcm16((raw[offset] - 128) / 128.0);
            if (bitsPerSample == 16) return BitConverter.ToInt16(raw, offset);
            if (bitsPerSample == 24)
            {
                int value = raw[offset] | (raw[offset + 1] << 8) | (raw[offset + 2] << 16);
                if ((value & 0x00800000) != 0) value |= unchecked((int)0xFF000000);
                return ClampToPcm16(value / 8388608.0);
            }
            if (bitsPerSample == 32)
            {
                int value = BitConverter.ToInt32(raw, offset);
                int effectiveBits = validBits > 0 && validBits <= 32 ? validBits : 32;
                if (effectiveBits < 32) value >>= (32 - effectiveBits);
                double denominator = Math.Pow(2.0, effectiveBits - 1);
                return ClampToPcm16(value / denominator);
            }
            throw new NotSupportedException("unsupported WASAPI PCM container width: " + bitsPerSample);
        }

        private static void WriteWave(string outputPath, int sampleRate, short channels, IList<short> samples)
        {
            int dataBytes = checked(samples.Count * 2);
            using (FileStream stream = new FileStream(outputPath, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            using (BinaryWriter writer = new BinaryWriter(stream, Encoding.UTF8))
            {
                writer.Write(Encoding.ASCII.GetBytes("RIFF"));
                writer.Write(checked(36 + dataBytes));
                writer.Write(Encoding.ASCII.GetBytes("WAVE"));
                writer.Write(Encoding.ASCII.GetBytes("fmt "));
                writer.Write(16);
                writer.Write((short)1);
                writer.Write(channels);
                writer.Write(sampleRate);
                writer.Write(checked(sampleRate * channels * 2));
                writer.Write((short)(channels * 2));
                writer.Write((short)16);
                writer.Write(Encoding.ASCII.GetBytes("data"));
                writer.Write(dataBytes);
                for (int index = 0; index < samples.Count; index++) writer.Write(samples[index]);
                writer.Flush();
                stream.Flush(true);
            }
        }

        public static CaptureResult Capture(string endpointId, double requestedDurationSeconds, string outputPath, string readySignalPath)
        {
            if (String.IsNullOrWhiteSpace(endpointId)) throw new ArgumentException("an explicit endpoint ID is required", "endpointId");
            if (requestedDurationSeconds < 1.0 || requestedDurationSeconds > 5.0) throw new ArgumentOutOfRangeException("requestedDurationSeconds");
            if (File.Exists(outputPath)) throw new IOException("capture output already exists");

            int comResult = CoInitializeEx(IntPtr.Zero, 0);
            bool uninitializeCom = comResult == 0 || comResult == 1;
            if (comResult < 0 && comResult != unchecked((int)0x80010106)) Marshal.ThrowExceptionForHR(comResult);
            IMMDeviceEnumerator enumerator = null;
            IMMDevice device = null;
            IAudioClient audioClient = null;
            IAudioCaptureClient captureClient = null;
            ReadySignalFile readySignal = null;
            IntPtr formatPointer = IntPtr.Zero;
            bool started = false;
            try
            {
                enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorComObject();
                Check(enumerator.GetDevice(endpointId, out device), "IMMDeviceEnumerator.GetDevice");
                uint state;
                Check(device.GetState(out state), "IMMDevice.GetState");
                if ((state & DEVICE_STATE_ACTIVE) == 0) throw new InvalidOperationException("the selected render endpoint is not active");
                string observedEndpointId;
                Check(device.GetId(out observedEndpointId), "IMMDevice.GetId");
                if (!String.Equals(observedEndpointId, endpointId, StringComparison.Ordinal)) throw new InvalidOperationException("WASAPI returned a different endpoint ID");

                object service;
                Guid audioClientId = IAudioClientId;
                Check(device.Activate(ref audioClientId, CLSCTX_ALL, IntPtr.Zero, out service), "IMMDevice.Activate(IAudioClient)");
                audioClient = (IAudioClient)service;
                Check(audioClient.GetMixFormat(out formatPointer), "IAudioClient.GetMixFormat");
                WaveFormatEx baseFormat = (WaveFormatEx)Marshal.PtrToStructure(formatPointer, typeof(WaveFormatEx));
                int effectiveFormatTag = baseFormat.FormatTag;
                int validBits = baseFormat.BitsPerSample;
                if (baseFormat.FormatTag == WAVE_FORMAT_EXTENSIBLE)
                {
                    WaveFormatExtensible extended = (WaveFormatExtensible)Marshal.PtrToStructure(formatPointer, typeof(WaveFormatExtensible));
                    validBits = extended.ValidBitsPerSample;
                    if (extended.SubFormat == PcmSubFormat) effectiveFormatTag = WAVE_FORMAT_PCM;
                    else if (extended.SubFormat == FloatSubFormat) effectiveFormatTag = WAVE_FORMAT_IEEE_FLOAT;
                    else throw new NotSupportedException("unsupported WAVEFORMATEXTENSIBLE subformat " + extended.SubFormat);
                }
                if (baseFormat.Channels < 1 || baseFormat.Channels > 32 || baseFormat.SampleRate < 8000 || baseFormat.SampleRate > 384000)
                    throw new InvalidDataException("WASAPI mix format channel/rate is outside the qualification bound");
                int bytesPerSample = (baseFormat.BitsPerSample + 7) / 8;
                if (baseFormat.BlockAlign != baseFormat.Channels * bytesPerSample)
                    throw new InvalidDataException("WASAPI mix format block alignment is unsupported");
                long targetFrames = checked((long)Math.Ceiling(requestedDurationSeconds * baseFormat.SampleRate));
                long projectedWaveBytes = checked(44L + targetFrames * baseFormat.Channels * 2L);
                if (projectedWaveBytes > 1048576L) throw new InvalidOperationException("requested real-endpoint capture would exceed the 1 MiB H2 bound");

                Check(audioClient.Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK, 10000000L, 0L, formatPointer, IntPtr.Zero), "IAudioClient.Initialize(loopback)");
                Guid captureClientId = IAudioCaptureClientId;
                Check(audioClient.GetService(ref captureClientId, out service), "IAudioClient.GetService(IAudioCaptureClient)");
                captureClient = (IAudioCaptureClient)service;
                Check(audioClient.Start(), "IAudioClient.Start");
                started = true;
                readySignal = ReadySignalFile.CreateAfterSuccessfulStart(started, readySignalPath);

                int expectedSamples = checked((int)(targetFrames * baseFormat.Channels));
                List<short> samples = new List<short>(expectedSamples);
                long capturedFrames = 0;
                Stopwatch stopwatch = Stopwatch.StartNew();
                double timeoutSeconds = requestedDurationSeconds + 15.0;
                while (capturedFrames < targetFrames)
                {
                    if (stopwatch.Elapsed.TotalSeconds > timeoutSeconds) throw new TimeoutException("WASAPI loopback did not deliver the requested real endpoint frames");
                    uint packetFrames;
                    Check(captureClient.GetNextPacketSize(out packetFrames), "IAudioCaptureClient.GetNextPacketSize");
                    if (packetFrames == 0)
                    {
                        Thread.Sleep(5);
                        continue;
                    }
                    while (packetFrames > 0 && capturedFrames < targetFrames)
                    {
                        IntPtr packetData;
                        uint frames;
                        uint flags;
                        ulong devicePosition;
                        ulong qpcPosition;
                        Check(captureClient.GetBuffer(out packetData, out frames, out flags, out devicePosition, out qpcPosition), "IAudioCaptureClient.GetBuffer");
                        try
                        {
                            uint framesToConsume = (uint)Math.Min((long)frames, targetFrames - capturedFrames);
                            int rawLength = checked((int)(frames * baseFormat.BlockAlign));
                            byte[] raw = new byte[rawLength];
                            if ((flags & AUDCLNT_BUFFERFLAGS_SILENT) == 0)
                            {
                                if (packetData == IntPtr.Zero) throw new InvalidDataException("non-silent WASAPI packet has no data pointer");
                                Marshal.Copy(packetData, raw, 0, raw.Length);
                            }
                            int sampleCount = checked((int)(framesToConsume * baseFormat.Channels));
                            if ((flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0)
                            {
                                // These zeroes represent a real WASAPI silent packet. The PowerShell gate rejects an
                                // all-silent/below-threshold capture; this branch never synthesizes qualifying audio.
                                for (int sampleIndex = 0; sampleIndex < sampleCount; sampleIndex++) samples.Add(0);
                            }
                            else
                            {
                                for (int sampleIndex = 0; sampleIndex < sampleCount; sampleIndex++)
                                {
                                    int rawOffset = checked(sampleIndex * bytesPerSample);
                                    samples.Add(ReadSample(raw, rawOffset, effectiveFormatTag, baseFormat.BitsPerSample, validBits));
                                }
                            }
                            capturedFrames += framesToConsume;
                        }
                        finally
                        {
                            Check(captureClient.ReleaseBuffer(frames), "IAudioCaptureClient.ReleaseBuffer");
                        }
                        Check(captureClient.GetNextPacketSize(out packetFrames), "IAudioCaptureClient.GetNextPacketSize");
                    }
                }
                Check(audioClient.Stop(), "IAudioClient.Stop");
                started = false;
                if (capturedFrames != targetFrames || samples.Count != expectedSamples) throw new InvalidDataException("captured frame/sample count drifted");

                int peak = 0;
                long nonZero = 0;
                for (int index = 0; index < samples.Count; index++)
                {
                    int absolute = samples[index] == Int16.MinValue ? 32768 : Math.Abs((int)samples[index]);
                    if (absolute > peak) peak = absolute;
                    if (samples[index] != 0) nonZero++;
                }
                WriteWave(outputPath, (int)baseFormat.SampleRate, (short)baseFormat.Channels, samples);
                return new CaptureResult
                {
                    EndpointId = observedEndpointId,
                    SampleRate = (int)baseFormat.SampleRate,
                    Channels = baseFormat.Channels,
                    Frames = capturedFrames,
                    DurationSeconds = capturedFrames / (double)baseFormat.SampleRate,
                    PeakAbsolutePcm16 = peak,
                    NonZeroSampleRatio = samples.Count == 0 ? 0.0 : nonZero / (double)samples.Count
                };
            }
            finally
            {
                if (readySignal != null) readySignal.Dispose();
                if (started && audioClient != null) { try { audioClient.Stop(); } catch { } }
                if (formatPointer != IntPtr.Zero) Marshal.FreeCoTaskMem(formatPointer);
                if (captureClient != null) Marshal.FinalReleaseComObject(captureClient);
                if (audioClient != null) Marshal.FinalReleaseComObject(audioClient);
                if (device != null) Marshal.FinalReleaseComObject(device);
                if (enumerator != null) Marshal.FinalReleaseComObject(enumerator);
                if (uninitializeCom) CoUninitialize();
            }
        }
    }
}
'@

try {
    Add-Type -TypeDefinition $captureSource -Language CSharp -ErrorAction Stop
    $capture = [Cf7.AudioV2.EndpointCapture.WasapiLoopbackCapture]::Capture(
        $EndpointId,
        $DurationSeconds,
        $script:TemporaryWav,
        $readySignalFull)

    if ($capture.EndpointId -cne $EndpointId) {
        Fail-Cf7AudioCapture 'captured endpoint identity changed during acquisition'
    }
    if ($capture.DurationSeconds -lt 1.0 -or
            $capture.PeakAbsolutePcm16 -lt $script:MinimumPeakAbsolutePcm16 -or
            $capture.NonZeroSampleRatio -lt $script:MinimumNonZeroSampleRatio) {
        Fail-Cf7AudioCapture ('real endpoint capture is silent/below gate threshold (duration={0}, peak={1}, ratio={2})' -f
            $capture.DurationSeconds, $capture.PeakAbsolutePcm16, $capture.NonZeroSampleRatio)
    }
    $temporaryWavItem = Assert-Cf7PlainFile -Path $script:TemporaryWav -Label 'temporary endpoint capture'
    if ($temporaryWavItem.Length -gt $script:MaximumCaptureBytes) {
        Fail-Cf7AudioCapture 'endpoint capture exceeds the 1 MiB H2 bound'
    }

    $candidateProcess.Refresh()
    if ($candidateProcess.HasExited -or
            -not $candidateProcess.StartTime.ToUniversalTime().Equals($candidateProcessStartUtc) -or
            -not ([IO.Path]::GetFullPath($candidateProcess.Path)).Equals($candidateProcessPath, [StringComparison]::OrdinalIgnoreCase)) {
        Fail-Cf7AudioCapture 'exact candidate process did not remain stable for the capture interval'
    }
    $toolBytesAfter = [IO.File]::ReadAllBytes($PSCommandPath)
    if ((Get-Cf7Sha256Bytes -Bytes $toolBytesAfter) -cne $toolSha256) {
        Fail-Cf7AudioCapture 'capture tool bytes changed while capture was running'
    }

    $captureBytes = [IO.File]::ReadAllBytes($script:TemporaryWav)
    $captureSha256 = Get-Cf7Sha256Bytes -Bytes $captureBytes
    $recordedAtUtc = [DateTime]::UtcNow.ToString('o', [Globalization.CultureInfo]::InvariantCulture)
    $durationJson = Format-Cf7JsonNumber -Value ([double]$capture.DurationSeconds)
    $configurationLines = @(
        '{',
        ('  "candidateBuildIdentity": {0},' -f (ConvertTo-Cf7JsonString $CandidateBuildIdentity)),
        ('  "candidatePayloadClosure": {0},' -f (ConvertTo-Cf7JsonString $CandidatePayloadClosure)),
        ('  "captureBytes": {0},' -f $captureBytes.Length),
        ('  "captureId": {0},' -f (ConvertTo-Cf7JsonString $CaptureId)),
        ('  "captureSha256": {0},' -f (ConvertTo-Cf7JsonString $captureSha256)),
        ('  "caseId": {0},' -f (ConvertTo-Cf7JsonString $CaseId)),
        ('  "channels": {0},' -f [int]$capture.Channels),
        ('  "deviceIdDigest": {0},' -f (ConvertTo-Cf7JsonString $DeviceIdDigest)),
        ('  "durationSeconds": {0},' -f $durationJson),
        '  "format": "pcm_s16le",',
        ('  "recordedAtUtc": {0},' -f (ConvertTo-Cf7JsonString $recordedAtUtc)),
        ('  "runId": {0},' -f (ConvertTo-Cf7JsonString $RunId)),
        ('  "sampleRate": {0},' -f [int]$capture.SampleRate),
        '  "schema": "cf7.audio-v2.endpoint-capture-configuration.v1",',
        ('  "selectedBackend": {0},' -f (ConvertTo-Cf7JsonString $SelectedBackend)),
        '  "tool": {',
        ('    "blobOid": {0},' -f (ConvertTo-Cf7JsonString $toolBlobOid)),
        ('    "path": {0},' -f (ConvertTo-Cf7JsonString $script:CaptureToolRelativePath)),
        ('    "sha256": {0}' -f (ConvertTo-Cf7JsonString $toolSha256)),
        '  }',
        '}'
    )
    $configurationText = [string]::Join("`n", [string[]]$configurationLines) + "`n"
    $utf8NoBom = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($script:TemporaryConfiguration, $configurationText, $utf8NoBom)
    $roundTrip = Get-Content -LiteralPath $script:TemporaryConfiguration -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$roundTrip.schema -cne 'cf7.audio-v2.endpoint-capture-configuration.v1' -or
            [string]$roundTrip.captureSha256 -cne $captureSha256 -or
            [long]$roundTrip.captureBytes -ne $captureBytes.Length) {
        Fail-Cf7AudioCapture 'endpoint capture configuration failed its canonical round-trip preflight'
    }

    [IO.File]::Move($script:TemporaryWav, $outputWavFull)
    $script:PublishedWav = $true
    $script:TemporaryWav = $null
    [IO.File]::Move($script:TemporaryConfiguration, $outputConfigurationFull)
    $script:PublishedConfiguration = $true
    $script:TemporaryConfiguration = $null
    [Console]::Out.Write($configurationText)
} catch {
    if ($script:PublishedConfiguration -and (Test-Path -LiteralPath $outputConfigurationFull -PathType Leaf)) {
        Remove-Item -LiteralPath $outputConfigurationFull -Force
    }
    if ($script:PublishedWav -and (Test-Path -LiteralPath $outputWavFull -PathType Leaf)) {
        Remove-Item -LiteralPath $outputWavFull -Force
    }
    throw
} finally {
    if ($script:TemporaryConfiguration -and (Test-Path -LiteralPath $script:TemporaryConfiguration -PathType Leaf)) {
        Remove-Item -LiteralPath $script:TemporaryConfiguration -Force
    }
    if ($script:TemporaryWav -and (Test-Path -LiteralPath $script:TemporaryWav -PathType Leaf)) {
        Remove-Item -LiteralPath $script:TemporaryWav -Force
    }
}
