"""
Thin ctypes wrapper around libcx (V implementation).

Locates libcx.dylib / libcx.so relative to this file. The primary library
is the V implementation in vcx/target/. All public functions return Python
str or raise RuntimeError on parse failure.
"""
import ctypes
import os
import pathlib

def _load_lib():
    lib_name = "libcx.dylib" if os.uname().sysname == "Darwin" else "libcx.so"

    # 1. Explicit path override
    if env := os.environ.get("LIBCX_PATH"):
        return ctypes.CDLL(env)

    candidates = []

    # 2. Directory override
    if env_dir := os.environ.get("LIBCX_LIB_DIR"):
        candidates.append(pathlib.Path(env_dir) / lib_name)

    # 3. System paths
    for sys_dir in ("/usr/local/lib", "/opt/homebrew/lib", "/usr/lib",
                    "/usr/lib/x86_64-linux-gnu", "/usr/lib/aarch64-linux-gnu"):
        candidates.append(pathlib.Path(sys_dir) / lib_name)

    # 4. Repo-relative fallback (development)
    base = pathlib.Path(__file__).resolve().parent.parent.parent.parent
    candidates += [
        base / "vcx" / "target" / lib_name,
        base / "dist" / "lib" / lib_name,
    ]

    for p in candidates:
        if p.exists():
            return ctypes.CDLL(str(p))
    raise RuntimeError(
        f"libcx not found. Install with 'sudo make install' or set LIBCX_PATH.\n"
        f"Looked in: {[str(c) for c in candidates]}"
    )

_lib = _load_lib()

_lib.cx_free.restype  = None
_lib.cx_free.argtypes = [ctypes.c_char_p]

_lib.cx_version.restype  = ctypes.c_char_p
_lib.cx_version.argtypes = []

def _setup(fn):
    fn.restype  = ctypes.c_char_p
    fn.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_char_p)]

_all_fns = (
    "cx_to_cx",   "cx_to_xml",   "cx_to_ast",   "cx_to_json",   "cx_to_yaml",   "cx_to_toml",   "cx_to_md",
    "cx_xml_to_cx",  "cx_xml_to_xml",  "cx_xml_to_ast",  "cx_xml_to_json",  "cx_xml_to_yaml",  "cx_xml_to_toml",  "cx_xml_to_md",
    "cx_json_to_cx", "cx_json_to_xml", "cx_json_to_ast", "cx_json_to_json", "cx_json_to_yaml", "cx_json_to_toml", "cx_json_to_md",
    "cx_yaml_to_cx", "cx_yaml_to_xml", "cx_yaml_to_ast", "cx_yaml_to_json", "cx_yaml_to_yaml", "cx_yaml_to_toml", "cx_yaml_to_md",
    "cx_toml_to_cx", "cx_toml_to_xml", "cx_toml_to_ast", "cx_toml_to_json", "cx_toml_to_yaml", "cx_toml_to_toml", "cx_toml_to_md",
    "cx_md_to_cx",   "cx_md_to_xml",   "cx_md_to_ast",   "cx_md_to_json",   "cx_md_to_yaml",   "cx_md_to_toml",   "cx_md_to_md",
    "cx_to_events",
    "cx_ast_to_cx", "cx_to_cx_compact",
)

# Binary protocol functions return length-prefixed raw buffers, not C strings.
# Use c_void_p so ctypes returns the raw integer address instead of auto-decoding.
_bin_fns = ("cx_to_events_bin", "cx_to_ast_bin")
for _name in _bin_fns:
    _fn = getattr(_lib, _name)
    _fn.restype  = ctypes.c_void_p
    _fn.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_char_p)]

for _name in _all_fns:
    _setup(getattr(_lib, _name))

def _call(fn, text: str) -> str:
    err = ctypes.c_char_p(None)
    out = fn(text.encode(), ctypes.byref(err))
    if out is None:
        msg = err.value.decode() if err.value else "unknown error"
        raise RuntimeError(msg)
    return out.decode()

def version() -> str: return _lib.cx_version().decode()

def to_events(cx_str: str) -> str:
    """Return all streaming events as a JSON array string."""
    return _call(_lib.cx_to_events, cx_str)

