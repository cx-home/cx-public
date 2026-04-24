package cx

import com.sun.jna.*
import com.sun.jna.ptr.PointerByReference
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths

/**
 * CX Kotlin binding — JNA wrapper around libcx.
 */
object CxLib {

    /** JNA native interface mirroring cx.h */
    interface NativeLib : Library {
        fun cx_free(s: Pointer)
        fun cx_version(): Pointer

        // Binary output (returns length-prefixed buffer)
        fun cx_to_ast_bin   (input: String, errOut: PointerByReference): Pointer?
        fun cx_to_events_bin(input: String, errOut: PointerByReference): Pointer?

        // CX input
        fun cx_to_cx          (input: String, errOut: PointerByReference): Pointer?
        fun cx_to_cx_compact  (input: String, errOut: PointerByReference): Pointer?
        fun cx_ast_to_cx      (input: String, errOut: PointerByReference): Pointer?
        fun cx_to_xml  (input: String, errOut: PointerByReference): Pointer?
        fun cx_to_ast  (input: String, errOut: PointerByReference): Pointer?
        fun cx_to_json (input: String, errOut: PointerByReference): Pointer?
        fun cx_to_yaml (input: String, errOut: PointerByReference): Pointer?
        fun cx_to_toml (input: String, errOut: PointerByReference): Pointer?
        fun cx_to_md   (input: String, errOut: PointerByReference): Pointer?

        // XML input
        fun cx_xml_to_cx   (input: String, errOut: PointerByReference): Pointer?
        fun cx_xml_to_xml  (input: String, errOut: PointerByReference): Pointer?
        fun cx_xml_to_ast  (input: String, errOut: PointerByReference): Pointer?
        fun cx_xml_to_json (input: String, errOut: PointerByReference): Pointer?
        fun cx_xml_to_yaml (input: String, errOut: PointerByReference): Pointer?
        fun cx_xml_to_toml (input: String, errOut: PointerByReference): Pointer?
        fun cx_xml_to_md   (input: String, errOut: PointerByReference): Pointer?

        // JSON input
        fun cx_json_to_cx   (input: String, errOut: PointerByReference): Pointer?
        fun cx_json_to_xml  (input: String, errOut: PointerByReference): Pointer?
        fun cx_json_to_ast  (input: String, errOut: PointerByReference): Pointer?
        fun cx_json_to_json (input: String, errOut: PointerByReference): Pointer?
        fun cx_json_to_yaml (input: String, errOut: PointerByReference): Pointer?
        fun cx_json_to_toml (input: String, errOut: PointerByReference): Pointer?
        fun cx_json_to_md   (input: String, errOut: PointerByReference): Pointer?

        // YAML input
        fun cx_yaml_to_cx   (input: String, errOut: PointerByReference): Pointer?
        fun cx_yaml_to_xml  (input: String, errOut: PointerByReference): Pointer?
        fun cx_yaml_to_ast  (input: String, errOut: PointerByReference): Pointer?
        fun cx_yaml_to_json (input: String, errOut: PointerByReference): Pointer?
        fun cx_yaml_to_yaml (input: String, errOut: PointerByReference): Pointer?
        fun cx_yaml_to_toml (input: String, errOut: PointerByReference): Pointer?
        fun cx_yaml_to_md   (input: String, errOut: PointerByReference): Pointer?

        // TOML input
        fun cx_toml_to_cx   (input: String, errOut: PointerByReference): Pointer?
        fun cx_toml_to_xml  (input: String, errOut: PointerByReference): Pointer?
        fun cx_toml_to_ast  (input: String, errOut: PointerByReference): Pointer?
        fun cx_toml_to_json (input: String, errOut: PointerByReference): Pointer?
        fun cx_toml_to_yaml (input: String, errOut: PointerByReference): Pointer?
        fun cx_toml_to_toml (input: String, errOut: PointerByReference): Pointer?
        fun cx_toml_to_md   (input: String, errOut: PointerByReference): Pointer?

