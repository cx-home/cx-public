package cx;

import com.sun.jna.*;
import com.sun.jna.ptr.PointerByReference;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.file.*;
import java.util.Arrays;
import java.util.List;
import java.util.function.BiFunction;

/**
 * CX Java binding — JNA wrapper around libcx.
 */
public class CxLib {

    /** JNA native interface mirroring cx.h */
    interface NativeLib extends Library {
        void    cx_free   (Pointer s);
        Pointer cx_version();

        // CX input
        Pointer cx_to_cx          (String input, PointerByReference errOut);
        Pointer cx_to_cx_compact  (String input, PointerByReference errOut);
        Pointer cx_ast_to_cx      (String input, PointerByReference errOut);
        Pointer cx_to_xml  (String input, PointerByReference errOut);
        Pointer cx_to_ast  (String input, PointerByReference errOut);
        Pointer cx_to_json (String input, PointerByReference errOut);
        Pointer cx_to_yaml (String input, PointerByReference errOut);
        Pointer cx_to_toml (String input, PointerByReference errOut);
        Pointer cx_to_md   (String input, PointerByReference errOut);

        // XML input
        Pointer cx_xml_to_cx   (String input, PointerByReference errOut);
        Pointer cx_xml_to_xml  (String input, PointerByReference errOut);
        Pointer cx_xml_to_ast  (String input, PointerByReference errOut);
        Pointer cx_xml_to_json (String input, PointerByReference errOut);
        Pointer cx_xml_to_yaml (String input, PointerByReference errOut);
        Pointer cx_xml_to_toml (String input, PointerByReference errOut);
        Pointer cx_xml_to_md   (String input, PointerByReference errOut);

        // JSON input
        Pointer cx_json_to_cx   (String input, PointerByReference errOut);
        Pointer cx_json_to_xml  (String input, PointerByReference errOut);
        Pointer cx_json_to_ast  (String input, PointerByReference errOut);
        Pointer cx_json_to_json (String input, PointerByReference errOut);
        Pointer cx_json_to_yaml (String input, PointerByReference errOut);
        Pointer cx_json_to_toml (String input, PointerByReference errOut);
        Pointer cx_json_to_md   (String input, PointerByReference errOut);

        // YAML input
        Pointer cx_yaml_to_cx   (String input, PointerByReference errOut);
        Pointer cx_yaml_to_xml  (String input, PointerByReference errOut);
        Pointer cx_yaml_to_ast  (String input, PointerByReference errOut);
        Pointer cx_yaml_to_json (String input, PointerByReference errOut);
        Pointer cx_yaml_to_yaml (String input, PointerByReference errOut);
        Pointer cx_yaml_to_toml (String input, PointerByReference errOut);
        Pointer cx_yaml_to_md   (String input, PointerByReference errOut);

        // TOML input
        Pointer cx_toml_to_cx   (String input, PointerByReference errOut);
        Pointer cx_toml_to_xml  (String input, PointerByReference errOut);
        Pointer cx_toml_to_ast  (String input, PointerByReference errOut);
        Pointer cx_toml_to_json (String input, PointerByReference errOut);
        Pointer cx_toml_to_yaml (String input, PointerByReference errOut);
        Pointer cx_toml_to_toml (String input, PointerByReference errOut);
        Pointer cx_toml_to_md   (String input, PointerByReference errOut);

        // MD input
        Pointer cx_md_to_cx   (String input, PointerByReference errOut);
        Pointer cx_md_to_xml  (String input, PointerByReference errOut);
        Pointer cx_md_to_ast  (String input, PointerByReference errOut);
        Pointer cx_md_to_json (String input, PointerByReference errOut);
        Pointer cx_md_to_yaml (String input, PointerByReference errOut);
        Pointer cx_md_to_toml (String input, PointerByReference errOut);
        Pointer cx_md_to_md   (String input, PointerByReference errOut);

        // Binary output
        Pointer cx_to_ast_bin    (String input, PointerByReference errOut);
        Pointer cx_to_events_bin (String input, PointerByReference errOut);
    }

    private static final NativeLib LIB;