# CX input
def to_cx        (src: str) -> str: return _call(_lib.cx_to_cx,          src)
def to_cx_compact(src: str) -> str: return _call(_lib.cx_to_cx_compact,  src)
def to_xml (src: str) -> str: return _call(_lib.cx_to_xml,  src)
def to_ast (src: str) -> str: return _call(_lib.cx_to_ast,  src)
def ast_to_cx    (src: str) -> str: return _call(_lib.cx_ast_to_cx,      src)
def to_json(src: str) -> str: return _call(_lib.cx_to_json, src)
def to_yaml(src: str) -> str: return _call(_lib.cx_to_yaml, src)
def to_toml(src: str) -> str: return _call(_lib.cx_to_toml, src)
def to_md  (src: str) -> str: return _call(_lib.cx_to_md,   src)

# XML input
def xml_to_cx  (src: str) -> str: return _call(_lib.cx_xml_to_cx,   src)
def xml_to_xml (src: str) -> str: return _call(_lib.cx_xml_to_xml,  src)
def xml_to_ast (src: str) -> str: return _call(_lib.cx_xml_to_ast,  src)
def xml_to_json(src: str) -> str: return _call(_lib.cx_xml_to_json, src)
def xml_to_yaml(src: str) -> str: return _call(_lib.cx_xml_to_yaml, src)
def xml_to_toml(src: str) -> str: return _call(_lib.cx_xml_to_toml, src)
def xml_to_md  (src: str) -> str: return _call(_lib.cx_xml_to_md,   src)

# JSON input
def json_to_cx  (src: str) -> str: return _call(_lib.cx_json_to_cx,   src)
def json_to_xml (src: str) -> str: return _call(_lib.cx_json_to_xml,  src)
def json_to_ast (src: str) -> str: return _call(_lib.cx_json_to_ast,  src)
def json_to_json(src: str) -> str: return _call(_lib.cx_json_to_json, src)
def json_to_yaml(src: str) -> str: return _call(_lib.cx_json_to_yaml, src)
def json_to_toml(src: str) -> str: return _call(_lib.cx_json_to_toml, src)
def json_to_md  (src: str) -> str: return _call(_lib.cx_json_to_md,   src)

# YAML input
def yaml_to_cx  (src: str) -> str: return _call(_lib.cx_yaml_to_cx,   src)
def yaml_to_xml (src: str) -> str: return _call(_lib.cx_yaml_to_xml,  src)
def yaml_to_ast (src: str) -> str: return _call(_lib.cx_yaml_to_ast,  src)
def yaml_to_json(src: str) -> str: return _call(_lib.cx_yaml_to_json, src)
def yaml_to_yaml(src: str) -> str: return _call(_lib.cx_yaml_to_yaml, src)
def yaml_to_toml(src: str) -> str: return _call(_lib.cx_yaml_to_toml, src)
def yaml_to_md  (src: str) -> str: return _call(_lib.cx_yaml_to_md,   src)

# TOML input
def toml_to_cx  (src: str) -> str: return _call(_lib.cx_toml_to_cx,   src)
def toml_to_xml (src: str) -> str: return _call(_lib.cx_toml_to_xml,  src)
def toml_to_ast (src: str) -> str: return _call(_lib.cx_toml_to_ast,  src)
def toml_to_json(src: str) -> str: return _call(_lib.cx_toml_to_json, src)
def toml_to_yaml(src: str) -> str: return _call(_lib.cx_toml_to_yaml, src)
def toml_to_toml(src: str) -> str: return _call(_lib.cx_toml_to_toml, src)
def toml_to_md  (src: str) -> str: return _call(_lib.cx_toml_to_md,   src)

# MD input
def md_to_cx  (src: str) -> str: return _call(_lib.cx_md_to_cx,   src)
def md_to_xml (src: str) -> str: return _call(_lib.cx_md_to_xml,  src)
def md_to_ast (src: str) -> str: return _call(_lib.cx_md_to_ast,  src)
def md_to_json(src: str) -> str: return _call(_lib.cx_md_to_json, src)
def md_to_yaml(src: str) -> str: return _call(_lib.cx_md_to_yaml, src)
def md_to_toml(src: str) -> str: return _call(_lib.cx_md_to_toml, src)
def md_to_md  (src: str) -> str: return _call(_lib.cx_md_to_md,   src)