        // MD input
        fun cx_md_to_cx   (input: String, errOut: PointerByReference): Pointer?
        fun cx_md_to_xml  (input: String, errOut: PointerByReference): Pointer?
        fun cx_md_to_ast  (input: String, errOut: PointerByReference): Pointer?
        fun cx_md_to_json (input: String, errOut: PointerByReference): Pointer?
        fun cx_md_to_yaml (input: String, errOut: PointerByReference): Pointer?
        fun cx_md_to_toml (input: String, errOut: PointerByReference): Pointer?
        fun cx_md_to_md   (input: String, errOut: PointerByReference): Pointer?
    }

    private lateinit var lib: NativeLib

    init {
        val os   = System.getProperty("os.name", "").lowercase()
        val name = if (os.contains("mac")) "libcx.dylib" else "libcx.so"
        val candidates = mutableListOf<Path>()

        // 1. Explicit path override
        System.getenv("LIBCX_PATH")?.let { candidates.add(Paths.get(it)) }

        // 2. Directory override
        System.getenv("LIBCX_LIB_DIR")?.let { candidates.add(Paths.get(it, name)) }

        // 3. System paths
        for (dir in listOf("/usr/local/lib", "/opt/homebrew/lib", "/usr/lib",
                           "/usr/lib/x86_64-linux-gnu", "/usr/lib/aarch64-linux-gnu"))
            candidates.add(Paths.get(dir, name))

        // 4. Repo-relative fallback (development)
        try {
            val base = Paths.get(CxLib::class.java.protectionDomain.codeSource.location.toURI())
            val repo = base.parent.parent.parent.parent.parent.parent.parent
            candidates.add(repo.resolve("vcx/target/$name"))
            candidates.add(repo.resolve("dist/lib/$name"))
        } catch (_: Exception) {}

        val found = candidates.firstOrNull { Files.exists(it) }
            ?: throw RuntimeException("libcx not found. Install with 'sudo make install' or set LIBCX_PATH.")
        lib = Native.load(found.toString(), NativeLib::class.java)
    }

    // ── helper ─────────────────────────────────────────────────────────────────

    private fun callFn(fn: (String, PointerByReference) -> Pointer?, input: String): String {
        val errRef = PointerByReference()
        val out = fn(input, errRef)
        if (out == null) {
            val ep  = errRef.value
            val msg = ep?.getString(0) ?: "unknown error"
            if (ep != null) lib.cx_free(ep)
            throw RuntimeException(msg)
        }
        val s = out.getString(0)
        lib.cx_free(out)
        return s
    }

    private fun callBinFn(fn: (String, PointerByReference) -> Pointer?, input: String): ByteArray {
        val errRef = PointerByReference()
        val out = fn(input, errRef)
        if (out == null) {
            val ep  = errRef.value
            val msg = ep?.getString(0) ?: "unknown error"
            if (ep != null) lib.cx_free(ep)
            throw RuntimeException(msg)
        }
        // Read 4-byte little-endian payload size
        val b0 = out.getByte(0).toInt() and 0xFF
        val b1 = out.getByte(1).toInt() and 0xFF
        val b2 = out.getByte(2).toInt() and 0xFF
        val b3 = out.getByte(3).toInt() and 0xFF
        val payloadSize = b0 or (b1 shl 8) or (b2 shl 16) or (b3 shl 24)
        val payload = out.getByteArray(4, payloadSize)
        lib.cx_free(out)
        return payload
    }

    // ── public API ─────────────────────────────────────────────────────────────

    fun version(): String {
        val p = lib.cx_version()
        val s = p.getString(0)
        lib.cx_free(p)
        return s
    }

    /** Return binary-encoded AST payload for the given CX string. */
    fun astBin(cxStr: String): ByteArray = callBinFn(lib::cx_to_ast_bin, cxStr)

    /** Return binary-encoded events payload for the given CX string. */
    fun eventsBin(cxStr: String): ByteArray = callBinFn(lib::cx_to_events_bin, cxStr)

