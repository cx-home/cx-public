#ifndef CX_H
#define CX_H

#ifdef __cplusplus
extern "C" {
#endif

/*
 * CX C API — implemented in V (vcx/)
 *
 * Grammar v3.3 / AST v2.3. All 6×7 input/output format combinations
 * (6 input formats × 7 outputs including AST) plus cx_free and cx_version.
 *
 * Calling convention:
 *   - input   must be a NUL-terminated UTF-8 string; must not be NULL.
 *   - err_out may be NULL if you don't need error details.
 *   - On success: returns a heap-allocated, NUL-terminated UTF-8 string.
 *   - On error:   returns NULL; if err_out is non-NULL sets *err_out to a
 *                 heap-allocated error message string.
 *   - All returned strings (including *err_out) must be released with
 *     cx_free(). Never pass them to the system free().
 *
 * Thread safety: all conversion functions are stateless — safe to call from
 * multiple threads concurrently without synchronisation.
 *
 * Formats: cx  xml  json (semantic)  yaml  toml  md
 * AST output: cx_to_ast / cx_*_to_ast — full parse tree as JSON
 */

/* ── CX input ──────────────────────────────────────────────────────────────── */

char* cx_to_cx         (const char* input, char** err_out);
char* cx_to_cx_compact (const char* input, char** err_out);
char* cx_to_xml (const char* input, char** err_out);
char* cx_to_ast (const char* input, char** err_out);
char* cx_to_json(const char* input, char** err_out);
char* cx_to_yaml(const char* input, char** err_out);
char* cx_to_toml(const char* input, char** err_out);
char* cx_to_md  (const char* input, char** err_out);

/* ── XML input ─────────────────────────────────────────────────────────────── */

char* cx_xml_to_cx  (const char* input, char** err_out);
char* cx_xml_to_xml (const char* input, char** err_out);
char* cx_xml_to_ast (const char* input, char** err_out);
char* cx_xml_to_json(const char* input, char** err_out);
char* cx_xml_to_yaml(const char* input, char** err_out);
char* cx_xml_to_toml(const char* input, char** err_out);
char* cx_xml_to_md  (const char* input, char** err_out);

/* ── JSON input ────────────────────────────────────────────────────────────── */

char* cx_json_to_cx  (const char* input, char** err_out);
char* cx_json_to_xml (const char* input, char** err_out);
char* cx_json_to_ast (const char* input, char** err_out);
char* cx_json_to_json(const char* input, char** err_out);
char* cx_json_to_yaml(const char* input, char** err_out);
char* cx_json_to_toml(const char* input, char** err_out);
char* cx_json_to_md  (const char* input, char** err_out);

/* ── YAML input ────────────────────────────────────────────────────────────── */

char* cx_yaml_to_cx  (const char* input, char** err_out);
char* cx_yaml_to_xml (const char* input, char** err_out);
char* cx_yaml_to_ast (const char* input, char** err_out);
char* cx_yaml_to_json(const char* input, char** err_out);
char* cx_yaml_to_yaml(const char* input, char** err_out);
char* cx_yaml_to_toml(const char* input, char** err_out);
char* cx_yaml_to_md  (const char* input, char** err_out);

/* ── TOML input ────────────────────────────────────────────────────────────── */

char* cx_toml_to_cx  (const char* input, char** err_out);
char* cx_toml_to_xml (const char* input, char** err_out);
char* cx_toml_to_ast (const char* input, char** err_out);
char* cx_toml_to_json(const char* input, char** err_out);
char* cx_toml_to_yaml(const char* input, char** err_out);
char* cx_toml_to_toml(const char* input, char** err_out);
char* cx_toml_to_md  (const char* input, char** err_out);

/* ── MD input ─────────────────────────────────────────────────────────────── */

char* cx_md_to_cx  (const char* input, char** err_out);
char* cx_md_to_xml (const char* input, char** err_out);
char* cx_md_to_ast (const char* input, char** err_out);
char* cx_md_to_json(const char* input, char** err_out);
char* cx_md_to_yaml(const char* input, char** err_out);
char* cx_md_to_toml(const char* input, char** err_out);
char* cx_md_to_md  (const char* input, char** err_out);

/* ── AST input ─────────────────────────────────────────────────────────────── */

/** Convert AST JSON (output of cx_to_ast / cx_*_to_ast) back to canonical CX. */
char* cx_ast_to_cx (const char* input, char** err_out);

/* ── memory ────────────────────────────────────────────────────────────────── */

/** Free any string returned by this library. */
void cx_free(char* s);

/** Return the library version string (e.g. "1.0.0"). Caller must cx_free(). */
char* cx_version(void);

/* ── Streaming ─────────────────────────────────────────────────────────────── */

/**
 * cx_to_events: parse CX input and return all streaming events as a JSON array.
 * Retained for tooling use. Language bindings should use cx_to_events_bin.
 */
char* cx_to_events(const char* input, char** err_out);

/* ── Binary protocol ───────────────────────────────────────────────────────── */

/**
 * cx_to_events_bin / cx_to_ast_bin: binary wire format for streaming events
 * and AST. Faster than the JSON equivalents (~2.5× encode, ~3.5× decode).
 *
 * Return format: [u32 LE: payload_size][payload bytes]
 * Read the first 4 bytes as a little-endian uint32 to get payload_size, then
 * read that many bytes. Free the entire buffer with cx_free().
 * The buffer is NOT a null-terminated string — it is binary data.
 *
 * cx_to_events_bin payload:
 *   [u32 LE: event_count] [events...]
 *   Each event: [u8: type_id] [payload per type]
 *   Type IDs: 0x01=StartDoc 0x02=EndDoc 0x03=StartElement 0x04=EndElement
 *             0x05=Text 0x06=Scalar 0x07=Comment 0x08=PI
 *             0x09=EntityRef 0x0A=RawText 0x0B=Alias
 *   Strings: [u32 LE: byte_len][bytes]  OptStrings: [u8: 0|1][str if 1]
 *   StartElement: str:name optstr:anchor optstr:data_type optstr:merge
 *                 u16:attr_count attrs[]
 *   Attr: str:name str:value optstr:data_type
 *
 * cx_to_ast_bin payload:
 *   [u8: version=1] [u16 LE: prolog_count] [prolog nodes...]
 *   [u16 LE: element_count] [element nodes...]
 *   Node type IDs: 0x01=Element 0x02=Text 0x03=Scalar 0x04=Comment
 *                  0x05=RawText 0x06=EntityRef 0x07=Alias 0x08=PI
 *                  0x09=XMLDecl 0x0A=CXDirective 0x0C=BlockContent 0xFF=skip
 *   Element: str:name optstr:anchor optstr:data_type optstr:merge
 *            u16:attr_count attrs[] u16:child_count nodes[]
 *
 * Binary format spec: see the cx_to_events_bin/cx_to_ast_bin comments above.
 */
char* cx_to_events_bin(const char* input, char** err_out);
char* cx_to_ast_bin   (const char* input, char** err_out);

#ifdef __cplusplus
}
#endif

#endif /* CX_H */
