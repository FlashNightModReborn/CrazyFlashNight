// CF7:ME SOL parser P/Invoke wrapper (Rust cdylib: sol_parser.dll)
// C# 5 syntax.

using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Save
{
    /// <summary>
    /// Result of a SOL parse attempt. ReturnCode matches Rust const values in
    /// launcher/native/sol_parser/src/lib.rs.
    /// </summary>
    public sealed class SolParseResult
    {
        // Public mirror of SolParserNative.RC_* 常量，便于跨 assembly（测试）引用。
        public const int RC_OK = 0;
        public const int RC_NOT_FOUND = 1;
        public const int RC_IO_ERROR = 2;
        public const int RC_PARSE_ERROR = 3;
        public const int RC_INVALID_ARGS = 4;
        public const int RC_SERIALIZE_ERROR = 5;

        public int ReturnCode;
        public JObject Data;    // non-null iff ReturnCode == RC_OK
        public string Error;    // diagnostic for logs; null on success
    }

    /// <summary>
    /// Thin P/Invoke wrapper around sol_parser.dll. Callers get a
    /// <see cref="SolParseResult"/>; SolResolver interprets the return code.
    /// </summary>
    internal static class SolParserNative
    {
        private const string DLL = "sol_parser.dll";

        public const int RC_OK = 0;
        public const int RC_NOT_FOUND = 1;
        public const int RC_IO_ERROR = 2;
        public const int RC_PARSE_ERROR = 3;
        public const int RC_INVALID_ARGS = 4;
        public const int RC_SERIALIZE_ERROR = 5;

        [DllImport(DLL, CallingConvention = CallingConvention.Cdecl, EntryPoint = "sol_parse_file")]
        private static extern int sol_parse_file(
            IntPtr pathPtr,
            uint pathLen,
            out IntPtr outJsonPtr,
            out uint outJsonLen);

        [DllImport(DLL, CallingConvention = CallingConvention.Cdecl, EntryPoint = "sol_free")]
        private static extern void sol_free(IntPtr ptr, uint len);

        /// <summary>
        /// Parse the given SOL file into a JSON object.
        /// Non-throwing: returns a result carrying rc + optional JObject + error text.
        /// </summary>
        public static SolParseResult Parse(string path)
        {
            SolParseResult result = new SolParseResult();
            if (string.IsNullOrEmpty(path))
            {
                result.ReturnCode = RC_INVALID_ARGS;
                result.Error = "empty path";
                return result;
            }

            // Pass the path as UTF-16 code units (matches OsString::from_wide on Rust side).
            char[] wide = path.ToCharArray();
            GCHandle pinned = GCHandle.Alloc(wide, GCHandleType.Pinned);
            try
            {
                IntPtr outPtr;
                uint outLen;
                int rc;
                try
                {
                    rc = sol_parse_file(pinned.AddrOfPinnedObject(), (uint)wide.Length, out outPtr, out outLen);
                }
                catch (DllNotFoundException ex)
                {
                    result.ReturnCode = -1;
                    result.Error = "sol_parser.dll missing: " + ex.Message;
                    LogManager.Log("[SolParserNative] " + result.Error);
                    return result;
                }
                catch (EntryPointNotFoundException ex)
                {
                    result.ReturnCode = -2;
                    result.Error = "sol_parser.dll entry point missing: " + ex.Message;
                    LogManager.Log("[SolParserNative] " + result.Error);
                    return result;
                }

                result.ReturnCode = rc;
                if (rc != RC_OK)
                {
                    result.Error = DescribeReturnCode(rc, path);
                    return result;
                }
                if (outPtr == IntPtr.Zero || outLen == 0)
                {
                    result.ReturnCode = RC_SERIALIZE_ERROR;
                    result.Error = "sol_parse_file returned OK but empty buffer";
                    return result;
                }

                byte[] jsonBytes = new byte[outLen];
                Marshal.Copy(outPtr, jsonBytes, 0, (int)outLen);
                sol_free(outPtr, outLen);

                string jsonText = Encoding.UTF8.GetString(jsonBytes);
                try
                {
                    result.Data = JObject.Parse(jsonText);
                }
                catch (Exception ex)
                {
                    result.ReturnCode = RC_SERIALIZE_ERROR;
                    result.Error = "JObject.Parse failed: " + ex.Message;
                }
                return result;
            }
            finally
            {
                pinned.Free();
            }
        }

        private static string DescribeReturnCode(int rc, string path)
        {
            switch (rc)
            {
                case RC_NOT_FOUND:      return "SOL file not found: " + path;
                case RC_IO_ERROR:       return "I/O error reading: " + path;
                case RC_PARSE_ERROR:    return "AMF0 parse error on: " + path;
                case RC_INVALID_ARGS:   return "invalid args to sol_parse_file";
                case RC_SERIALIZE_ERROR:return "serialization error from sol_parser.dll";
                default:                return "sol_parser.dll returned unknown rc=" + rc;
            }
        }
    }
}