    // CX input
    fun toCx        (input: String) = callFn(lib::cx_to_cx,         input)
    fun toCxCompact (input: String) = callFn(lib::cx_to_cx_compact, input)
    fun astToCx     (input: String) = callFn(lib::cx_ast_to_cx,     input)
    fun toXml (input: String) = callFn(lib::cx_to_xml,  input)
    fun toAst (input: String) = callFn(lib::cx_to_ast,  input)
    fun toJson(input: String) = callFn(lib::cx_to_json, input)
    fun toYaml(input: String) = callFn(lib::cx_to_yaml, input)
    fun toToml(input: String) = callFn(lib::cx_to_toml, input)
    fun toMd  (input: String) = callFn(lib::cx_to_md,   input)

    // XML input
    fun xmlToCx  (input: String) = callFn(lib::cx_xml_to_cx,   input)
    fun xmlToXml (input: String) = callFn(lib::cx_xml_to_xml,  input)
    fun xmlToAst (input: String) = callFn(lib::cx_xml_to_ast,  input)
    fun xmlToJson(input: String) = callFn(lib::cx_xml_to_json, input)
    fun xmlToYaml(input: String) = callFn(lib::cx_xml_to_yaml, input)
    fun xmlToToml(input: String) = callFn(lib::cx_xml_to_toml, input)
    fun xmlToMd  (input: String) = callFn(lib::cx_xml_to_md,   input)

    // JSON input
    fun jsonToCx  (input: String) = callFn(lib::cx_json_to_cx,   input)
    fun jsonToXml (input: String) = callFn(lib::cx_json_to_xml,  input)
    fun jsonToAst (input: String) = callFn(lib::cx_json_to_ast,  input)
    fun jsonToJson(input: String) = callFn(lib::cx_json_to_json, input)
    fun jsonToYaml(input: String) = callFn(lib::cx_json_to_yaml, input)
    fun jsonToToml(input: String) = callFn(lib::cx_json_to_toml, input)
    fun jsonToMd  (input: String) = callFn(lib::cx_json_to_md,   input)

    // YAML input
    fun yamlToCx  (input: String) = callFn(lib::cx_yaml_to_cx,   input)
    fun yamlToXml (input: String) = callFn(lib::cx_yaml_to_xml,  input)
    fun yamlToAst (input: String) = callFn(lib::cx_yaml_to_ast,  input)
    fun yamlToJson(input: String) = callFn(lib::cx_yaml_to_json, input)
    fun yamlToYaml(input: String) = callFn(lib::cx_yaml_to_yaml, input)
    fun yamlToToml(input: String) = callFn(lib::cx_yaml_to_toml, input)
    fun yamlToMd  (input: String) = callFn(lib::cx_yaml_to_md,   input)

    // TOML input
    fun tomlToCx  (input: String) = callFn(lib::cx_toml_to_cx,   input)
    fun tomlToXml (input: String) = callFn(lib::cx_toml_to_xml,  input)
    fun tomlToAst (input: String) = callFn(lib::cx_toml_to_ast,  input)
    fun tomlToJson(input: String) = callFn(lib::cx_toml_to_json, input)
    fun tomlToYaml(input: String) = callFn(lib::cx_toml_to_yaml, input)
    fun tomlToToml(input: String) = callFn(lib::cx_toml_to_toml, input)
    fun tomlToMd  (input: String) = callFn(lib::cx_toml_to_md,   input)

    // MD input
    fun mdToCx  (input: String) = callFn(lib::cx_md_to_cx,   input)
    fun mdToXml (input: String) = callFn(lib::cx_md_to_xml,  input)
    fun mdToAst (input: String) = callFn(lib::cx_md_to_ast,  input)
    fun mdToJson(input: String) = callFn(lib::cx_md_to_json, input)
    fun mdToYaml(input: String) = callFn(lib::cx_md_to_yaml, input)
    fun mdToToml(input: String) = callFn(lib::cx_md_to_toml, input)
    fun mdToMd  (input: String) = callFn(lib::cx_md_to_md,   input)
}
