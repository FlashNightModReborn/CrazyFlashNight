using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace CF7Launcher.Config
{
    // Only selected by the existing IsDevRepository exemption. Steam's local
    // library list locates installed files; it is not an ownership credential.
    internal static class DevelopmentCollectionAccess
    {
        private const string CollectionDirectory = "CrazyFlasherSeries";
        private static readonly Regex LibraryPath = new Regex("\"path\"\\s+\"((?:\\\\.|[^\"\\\\])*)\"",
            RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

        internal static CollectionAccess Read(string projectRoot, IEnumerable<string> steamRoots = null)
        {
            string canonicalRoot = Path.TrimEndingDirectorySeparator(Path.GetFullPath(projectRoot));
            string sibling = new DirectoryInfo(canonicalRoot).Parent?.Parent?.FullName;
            string install = FindInstall(sibling);
            if (install == null)
            {
                var visited = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                foreach (string root in steamRoots ?? InstalledSteamRoots())
                {
                    foreach (string library in Libraries(root))
                    {
                        if (!visited.Add(library)) continue;
                        install = FindInstall(Path.Combine(library, "steamapps", "common"));
                        if (install != null) break;
                    }
                    if (install != null) break;
                }
            }
            if (install == null) return new CollectionAccess { Error = "development_content_missing" };
            return new CollectionAccess { IsDevelopment = true, InstallDirectory = install,
                AccountNamespace = Convert.ToHexString(SHA256.HashData(
                    Encoding.UTF8.GetBytes("cf7.bookshelf.development.v1:" + canonicalRoot.ToUpperInvariant()))).ToLowerInvariant() };
        }

        private static string FindInstall(string common)
        {
            if (string.IsNullOrWhiteSpace(common)) return null;
            try
            {
                string install = Path.GetFullPath(Path.Combine(common, CollectionDirectory));
                if (!Directory.Exists(install) || (File.GetAttributes(install) & FileAttributes.ReparsePoint) != 0) return null;
                // Individual missing or modified movies are rejected by ReadMovie.
                for (int chapter = 2; chapter <= 6; chapter++)
                    foreach (string language in new[] { "cn", "en" })
                        if (File.Exists(Path.Combine(install, "exes", "crazyflasher" + chapter + "-" + language + "_secure.exe")))
                            return install;
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
            catch (ArgumentException) { }
            return null;
        }

        private static IEnumerable<string> InstalledSteamRoots()
        {
            var roots = new List<string>();
            foreach (var item in new[] {
                (Registry.CurrentUser, @"Software\Valve\Steam", "SteamPath"),
                (Registry.LocalMachine, @"SOFTWARE\WOW6432Node\Valve\Steam", "InstallPath"),
                (Registry.LocalMachine, @"SOFTWARE\Valve\Steam", "InstallPath") })
            {
                try
                {
                    using var key = item.Item1.OpenSubKey(item.Item2, false);
                    if (key?.GetValue(item.Item3) is string value && Path.IsPathFullyQualified(value)) roots.Add(value);
                }
                catch (System.Security.SecurityException) { }
                catch (UnauthorizedAccessException) { }
                catch (IOException) { }
            }
            string programs = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
            if (!string.IsNullOrEmpty(programs)) roots.Add(Path.Combine(programs, "Steam"));
            return roots;
        }

        private static IEnumerable<string> Libraries(string root)
        {
            var libraries = new List<string>();
            if (string.IsNullOrWhiteSpace(root) || !Path.IsPathFullyQualified(root)) return libraries;
            try
            {
                libraries.Add(Path.GetFullPath(root));
                string file = Path.Combine(root, "steamapps", "libraryfolders.vdf");
                if (!File.Exists(file) || new FileInfo(file).Length > 1024 * 1024) return libraries;
                foreach (Match match in LibraryPath.Matches(File.ReadAllText(file)))
                {
                    string path = match.Groups[1].Value.Replace(@"\\", @"\");
                    if (Path.IsPathFullyQualified(path)) libraries.Add(Path.GetFullPath(path));
                    if (libraries.Count >= 64) break;
                }
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
            catch (ArgumentException) { }
            return libraries;
        }
    }
}
