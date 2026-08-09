[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Current-user, local, read-only Core Audio inventory. This intentionally
# exposes the raw IMMDevice EndpointId only on stdout; it does not activate an
# audio client, change a default endpoint, or persist the inventory.
$source = @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace Cf7.AudioV2.EndpointInventory
{
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
        [PreserveSig] int EnumAudioEndpoints(EDataFlow dataFlow, uint stateMask, out IMMDeviceCollection devices);
        [PreserveSig] int GetDefaultAudioEndpoint(EDataFlow dataFlow, ERole role, out IMMDevice endpoint);
        [PreserveSig] int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice endpoint);
        [PreserveSig] int RegisterEndpointNotificationCallback(IntPtr callback);
        [PreserveSig] int UnregisterEndpointNotificationCallback(IntPtr callback);
    }

    [ComImport]
    [Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDeviceCollection
    {
        [PreserveSig] int GetCount(out uint count);
        [PreserveSig] int Item(uint index, out IMMDevice device);
    }

    [ComImport]
    [Guid("D666063F-1587-4E43-81F1-B948E807363F")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IMMDevice
    {
        [PreserveSig] int Activate(ref Guid interfaceId, uint classContext, IntPtr activationParameters, [MarshalAs(UnmanagedType.IUnknown)] out object result);
        [PreserveSig] int OpenPropertyStore(uint access, out IPropertyStore properties);
        [PreserveSig] int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        [PreserveSig] int GetState(out uint state);
    }

    [ComImport]
    [Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IPropertyStore
    {
        [PreserveSig] int GetCount(out uint count);
        [PreserveSig] int GetAt(uint index, out PropertyKey key);
        [PreserveSig] int GetValue(ref PropertyKey key, out PropVariant value);
        [PreserveSig] int SetValue(ref PropertyKey key, ref PropVariant value);
        [PreserveSig] int Commit();
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct PropertyKey
    {
        internal Guid FormatId;
        internal uint PropertyId;

        internal PropertyKey(Guid formatId, uint propertyId)
        {
            FormatId = formatId;
            PropertyId = propertyId;
        }
    }

    [StructLayout(LayoutKind.Explicit)]
    internal struct PropVariant
    {
        [FieldOffset(0)] internal ushort ValueType;
        [FieldOffset(8)] internal IntPtr PointerValue;
    }

    public sealed class EndpointRow
    {
        public string EndpointId { get; set; }
        public string FriendlyName { get; set; }
        public string[] DefaultRoles { get; set; }
    }

    public static class EndpointReader
    {
        private const uint DeviceStateActive = 1;
        private const uint StorageRead = 0;
        private const ushort VariantWideString = 31;
        private const int ElementNotFound = unchecked((int)0x80070490);
        private static readonly PropertyKey FriendlyNameKey = new PropertyKey(
            new Guid("A45C254E-DF1C-4EFD-8020-67D146A850E0"), 14);

        [DllImport("ole32.dll")]
        private static extern int PropVariantClear(ref PropVariant value);

        private static void Check(int hresult, string operation)
        {
            if (hresult < 0)
                throw new COMException(operation + " failed", hresult);
        }

        private static void Release(object value)
        {
            if (value != null && Marshal.IsComObject(value))
                Marshal.FinalReleaseComObject(value);
        }

        private static string ReadId(IMMDevice device)
        {
            string id;
            Check(device.GetId(out id), "IMMDevice.GetId");
            if (String.IsNullOrEmpty(id))
                throw new InvalidOperationException("IMMDevice returned an empty EndpointId");
            return id;
        }

        private static string ReadFriendlyName(IMMDevice device)
        {
            IPropertyStore store = null;
            PropVariant value = new PropVariant();
            try
            {
                Check(device.OpenPropertyStore(StorageRead, out store), "IMMDevice.OpenPropertyStore");
                PropertyKey key = FriendlyNameKey;
                Check(store.GetValue(ref key, out value), "IPropertyStore.GetValue(PKEY_Device_FriendlyName)");
                if (value.ValueType != VariantWideString || value.PointerValue == IntPtr.Zero)
                    throw new InvalidOperationException("PKEY_Device_FriendlyName is not a non-null VT_LPWSTR");
                return Marshal.PtrToStringUni(value.PointerValue) ?? String.Empty;
            }
            finally
            {
                PropVariantClear(ref value);
                Release(store);
            }
        }

        private static Dictionary<string, List<string>> ReadDefaultRoles(IMMDeviceEnumerator enumerator)
        {
            Dictionary<string, List<string>> result = new Dictionary<string, List<string>>(StringComparer.Ordinal);
            ERole[] roles = new ERole[] { ERole.Console, ERole.Multimedia, ERole.Communications };
            string[] names = new string[] { "console", "multimedia", "communications" };
            for (int index = 0; index < roles.Length; index++)
            {
                IMMDevice endpoint = null;
                try
                {
                    int hresult = enumerator.GetDefaultAudioEndpoint(EDataFlow.Render, roles[index], out endpoint);
                    if (hresult == ElementNotFound)
                        continue;
                    Check(hresult, "IMMDeviceEnumerator.GetDefaultAudioEndpoint");
                    string id = ReadId(endpoint);
                    List<string> endpointRoles;
                    if (!result.TryGetValue(id, out endpointRoles))
                    {
                        endpointRoles = new List<string>();
                        result.Add(id, endpointRoles);
                    }
                    endpointRoles.Add(names[index]);
                }
                finally
                {
                    Release(endpoint);
                }
            }
            foreach (List<string> rolesForEndpoint in result.Values)
                rolesForEndpoint.Sort(StringComparer.Ordinal);
            return result;
        }

        public static EndpointRow[] EnumerateActiveRenderEndpoints()
        {
            IMMDeviceEnumerator enumerator = null;
            IMMDeviceCollection collection = null;
            try
            {
                enumerator = (IMMDeviceEnumerator)new MMDeviceEnumeratorComObject();
                Dictionary<string, List<string>> defaultRoles = ReadDefaultRoles(enumerator);
                Check(enumerator.EnumAudioEndpoints(EDataFlow.Render, DeviceStateActive, out collection),
                    "IMMDeviceEnumerator.EnumAudioEndpoints(active render)");
                uint count;
                Check(collection.GetCount(out count), "IMMDeviceCollection.GetCount");
                List<EndpointRow> rows = new List<EndpointRow>();
                for (uint index = 0; index < count; index++)
                {
                    IMMDevice endpoint = null;
                    try
                    {
                        Check(collection.Item(index, out endpoint), "IMMDeviceCollection.Item");
                        uint state;
                        Check(endpoint.GetState(out state), "IMMDevice.GetState");
                        if (state != DeviceStateActive)
                            throw new InvalidOperationException("active-render enumeration returned a non-active endpoint");
                        string id = ReadId(endpoint);
                        List<string> roles;
                        rows.Add(new EndpointRow {
                            EndpointId = id,
                            FriendlyName = ReadFriendlyName(endpoint),
                            DefaultRoles = defaultRoles.TryGetValue(id, out roles) ? roles.ToArray() : new string[0]
                        });
                    }
                    finally
                    {
                        Release(endpoint);
                    }
                }
                rows.Sort(delegate(EndpointRow left, EndpointRow right) {
                    return StringComparer.Ordinal.Compare(left.EndpointId, right.EndpointId);
                });
                return rows.ToArray();
            }
            finally
            {
                Release(collection);
                Release(enumerator);
            }
        }
    }
}
'@

Add-Type -TypeDefinition $source -Language CSharp

$endpoints = @([Cf7.AudioV2.EndpointInventory.EndpointReader]::EnumerateActiveRenderEndpoints())
$outputRows = @($endpoints | ForEach-Object {
    $endpointIdBytes = [Text.Encoding]::UTF8.GetBytes($_.EndpointId)
    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $deviceIdDigest = ([BitConverter]::ToString($hasher.ComputeHash($endpointIdBytes))).Replace('-', '')
    } finally {
        $hasher.Dispose()
    }
    [ordered]@{
        defaultRoles = @($_.DefaultRoles)
        deviceIdDigest = $deviceIdDigest
        endpointId = $_.EndpointId
        friendlyName = $_.FriendlyName
        state = 'active'
    }
})

$result = [ordered]@{
    endpoints = $outputRows
    schema = 'cf7.audio-v2.playback-endpoint-inventory.v1'
}
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::Out.WriteLine(($result | ConvertTo-Json -Compress -Depth 6))
