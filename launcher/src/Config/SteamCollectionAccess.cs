using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

namespace CF7Launcher.Config
{
    // Development access is a separate source, never a fabricated Steam account.
    internal sealed class CollectionAccess
    {
        public string Error, InstallDirectory, AccountNamespace, PersonaName;
        public ulong SteamId;
        public bool DlcInstalled, IsDevelopment;
        public bool Ready => Error == null && (IsDevelopment || SteamId != 0)
            && !string.IsNullOrEmpty(InstallDirectory) && !string.IsNullOrEmpty(AccountNamespace);
        internal static string NamespaceFor(ulong id) => Convert.ToHexString(SHA256.HashData(
            Encoding.UTF8.GetBytes("cf7.bookshelf.original.v1:" + id))).ToLowerInvariant();
    }

    internal static class SteamCollectionAccess
    {
        internal const uint AppId = 1540150, DlcAppId = 2917650;
        // Match the main game's existing Git exemption once per content service.
        // An ordinary install never falls back to local files after a Steam error.
        internal static Func<CollectionAccess> CreateReader(string root, Func<CollectionAccess> readSteam = null)
            => SteamOwnershipCheck.IsDevRepository(root)
                ? () => DevelopmentCollectionAccess.Read(root)
                : readSteam ?? (() => Read(root));
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate IntPtr Interface();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)]
        private delegate bool AppFlag(IntPtr self, uint appId);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)]
        private delegate bool LoggedOn(IntPtr self);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate ulong SteamId(IntPtr self);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] private delegate IntPtr Persona(IntPtr self);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        private delegate uint InstallDir(IntPtr self, uint appId, [Out] byte[] path, uint capacity);
        private static T Bind<T>(IntPtr module, params string[] names) where T : Delegate
        {
            IntPtr export = SteamOwnershipCheck.Export(module, names);
            if (export == IntPtr.Zero) throw new MissingMethodException();
            return Marshal.GetDelegateForFunctionPointer<T>(export);
        }
        internal static CollectionAccess Read(string root)
        {
            lock (SteamOwnershipCheck.ClientGate)
            {
                try
                {
                    if (!SteamOwnershipCheck.TryGetContentClient(root, out var module, out var apps, out string error))
                        return new CollectionAccess { Error = error };
                    var user = Bind<Interface>(module, "SteamAPI_SteamUser_v023", "SteamAPI_SteamUser_v022", "SteamAPI_SteamUser_v021", "SteamAPI_SteamUser_v020", "SteamAPI_SteamUser_v019")();
                    if (user == IntPtr.Zero || !Bind<LoggedOn>(module, "SteamAPI_ISteamUser_BLoggedOn")(user))
                        return new CollectionAccess { Error = "steam_unavailable" };
                    if (!Bind<AppFlag>(module, "SteamAPI_ISteamApps_BIsSubscribedApp")(apps, AppId))
                        return new CollectionAccess { Error = "not_owned" };
                    if (!Bind<AppFlag>(module, "SteamAPI_ISteamApps_BIsAppInstalled")(apps, AppId))
                        return new CollectionAccess { Error = "not_installed" };
                    var buffer = new byte[4096];
                    uint length = Bind<InstallDir>(module, "SteamAPI_ISteamApps_GetAppInstallDir")(apps, AppId, buffer, (uint)buffer.Length);
                    if (length == 0 || length >= buffer.Length || buffer[length] != 0)
                        return new CollectionAccess { Error = "not_installed" };
                    string path = Encoding.UTF8.GetString(buffer, 0, (int)length);
                    if (!Path.IsPathFullyQualified(path) || !Directory.Exists(path))
                        return new CollectionAccess { Error = "not_installed" };
                    ulong id = Bind<SteamId>(module, "SteamAPI_ISteamUser_GetSteamID")(user);
                    if (id == 0) return new CollectionAccess { Error = "steam_unavailable" };
                    var friends = Bind<Interface>(module, "SteamAPI_SteamFriends_v017", "SteamAPI_SteamFriends_v016", "SteamAPI_SteamFriends_v015")();
                    if (friends == IntPtr.Zero) return new CollectionAccess { Error = "steam_unavailable" };
                    string name = Marshal.PtrToStringUTF8(Bind<Persona>(module, "SteamAPI_ISteamFriends_GetPersonaName")(friends)) ?? "";
                    return new CollectionAccess { InstallDirectory = Path.GetFullPath(path), SteamId = id,
                        AccountNamespace = CollectionAccess.NamespaceFor(id), PersonaName = name,
                        DlcInstalled = Bind<AppFlag>(module, "SteamAPI_ISteamApps_BIsDlcInstalled")(apps, DlcAppId) };
                }
                catch (MissingMethodException) { return new CollectionAccess { Error = "sdk_unavailable" }; }
                catch (Exception) { return new CollectionAccess { Error = "steam_unavailable" }; }
            }
        }
    }
}
