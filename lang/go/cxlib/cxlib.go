// Package cxlib is a CGo binding for libcx.
package cxlib

/*
// Search: system install (make install), then repo-relative dev tree.
// Override at build time: CGO_LDFLAGS="-L/custom/path -Wl,-rpath,/custom/path"
#cgo CFLAGS:  -I${SRCDIR}/../../../include -I/usr/local/include -I/opt/homebrew/include
#cgo LDFLAGS: -lcx
#cgo darwin LDFLAGS: -L${SRCDIR}/../../../vcx/target -L${SRCDIR}/../../../dist/lib -L/usr/local/lib -L/opt/homebrew/lib -Wl,-rpath,${SRCDIR}/../../../vcx/target -Wl,-rpath,/usr/local/lib -Wl,-rpath,/opt/homebrew/lib
#cgo linux  LDFLAGS: -L${SRCDIR}/../../../vcx/target -L${SRCDIR}/../../../dist/lib -L/usr/local/lib                     -Wl,-rpath,${SRCDIR}/../../../vcx/target -Wl,-rpath,/usr/local/lib
#include "cx.h"
#include <stdlib.h>
extern char* cx_to_ast_bin(const char* input, char** err_out);
extern char* cx_to_events_bin(const char* input, char** err_out);
extern char* cx_ast_to_cx(const char* input, char** err_out);
extern char* cx_to_cx_compact(const char* input, char** err_out);
*/
import "C"
import (
	"encoding/binary"
	"fmt"
	"unsafe"
)

func cStr(s string) *C.char {
	return C.CString(s)
}

func goStr(p *C.char) string {
	s := C.GoString(p)
	C.cx_free(p)
	return s
}

func callC(fn func(*C.char, **C.char) *C.char, input string) (string, error) {
	cs := C.CString(input)
	defer C.free(unsafe.Pointer(cs))
	var errPtr *C.char
	out := fn(cs, &errPtr)
	if out == nil {
		if errPtr != nil {
			msg := C.GoString(errPtr)
			C.cx_free(errPtr)
			return "", fmt.Errorf("%s", msg)
		}
		return "", fmt.Errorf("unknown error")
	}
	s := C.GoString(out)
	C.cx_free(out)
	return s, nil
}

func extractBinPayload(raw unsafe.Pointer, errPtr *C.char) ([]byte, error) {
	if raw == nil {
		if errPtr != nil {
			msg := C.GoString(errPtr)
			C.cx_free(errPtr)
			return nil, fmt.Errorf("%s", msg)
		}
		return nil, fmt.Errorf("unknown error")
	}
	// First 4 bytes: payload size as u32 LE
	sizeBytes := (*[4]byte)(raw)[:]
	payloadSize := binary.LittleEndian.Uint32(sizeBytes)
	// Copy payload (bytes after the 4-byte header)
	payload := make([]byte, payloadSize)
	if payloadSize > 0 {
		src := unsafe.Slice((*byte)(unsafe.Pointer(uintptr(raw)+4)), payloadSize)
		copy(payload, src)
	}
	C.cx_free((*C.char)(raw))
	return payload, nil
}

// ToAstBin returns the raw binary AST for a CX input string.
func ToAstBin(input string) ([]byte, error) {
	cs := C.CString(input)
	defer C.free(unsafe.Pointer(cs))
	var errPtr *C.char
	raw := unsafe.Pointer(C.cx_to_ast_bin(cs, &errPtr))
	return extractBinPayload(raw, errPtr)
}

// ToEventsBin returns the raw binary events for a CX input string.
func ToEventsBin(input string) ([]byte, error) {
	cs := C.CString(input)
	defer C.free(unsafe.Pointer(cs))
	var errPtr *C.char
	raw := unsafe.Pointer(C.cx_to_events_bin(cs, &errPtr))
	return extractBinPayload(raw, errPtr)
}

// Version returns the library version string.
func Version() string {
	ptr := C.cx_version()
	s := C.GoString(ptr)
	C.cx_free(ptr)
	return s
}

// CX input
func ToCx(input string) (string, error) {
	cs := C.CString(input)
	defer C.free(unsafe.Pointer(cs))
	var ep *C.char
	out := C.cx_to_cx(cs, &ep)
	if out == nil {
		if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }
		return "", fmt.Errorf("unknown error")
	}
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func ToCxCompact(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_to_cx_compact(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func AstToCx(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_ast_to_cx(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func ToXml(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_to_xml(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func ToAst(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_to_ast(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func ToJson(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_to_json(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func ToYaml(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_to_yaml(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func ToToml(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_to_toml(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func ToMd(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_to_md(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}

// XML input
func XmlToCx(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_xml_to_cx(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func XmlToXml(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_xml_to_xml(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func XmlToAst(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_xml_to_ast(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func XmlToJson(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_xml_to_json(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func XmlToYaml(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_xml_to_yaml(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func XmlToToml(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_xml_to_toml(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func XmlToMd(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_xml_to_md(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}

// JSON input
func JsonToCx(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_json_to_cx(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func JsonToXml(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_json_to_xml(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func JsonToAst(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_json_to_ast(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func JsonToJson(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_json_to_json(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func JsonToYaml(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_json_to_yaml(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func JsonToToml(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_json_to_toml(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func JsonToMd(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_json_to_md(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}

// YAML input
func YamlToCx(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_yaml_to_cx(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func YamlToXml(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_yaml_to_xml(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func YamlToAst(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_yaml_to_ast(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func YamlToJson(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_yaml_to_json(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func YamlToYaml(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_yaml_to_yaml(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func YamlToToml(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_yaml_to_toml(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func YamlToMd(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_yaml_to_md(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}

// TOML input
func TomlToCx(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_toml_to_cx(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func TomlToXml(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_toml_to_xml(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func TomlToAst(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_toml_to_ast(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func TomlToJson(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_toml_to_json(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func TomlToYaml(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_toml_to_yaml(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func TomlToToml(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_toml_to_toml(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func TomlToMd(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_toml_to_md(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}

// MD input
func MdToCx(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_md_to_cx(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func MdToXml(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_md_to_xml(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func MdToAst(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_md_to_ast(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func MdToJson(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_md_to_json(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func MdToYaml(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_md_to_yaml(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func MdToToml(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_md_to_toml(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
func MdToMd(input string) (string, error) {
	cs := C.CString(input); defer C.free(unsafe.Pointer(cs)); var ep *C.char
	out := C.cx_md_to_md(cs, &ep); if out == nil { if ep != nil { m := C.GoString(ep); C.cx_free(ep); return "", fmt.Errorf("%s", m) }; return "", fmt.Errorf("unknown error") }
	s := C.GoString(out); C.cx_free(out); return s, nil
}
