pub mod ast;
pub mod binary;
pub mod cxpath;
pub mod stream;

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;

// ── C declarations ─────────────────────────────────────────────────────────────

extern "C" {
    fn cx_free(s: *mut c_char);
    fn cx_version() -> *mut c_char;

    // CX input
    fn cx_to_cx         (input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_to_cx_compact (input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_ast_to_cx     (input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_to_xml (input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_to_ast (input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_to_json(input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_to_yaml(input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_to_toml(input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_to_md  (input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;

    // XML input
    fn cx_xml_to_cx  (input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_xml_to_xml (input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_xml_to_ast (input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_xml_to_json(input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_xml_to_yaml(input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_xml_to_toml(input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_xml_to_md  (input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;

    // JSON input
    fn cx_json_to_cx  (input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_json_to_xml (input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_json_to_ast (input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_json_to_json(input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_json_to_yaml(input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_json_to_toml(input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_json_to_md  (input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;

    // YAML input
    fn cx_yaml_to_cx  (input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_yaml_to_xml (input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_yaml_to_ast (input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_yaml_to_json(input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_yaml_to_yaml(input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_yaml_to_toml(input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_yaml_to_md  (input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;

    // TOML input
    fn cx_toml_to_cx  (input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_toml_to_xml (input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_toml_to_ast (input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_toml_to_json(input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_toml_to_yaml(input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_toml_to_toml(input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_toml_to_md  (input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;

    // MD input
    fn cx_md_to_cx  (input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_md_to_xml (input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_md_to_ast (input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_md_to_json(input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_md_to_yaml(input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_md_to_toml(input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_md_to_md  (input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;

    // Binary output (CX input only)
    fn cx_to_ast_bin   (input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
    fn cx_to_events_bin(input: *const c_char, err_out: *mut *mut c_char) -> *mut c_char;
}

// ── internal helpers ───────────────────────────────────────────────────────────

type CxFn = unsafe extern "C" fn(*const c_char, *mut *mut c_char) -> *mut c_char;

fn call(f: CxFn, input: &str) -> Result<String, String> {
    let c_input = CString::new(input).map_err(|e| e.to_string())?;
    let mut err_ptr: *mut c_char = ptr::null_mut();
    let out = unsafe { f(c_input.as_ptr(), &mut err_ptr) };
    if out.is_null() {
        if err_ptr.is_null() {
            return Err("unknown error".to_owned());
        }
        let msg = unsafe { CStr::from_ptr(err_ptr).to_string_lossy().into_owned() };
        unsafe { cx_free(err_ptr) };
        return Err(msg);
    }
    let s = unsafe { CStr::from_ptr(out).to_string_lossy().into_owned() };
    unsafe { cx_free(out) };
    Ok(s)
}

/// Call a binary C function and return the payload bytes.
///
/// The C function returns a buffer with layout:
///   [u32 LE: payload_size][payload bytes]
/// This helper reads `payload_size` bytes starting at offset 4, frees the C
/// buffer, and returns the payload as a `Vec<u8>`.
pub(crate) fn call_bin(input: &str, func: &str) -> Result<Vec<u8>, String> {
    let c_input = CString::new(input).map_err(|e| e.to_string())?;
    let mut err_ptr: *mut c_char = ptr::null_mut();
    let raw_ptr: *mut c_char = unsafe {
        match func {
            "cx_to_ast_bin"    => cx_to_ast_bin   (c_input.as_ptr(), &mut err_ptr),
            "cx_to_events_bin" => cx_to_events_bin(c_input.as_ptr(), &mut err_ptr),
            other => return Err(format!("unknown binary function: {}", other)),
        }
    };
    if raw_ptr.is_null() {
        if err_ptr.is_null() {
            return Err("unknown error".to_owned());
        }
        let msg = unsafe { CStr::from_ptr(err_ptr).to_string_lossy().into_owned() };
        unsafe { cx_free(err_ptr) };
        return Err(msg);
    }
    // Read the 4-byte length prefix then copy payload bytes.
    let payload = unsafe {
        let hdr = std::slice::from_raw_parts(raw_ptr as *const u8, 4);
        let size = u32::from_le_bytes([hdr[0], hdr[1], hdr[2], hdr[3]]) as usize;
        let payload_ptr = raw_ptr.add(4) as *const u8;
        let bytes = std::slice::from_raw_parts(payload_ptr, size).to_vec();
        cx_free(raw_ptr);
        bytes
    };
    Ok(payload)
}

// ── version ────────────────────────────────────────────────────────────────────

pub fn version() -> String {
    unsafe {
        let ptr = cx_version();
        let s = CStr::from_ptr(ptr).to_string_lossy().into_owned();
        cx_free(ptr);
        s
    }
}

// ── public API ─────────────────────────────────────────────────────────────────

macro_rules! wrap {
    ($($pub_name:ident => $c_name:ident;)*) => {
        $(
            pub fn $pub_name(input: &str) -> Result<String, String> {
                call($c_name, input)
            }
        )*
    };
}

wrap! {
    // CX input
    to_cx         => cx_to_cx;
    to_cx_compact => cx_to_cx_compact;
    ast_to_cx     => cx_ast_to_cx;
    to_xml  => cx_to_xml;
    to_ast  => cx_to_ast;
    to_json => cx_to_json;
    to_yaml => cx_to_yaml;
    to_toml => cx_to_toml;
    to_md   => cx_to_md;

    // XML input
    xml_to_cx   => cx_xml_to_cx;
    xml_to_xml  => cx_xml_to_xml;
    xml_to_ast  => cx_xml_to_ast;
    xml_to_json => cx_xml_to_json;
    xml_to_yaml => cx_xml_to_yaml;
    xml_to_toml => cx_xml_to_toml;
    xml_to_md   => cx_xml_to_md;

    // JSON input
    json_to_cx   => cx_json_to_cx;
    json_to_xml  => cx_json_to_xml;
    json_to_ast  => cx_json_to_ast;
    json_to_json => cx_json_to_json;
    json_to_yaml => cx_json_to_yaml;
    json_to_toml => cx_json_to_toml;
    json_to_md   => cx_json_to_md;

    // YAML input
    yaml_to_cx   => cx_yaml_to_cx;
    yaml_to_xml  => cx_yaml_to_xml;
    yaml_to_ast  => cx_yaml_to_ast;
    yaml_to_json => cx_yaml_to_json;
    yaml_to_yaml => cx_yaml_to_yaml;
    yaml_to_toml => cx_yaml_to_toml;
    yaml_to_md   => cx_yaml_to_md;

    // TOML input
    toml_to_cx   => cx_toml_to_cx;
    toml_to_xml  => cx_toml_to_xml;
    toml_to_ast  => cx_toml_to_ast;
    toml_to_json => cx_toml_to_json;
    toml_to_yaml => cx_toml_to_yaml;
    toml_to_toml => cx_toml_to_toml;
    toml_to_md   => cx_toml_to_md;

    // MD input
    md_to_cx   => cx_md_to_cx;
    md_to_xml  => cx_md_to_xml;
    md_to_ast  => cx_md_to_ast;
    md_to_json => cx_md_to_json;
    md_to_yaml => cx_md_to_yaml;
    md_to_toml => cx_md_to_toml;
    md_to_md   => cx_md_to_md;
}

// ── binary API ─────────────────────────────────────────────────────────────────

/// Parse a CX string into a `Document` AST via the binary protocol.
pub fn parse(cx_str: &str) -> Result<ast::Document, String> {
    let data = call_bin(cx_str, "cx_to_ast_bin")?;
    binary::decode_ast(&data)
}

/// Parse a CX string into a stream of `StreamEvent`s via the binary protocol.
pub fn stream(cx_str: &str) -> Result<Vec<stream::StreamEvent>, String> {
    let data = call_bin(cx_str, "cx_to_events_bin")?;
    binary::decode_events(&data)
}
