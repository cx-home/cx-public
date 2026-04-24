using System;
using System.IO;
using System.Runtime.InteropServices;

namespace CX;

/// <summary>CX C# binding — P/Invoke wrapper around libcx.</summary>
public static class CxLib
{
    private const string Lib = "cx";

    static CxLib()
    {
        NativeLibrary.SetDllImportResolver(typeof(CxLib).Assembly,
            (name, _, _) =>
            {
                if (name != Lib) return IntPtr.Zero;
                var candidates = new List<string>();

                // 1. Explicit path override
                var envPath = Environment.GetEnvironmentVariable("LIBCX_PATH");
                if (envPath != null) candidates.Add(envPath);

                // 2. Directory override
                var envDir = Environment.GetEnvironmentVariable("LIBCX_LIB_DIR");
                if (envDir != null)
                {
                    candidates.Add(Path.Combine(envDir, "libcx.dylib"));
                    candidates.Add(Path.Combine(envDir, "libcx.so"));
                }

                // 3. System paths
                foreach (var dir in new[] { "/usr/local/lib", "/opt/homebrew/lib", "/usr/lib",
                                            "/usr/lib/x86_64-linux-gnu", "/usr/lib/aarch64-linux-gnu" })
                {
                    candidates.Add(Path.Combine(dir, "libcx.dylib"));
                    candidates.Add(Path.Combine(dir, "libcx.so"));
                }

                // 4. Repo-relative fallback (development)
                try
                {
                    string repoRoot = FindRepoRoot(AppContext.BaseDirectory);
                    candidates.Add(Path.Combine(repoRoot, "vcx", "target", "libcx.dylib"));
                    candidates.Add(Path.Combine(repoRoot, "vcx", "target", "libcx.so"));
                    candidates.Add(Path.Combine(repoRoot, "dist", "lib", "libcx.dylib"));
                    candidates.Add(Path.Combine(repoRoot, "dist", "lib", "libcx.so"));
                }
                catch { /* no repo root found — skip */ }

                foreach (var p in candidates)
                    if (File.Exists(p) && NativeLibrary.TryLoad(p, out var h)) return h;
                throw new DllNotFoundException(
                    "libcx not found. Install with 'sudo make install' or set LIBCX_PATH.");
            });
    }

    private static string FindRepoRoot(string start)
    {
        var dir = new DirectoryInfo(start);
        while (dir != null)
        {
            if (Directory.Exists(Path.Combine(dir.FullName, "vcx"))) return dir.FullName;
            dir = dir.Parent;
        }
        throw new DirectoryNotFoundException("Cannot locate repo root from " + start);
    }

    // ── memory ────────────────────────────────────────────────────────────────

    [DllImport(Lib, EntryPoint = "cx_free")]
    private static extern void Free(IntPtr s);

    [DllImport(Lib, EntryPoint = "cx_version")]
    private static extern IntPtr NativeVersion();