    static {
        String os   = System.getProperty("os.name", "").toLowerCase();
        String name = os.contains("mac") ? "libcx.dylib" : "libcx.so";
        List<String> candidates = new java.util.ArrayList<>();

        // 1. Explicit path override
        String envPath = System.getenv("LIBCX_PATH");
        if (envPath != null) candidates.add(envPath);

        // 2. Directory override
        String envDir = System.getenv("LIBCX_LIB_DIR");
        if (envDir != null) candidates.add(envDir + "/" + name);

        // 3. System paths
        for (String dir : new String[]{"/usr/local/lib", "/opt/homebrew/lib", "/usr/lib",
                                       "/usr/lib/x86_64-linux-gnu", "/usr/lib/aarch64-linux-gnu"})
            candidates.add(dir + "/" + name);

        // 4. Repo-relative fallback (development)
        try {
            Path base = Paths.get(CxLib.class.getProtectionDomain()
                    .getCodeSource().getLocation().toURI());
            Path repo = base.getParent().getParent().getParent().getParent().getParent();
            candidates.add(repo.resolve("vcx/target/" + name).toString());
            candidates.add(repo.resolve("dist/lib/"   + name).toString());
        } catch (Exception ignored) {}

        String found = candidates.stream()
                .filter(p -> Files.exists(Paths.get(p)))
                .findFirst()
                .orElseThrow(() -> new RuntimeException(
                        "libcx not found. Install with 'sudo make install' or set LIBCX_PATH."));
        LIB = Native.load(found, NativeLib.class);
    }

    // ── helper ─────────────────────────────────────────────────────────────────

    private static String callFn(
            BiFunction<String, PointerByReference, Pointer> fn,
            String input) {
        PointerByReference errRef = new PointerByReference();
        Pointer out = fn.apply(input, errRef);
        if (out == null) {
            Pointer ep  = errRef.getValue();
            String  msg = (ep != null) ? ep.getString(0) : "unknown error";
            if (ep != null) LIB.cx_free(ep);
            throw new RuntimeException(msg);
        }
        String s = out.getString(0);
        LIB.cx_free(out);
        return s;
    }

    // ── public API ─────────────────────────────────────────────────────────────

    public static String version() {
        Pointer p = LIB.cx_version();
        String s  = p.getString(0);
        LIB.cx_free(p);
        return s;
    }

    // CX input
    public static String toCx        (String input) { return callFn(LIB::cx_to_cx,         input); }
    public static String toCxCompact (String input) { return callFn(LIB::cx_to_cx_compact, input); }
    public static String astToCx     (String input) { return callFn(LIB::cx_ast_to_cx,     input); }
    public static String toXml (String input) { return callFn(LIB::cx_to_xml,  input); }
    public static String toAst (String input) { return callFn(LIB::cx_to_ast,  input); }
    public static String toJson(String input) { return callFn(LIB::cx_to_json, input); }
    public static String toYaml(String input) { return callFn(LIB::cx_to_yaml, input); }
    public static String toToml(String input) { return callFn(LIB::cx_to_toml, input); }
    public static String toMd  (String input) { return callFn(LIB::cx_to_md,   input); }

    // XML input
    public static String xmlToCx  (String input) { return callFn(LIB::cx_xml_to_cx,   input); }
    public static String xmlToXml (String input) { return callFn(LIB::cx_xml_to_xml,  input); }
    public static String xmlToAst (String input) { return callFn(LIB::cx_xml_to_ast,  input); }
    public static String xmlToJson(String input) { return callFn(LIB::cx_xml_to_json, input); }
    public static String xmlToYaml(String input) { return callFn(LIB::cx_xml_to_yaml, input); }
    public static String xmlToToml(String input) { return callFn(LIB::cx_xml_to_toml, input); }
    public static String xmlToMd  (String input) { return callFn(LIB::cx_xml_to_md,   input); }