    // ── CX input ──────────────────────────────────────────────────────────────
    [DllImport(Lib, EntryPoint = "cx_to_cx")]          private static extern IntPtr NativeToCx        (string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_to_cx_compact")]  private static extern IntPtr NativeToCxCompact (string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_ast_to_cx")]      private static extern IntPtr NativeAstToCx     (string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_to_xml")]  private static extern IntPtr NativeToXml (string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_to_ast")]  private static extern IntPtr NativeToAst (string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_to_json")] private static extern IntPtr NativeToJson(string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_to_yaml")] private static extern IntPtr NativeToYaml(string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_to_toml")] private static extern IntPtr NativeToToml(string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_to_md")]   private static extern IntPtr NativeToMd  (string i, out IntPtr e);

    // ── XML input ─────────────────────────────────────────────────────────────
    [DllImport(Lib, EntryPoint = "cx_xml_to_cx")]   private static extern IntPtr NativeXmlToCx  (string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_xml_to_xml")]  private static extern IntPtr NativeXmlToXml (string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_xml_to_ast")]  private static extern IntPtr NativeXmlToAst (string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_xml_to_json")] private static extern IntPtr NativeXmlToJson(string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_xml_to_yaml")] private static extern IntPtr NativeXmlToYaml(string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_xml_to_toml")] private static extern IntPtr NativeXmlToToml(string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_xml_to_md")]   private static extern IntPtr NativeXmlToMd  (string i, out IntPtr e);

    // ── JSON input ────────────────────────────────────────────────────────────
    [DllImport(Lib, EntryPoint = "cx_json_to_cx")]   private static extern IntPtr NativeJsonToCx  (string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_json_to_xml")]  private static extern IntPtr NativeJsonToXml (string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_json_to_ast")]  private static extern IntPtr NativeJsonToAst (string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_json_to_json")] private static extern IntPtr NativeJsonToJson(string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_json_to_yaml")] private static extern IntPtr NativeJsonToYaml(string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_json_to_toml")] private static extern IntPtr NativeJsonToToml(string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_json_to_md")]   private static extern IntPtr NativeJsonToMd  (string i, out IntPtr e);

    // ── YAML input ────────────────────────────────────────────────────────────
    [DllImport(Lib, EntryPoint = "cx_yaml_to_cx")]   private static extern IntPtr NativeYamlToCx  (string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_yaml_to_xml")]  private static extern IntPtr NativeYamlToXml (string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_yaml_to_ast")]  private static extern IntPtr NativeYamlToAst (string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_yaml_to_json")] private static extern IntPtr NativeYamlToJson(string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_yaml_to_yaml")] private static extern IntPtr NativeYamlToYaml(string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_yaml_to_toml")] private static extern IntPtr NativeYamlToToml(string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_yaml_to_md")]   private static extern IntPtr NativeYamlToMd  (string i, out IntPtr e);

    // ── TOML input ────────────────────────────────────────────────────────────
    [DllImport(Lib, EntryPoint = "cx_toml_to_cx")]   private static extern IntPtr NativeTomlToCx  (string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_toml_to_xml")]  private static extern IntPtr NativeTomlToXml (string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_toml_to_ast")]  private static extern IntPtr NativeTomlToAst (string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_toml_to_json")] private static extern IntPtr NativeTomlToJson(string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_toml_to_yaml")] private static extern IntPtr NativeTomlToYaml(string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_toml_to_toml")] private static extern IntPtr NativeTomlToToml(string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_toml_to_md")]   private static extern IntPtr NativeTomlToMd  (string i, out IntPtr e);

    // ── MD input ──────────────────────────────────────────────────────────────
    [DllImport(Lib, EntryPoint = "cx_md_to_cx")]   private static extern IntPtr NativeMdToCx  (string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_md_to_xml")]  private static extern IntPtr NativeMdToXml (string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_md_to_ast")]  private static extern IntPtr NativeMdToAst (string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_md_to_json")] private static extern IntPtr NativeMdToJson(string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_md_to_yaml")] private static extern IntPtr NativeMdToYaml(string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_md_to_toml")] private static extern IntPtr NativeMdToToml(string i, out IntPtr e);
    [DllImport(Lib, EntryPoint = "cx_md_to_md")]   private static extern IntPtr NativeMdToMd  (string i, out IntPtr e);

    // ── binary functions ──────────────────────────────────────────────────────
    [DllImport(Lib, EntryPoint = "cx_to_ast_bin",    CharSet = CharSet.Ansi)]
    private static extern IntPtr NativeToAstBin   (string i, out IntPtr e);

    [DllImport(Lib, EntryPoint = "cx_to_events_bin", CharSet = CharSet.Ansi)]
    private static extern IntPtr NativeToEventsBin(string i, out IntPtr e);

    // ── helper ────────────────────────────────────────────────────────────────

    private static string Unwrap(IntPtr result, IntPtr errPtr)
    {
        if (result == IntPtr.Zero)
        {
            string msg = errPtr != IntPtr.Zero
                ? (Marshal.PtrToStringUTF8(errPtr) ?? "unknown error")
                : "unknown error";
            if (errPtr != IntPtr.Zero) Free(errPtr);
            throw new InvalidOperationException(msg);
        }
        string s = Marshal.PtrToStringUTF8(result) ?? "";
        Free(result);
        return s;
    }

    // ── binary helper ─────────────────────────────────────────────────────────

    /// <summary>
    /// Read a [u32 LE: payload_size][payload…] buffer from a native pointer,
    /// copy the payload into a managed byte[], free the native buffer, and return
    /// the payload bytes.
    /// </summary>
    private static byte[] UnwrapBin(IntPtr result, IntPtr errPtr)
    {
        if (result == IntPtr.Zero)
        {
            string msg = errPtr != IntPtr.Zero
                ? (Marshal.PtrToStringUTF8(errPtr) ?? "unknown error")
                : "unknown error";
            if (errPtr != IntPtr.Zero) Free(errPtr);
            throw new InvalidOperationException(msg);
        }

        // Read the 4-byte little-endian payload size.
        uint payloadSize = (uint)(
              Marshal.ReadByte(result, 0)
            | (Marshal.ReadByte(result, 1) << 8)
            | (Marshal.ReadByte(result, 2) << 16)
            | (Marshal.ReadByte(result, 3) << 24));

        var payload = new byte[payloadSize];
        Marshal.Copy(result + 4, payload, 0, (int)payloadSize);
        Free(result);
        return payload;
    }

    /// <summary>Call cx_to_ast_bin and return the raw payload bytes.</summary>
    public static byte[] AstBin(string cxStr)
    {
        var r = NativeToAstBin(cxStr, out var e);
        return UnwrapBin(r, e);
    }

    /// <summary>Call cx_to_events_bin and return the raw payload bytes.</summary>
    public static byte[] EventsBin(string cxStr)
    {
        var r = NativeToEventsBin(cxStr, out var e);
        return UnwrapBin(r, e);
    }

    // ── public API ────────────────────────────────────────────────────────────

    public static string Version()
    {
        var p = NativeVersion();
        var s = Marshal.PtrToStringUTF8(p) ?? "";
        Free(p);
        return s;
    }

    // CX input
    public static string ToCx        (string i) { var r = NativeToCx        (i, out var e); return Unwrap(r, e); }
    public static string ToCxCompact (string i) { var r = NativeToCxCompact (i, out var e); return Unwrap(r, e); }
    public static string AstToCx     (string i) { var r = NativeAstToCx     (i, out var e); return Unwrap(r, e); }
    public static string ToXml (string i) { var r = NativeToXml (i, out var e); return Unwrap(r, e); }
    public static string ToAst (string i) { var r = NativeToAst (i, out var e); return Unwrap(r, e); }
    public static string ToJson(string i) { var r = NativeToJson(i, out var e); return Unwrap(r, e); }
    public static string ToYaml(string i) { var r = NativeToYaml(i, out var e); return Unwrap(r, e); }
    public static string ToToml(string i) { var r = NativeToToml(i, out var e); return Unwrap(r, e); }
    public static string ToMd  (string i) { var r = NativeToMd  (i, out var e); return Unwrap(r, e); }

    // XML input
    public static string XmlToCx  (string i) { var r = NativeXmlToCx  (i, out var e); return Unwrap(r, e); }
    public static string XmlToXml (string i) { var r = NativeXmlToXml (i, out var e); return Unwrap(r, e); }
    public static string XmlToAst (string i) { var r = NativeXmlToAst (i, out var e); return Unwrap(r, e); }
    public static string XmlToJson(string i) { var r = NativeXmlToJson(i, out var e); return Unwrap(r, e); }
    public static string XmlToYaml(string i) { var r = NativeXmlToYaml(i, out var e); return Unwrap(r, e); }
    public static string XmlToToml(string i) { var r = NativeXmlToToml(i, out var e); return Unwrap(r, e); }
    public static string XmlToMd  (string i) { var r = NativeXmlToMd  (i, out var e); return Unwrap(r, e); }

    // JSON input
    public static string JsonToCx  (string i) { var r = NativeJsonToCx  (i, out var e); return Unwrap(r, e); }
    public static string JsonToXml (string i) { var r = NativeJsonToXml (i, out var e); return Unwrap(r, e); }
    public static string JsonToAst (string i) { var r = NativeJsonToAst (i, out var e); return Unwrap(r, e); }
    public static string JsonToJson(string i) { var r = NativeJsonToJson(i, out var e); return Unwrap(r, e); }
    public static string JsonToYaml(string i) { var r = NativeJsonToYaml(i, out var e); return Unwrap(r, e); }
    public static string JsonToToml(string i) { var r = NativeJsonToToml(i, out var e); return Unwrap(r, e); }
    public static string JsonToMd  (string i) { var r = NativeJsonToMd  (i, out var e); return Unwrap(r, e); }

    // YAML input
    public static string YamlToCx  (string i) { var r = NativeYamlToCx  (i, out var e); return Unwrap(r, e); }
    public static string YamlToXml (string i) { var r = NativeYamlToXml (i, out var e); return Unwrap(r, e); }
    public static string YamlToAst (string i) { var r = NativeYamlToAst (i, out var e); return Unwrap(r, e); }
    public static string YamlToJson(string i) { var r = NativeYamlToJson(i, out var e); return Unwrap(r, e); }
    public static string YamlToYaml(string i) { var r = NativeYamlToYaml(i, out var e); return Unwrap(r, e); }
    public static string YamlToToml(string i) { var r = NativeYamlToToml(i, out var e); return Unwrap(r, e); }
    public static string YamlToMd  (string i) { var r = NativeYamlToMd  (i, out var e); return Unwrap(r, e); }

    // TOML input
    public static string TomlToCx  (string i) { var r = NativeTomlToCx  (i, out var e); return Unwrap(r, e); }
    public static string TomlToXml (string i) { var r = NativeTomlToXml (i, out var e); return Unwrap(r, e); }
    public static string TomlToAst (string i) { var r = NativeTomlToAst (i, out var e); return Unwrap(r, e); }
    public static string TomlToJson(string i) { var r = NativeTomlToJson(i, out var e); return Unwrap(r, e); }
    public static string TomlToYaml(string i) { var r = NativeTomlToYaml(i, out var e); return Unwrap(r, e); }
    public static string TomlToToml(string i) { var r = NativeTomlToToml(i, out var e); return Unwrap(r, e); }
    public static string TomlToMd  (string i) { var r = NativeTomlToMd  (i, out var e); return Unwrap(r, e); }

    // MD input
    public static string MdToCx  (string i) { var r = NativeMdToCx  (i, out var e); return Unwrap(r, e); }
    public static string MdToXml (string i) { var r = NativeMdToXml (i, out var e); return Unwrap(r, e); }
    public static string MdToAst (string i) { var r = NativeMdToAst (i, out var e); return Unwrap(r, e); }
    public static string MdToJson(string i) { var r = NativeMdToJson(i, out var e); return Unwrap(r, e); }
    public static string MdToYaml(string i) { var r = NativeMdToYaml(i, out var e); return Unwrap(r, e); }
    public static string MdToToml(string i) { var r = NativeMdToToml(i, out var e); return Unwrap(r, e); }
    public static string MdToMd  (string i) { var r = NativeMdToMd  (i, out var e); return Unwrap(r, e); }
}