    // JSON input
    public static String jsonToCx  (String input) { return callFn(LIB::cx_json_to_cx,   input); }
    public static String jsonToXml (String input) { return callFn(LIB::cx_json_to_xml,  input); }
    public static String jsonToAst (String input) { return callFn(LIB::cx_json_to_ast,  input); }
    public static String jsonToJson(String input) { return callFn(LIB::cx_json_to_json, input); }
    public static String jsonToYaml(String input) { return callFn(LIB::cx_json_to_yaml, input); }
    public static String jsonToToml(String input) { return callFn(LIB::cx_json_to_toml, input); }
    public static String jsonToMd  (String input) { return callFn(LIB::cx_json_to_md,   input); }

    // YAML input
    public static String yamlToCx  (String input) { return callFn(LIB::cx_yaml_to_cx,   input); }
    public static String yamlToXml (String input) { return callFn(LIB::cx_yaml_to_xml,  input); }
    public static String yamlToAst (String input) { return callFn(LIB::cx_yaml_to_ast,  input); }
    public static String yamlToJson(String input) { return callFn(LIB::cx_yaml_to_json, input); }
    public static String yamlToYaml(String input) { return callFn(LIB::cx_yaml_to_yaml, input); }
    public static String yamlToToml(String input) { return callFn(LIB::cx_yaml_to_toml, input); }
    public static String yamlToMd  (String input) { return callFn(LIB::cx_yaml_to_md,   input); }

    // TOML input
    public static String tomlToCx  (String input) { return callFn(LIB::cx_toml_to_cx,   input); }
    public static String tomlToXml (String input) { return callFn(LIB::cx_toml_to_xml,  input); }
    public static String tomlToAst (String input) { return callFn(LIB::cx_toml_to_ast,  input); }
    public static String tomlToJson(String input) { return callFn(LIB::cx_toml_to_json, input); }
    public static String tomlToYaml(String input) { return callFn(LIB::cx_toml_to_yaml, input); }
    public static String tomlToToml(String input) { return callFn(LIB::cx_toml_to_toml, input); }
    public static String tomlToMd  (String input) { return callFn(LIB::cx_toml_to_md,   input); }

    // MD input
    public static String mdToCx  (String input) { return callFn(LIB::cx_md_to_cx,   input); }
    public static String mdToXml (String input) { return callFn(LIB::cx_md_to_xml,  input); }
    public static String mdToAst (String input) { return callFn(LIB::cx_md_to_ast,  input); }
    public static String mdToJson(String input) { return callFn(LIB::cx_md_to_json, input); }
    public static String mdToYaml(String input) { return callFn(LIB::cx_md_to_yaml, input); }
    public static String mdToToml(String input) { return callFn(LIB::cx_md_to_toml, input); }
    public static String mdToMd  (String input) { return callFn(LIB::cx_md_to_md,   input); }

    // ── binary helpers ─────────────────────────────────────────────────────────

    /**
     * Call cx_to_ast_bin, read the length-prefixed payload, free the pointer,
     * and return the raw payload bytes.
     */
    public static byte[] astBin(String cxStr) {
        return callBinFn(LIB::cx_to_ast_bin, cxStr);
    }

    /**
     * Call cx_to_events_bin, read the length-prefixed payload, free the pointer,
     * and return the raw payload bytes.
     */
    public static byte[] eventsBin(String cxStr) {
        return callBinFn(LIB::cx_to_events_bin, cxStr);
    }

    private static byte[] callBinFn(
            BiFunction<String, PointerByReference, Pointer> fn,
            String input) {
        PointerByReference errRef = new PointerByReference();
        Pointer out = fn.apply(input, errRef);
        if (out == null) {
            Pointer ep  = errRef.getValue();
            String  msg = (ep != null) ? ep.getString(0) : "unknown error";
            if (ep != null) LIB.cx_free(ep);
            throw new RuntimeException(msg);
        }
        // Buffer layout: [u32 LE: payload_size][payload bytes]
        byte[] sizeBytes = out.getByteArray(0, 4);
        int payloadSize = ByteBuffer.wrap(sizeBytes).order(ByteOrder.LITTLE_ENDIAN).getInt();
        byte[] payload = out.getByteArray(4, payloadSize);
        LIB.cx_free(out);
        return payload;
    }
}
