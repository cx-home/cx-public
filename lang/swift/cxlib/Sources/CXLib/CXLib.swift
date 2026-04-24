import CXC
import Foundation

/// CX Swift binding — thin wrapper around libcx via the C module.
public enum CXError: Error, LocalizedError {
    case parse(String)
    public var errorDescription: String? {
        if case .parse(let m) = self { return m }
        return nil
    }
}

// ── internal helpers ─────────────────────────────────────────────────────────

private func _callFn(
    _ fn: (UnsafePointer<CChar>?,
           UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> UnsafeMutablePointer<CChar>?,
    _ input: String) throws -> String {
    var errPtr: UnsafeMutablePointer<CChar>? = nil
    guard let out = input.withCString({ fn($0, &errPtr) }) else {
        let msg: String
        if let ep = errPtr { msg = String(cString: ep); cx_free(ep) }
        else                { msg = "unknown error" }
        throw CXError.parse(msg)
    }
    let s = String(cString: out)
    cx_free(out)
    return s
}

/// Call a binary-returning C function and decode the length-prefixed buffer into Data.
private func _callBin(
    _ input: String,
    fn: (UnsafePointer<CChar>?, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> UnsafeMutablePointer<CChar>?) throws -> Data {
    var errPtr: UnsafeMutablePointer<CChar>? = nil
    guard let ptr = input.withCString({ fn($0, &errPtr) }) else {
        let msg: String
        if let ep = errPtr { msg = String(cString: ep); cx_free(ep) }
        else                { msg = "unknown error" }
        throw CXError.parse(msg)
    }
    // Buffer layout: [u32 LE: payload_size][payload bytes]
    let rawPtr = UnsafeRawPointer(ptr)
    let sizeLE = rawPtr.load(as: UInt32.self)
    let size = Int(UInt32(littleEndian: sizeLE))
    let data = Data(bytes: rawPtr.advanced(by: 4), count: size)
    cx_free(ptr)
    return data
}

// ── CXLib namespace ───────────────────────────────────────────────────────────

/// Namespace for CX library functions. Also exposes all format-conversion
/// functions as static methods (used internally by CXDocument).
public enum CXLib {

    // ── binary (used by BinaryDecoder) ─────────────────────────────────────────

    public static func astBin(_ cxStr: String) throws -> Data {
        return try _callBin(cxStr, fn: cx_to_ast_bin)
    }

    public static func eventsBin(_ cxStr: String) throws -> Data {
        return try _callBin(cxStr, fn: cx_to_events_bin)
    }

    // ── version ────────────────────────────────────────────────────────────────

    public static func version() -> String {
        let p = cx_version()!
        let s = String(cString: p)
        cx_free(p)
        return s
    }

    // ── CX input ───────────────────────────────────────────────────────────────

    public static func toCx        (_ input: String) throws -> String { try _callFn(cx_to_cx,         input) }
    public static func toCxCompact (_ input: String) throws -> String { try _callFn(cx_to_cx_compact, input) }
    public static func astToCx     (_ input: String) throws -> String { try _callFn(cx_ast_to_cx,     input) }
    public static func toXml (_ input: String) throws -> String { try _callFn(cx_to_xml,  input) }
    public static func toAst (_ input: String) throws -> String { try _callFn(cx_to_ast,  input) }
    public static func toJson(_ input: String) throws -> String { try _callFn(cx_to_json, input) }
    public static func toYaml(_ input: String) throws -> String { try _callFn(cx_to_yaml, input) }
    public static func toToml(_ input: String) throws -> String { try _callFn(cx_to_toml, input) }
    public static func toMd  (_ input: String) throws -> String { try _callFn(cx_to_md,   input) }

    // ── XML input ──────────────────────────────────────────────────────────────

    public static func xmlToCx  (_ input: String) throws -> String { try _callFn(cx_xml_to_cx,   input) }
    public static func xmlToXml (_ input: String) throws -> String { try _callFn(cx_xml_to_xml,  input) }
    public static func xmlToAst (_ input: String) throws -> String { try _callFn(cx_xml_to_ast,  input) }
    public static func xmlToJson(_ input: String) throws -> String { try _callFn(cx_xml_to_json, input) }
    public static func xmlToYaml(_ input: String) throws -> String { try _callFn(cx_xml_to_yaml, input) }
    public static func xmlToToml(_ input: String) throws -> String { try _callFn(cx_xml_to_toml, input) }
    public static func xmlToMd  (_ input: String) throws -> String { try _callFn(cx_xml_to_md,   input) }

    // ── JSON input ─────────────────────────────────────────────────────────────

    public static func jsonToCx  (_ input: String) throws -> String { try _callFn(cx_json_to_cx,   input) }
    public static func jsonToXml (_ input: String) throws -> String { try _callFn(cx_json_to_xml,  input) }
    public static func jsonToAst (_ input: String) throws -> String { try _callFn(cx_json_to_ast,  input) }
    public static func jsonToJson(_ input: String) throws -> String { try _callFn(cx_json_to_json, input) }
    public static func jsonToYaml(_ input: String) throws -> String { try _callFn(cx_json_to_yaml, input) }
    public static func jsonToToml(_ input: String) throws -> String { try _callFn(cx_json_to_toml, input) }
    public static func jsonToMd  (_ input: String) throws -> String { try _callFn(cx_json_to_md,   input) }

    // ── YAML input ─────────────────────────────────────────────────────────────

    public static func yamlToCx  (_ input: String) throws -> String { try _callFn(cx_yaml_to_cx,   input) }
    public static func yamlToXml (_ input: String) throws -> String { try _callFn(cx_yaml_to_xml,  input) }
    public static func yamlToAst (_ input: String) throws -> String { try _callFn(cx_yaml_to_ast,  input) }
    public static func yamlToJson(_ input: String) throws -> String { try _callFn(cx_yaml_to_json, input) }
    public static func yamlToYaml(_ input: String) throws -> String { try _callFn(cx_yaml_to_yaml, input) }
    public static func yamlToToml(_ input: String) throws -> String { try _callFn(cx_yaml_to_toml, input) }
    public static func yamlToMd  (_ input: String) throws -> String { try _callFn(cx_yaml_to_md,   input) }

    // ── TOML input ─────────────────────────────────────────────────────────────

    public static func tomlToCx  (_ input: String) throws -> String { try _callFn(cx_toml_to_cx,   input) }
    public static func tomlToXml (_ input: String) throws -> String { try _callFn(cx_toml_to_xml,  input) }
    public static func tomlToAst (_ input: String) throws -> String { try _callFn(cx_toml_to_ast,  input) }
    public static func tomlToJson(_ input: String) throws -> String { try _callFn(cx_toml_to_json, input) }
    public static func tomlToYaml(_ input: String) throws -> String { try _callFn(cx_toml_to_yaml, input) }
    public static func tomlToToml(_ input: String) throws -> String { try _callFn(cx_toml_to_toml, input) }
    public static func tomlToMd  (_ input: String) throws -> String { try _callFn(cx_toml_to_md,   input) }

    // ── MD input ───────────────────────────────────────────────────────────────

    public static func mdToCx  (_ input: String) throws -> String { try _callFn(cx_md_to_cx,   input) }
    public static func mdToXml (_ input: String) throws -> String { try _callFn(cx_md_to_xml,  input) }
    public static func mdToAst (_ input: String) throws -> String { try _callFn(cx_md_to_ast,  input) }
    public static func mdToJson(_ input: String) throws -> String { try _callFn(cx_md_to_json, input) }
    public static func mdToYaml(_ input: String) throws -> String { try _callFn(cx_md_to_yaml, input) }
    public static func mdToToml(_ input: String) throws -> String { try _callFn(cx_md_to_toml, input) }
    public static func mdToMd  (_ input: String) throws -> String { try _callFn(cx_md_to_md,   input) }
}

// ── module-level shims (keep backward compat for any direct callers) ──────────

public func version() -> String { CXLib.version() }

public func toCx        (_ input: String) throws -> String { try CXLib.toCx(input)        }
public func toCxCompact (_ input: String) throws -> String { try CXLib.toCxCompact(input) }
public func astToCx     (_ input: String) throws -> String { try CXLib.astToCx(input)     }
public func toXml (_ input: String) throws -> String { try CXLib.toXml(input)  }
public func toAst (_ input: String) throws -> String { try CXLib.toAst(input)  }
public func toJson(_ input: String) throws -> String { try CXLib.toJson(input) }
public func toYaml(_ input: String) throws -> String { try CXLib.toYaml(input) }
public func toToml(_ input: String) throws -> String { try CXLib.toToml(input) }
public func toMd  (_ input: String) throws -> String { try CXLib.toMd(input)   }

public func xmlToCx  (_ input: String) throws -> String { try CXLib.xmlToCx(input)   }
public func xmlToXml (_ input: String) throws -> String { try CXLib.xmlToXml(input)  }
public func xmlToAst (_ input: String) throws -> String { try CXLib.xmlToAst(input)  }
public func xmlToJson(_ input: String) throws -> String { try CXLib.xmlToJson(input) }
public func xmlToYaml(_ input: String) throws -> String { try CXLib.xmlToYaml(input) }
public func xmlToToml(_ input: String) throws -> String { try CXLib.xmlToToml(input) }
public func xmlToMd  (_ input: String) throws -> String { try CXLib.xmlToMd(input)   }

public func jsonToCx  (_ input: String) throws -> String { try CXLib.jsonToCx(input)   }
public func jsonToXml (_ input: String) throws -> String { try CXLib.jsonToXml(input)  }
public func jsonToAst (_ input: String) throws -> String { try CXLib.jsonToAst(input)  }
public func jsonToJson(_ input: String) throws -> String { try CXLib.jsonToJson(input) }
public func jsonToYaml(_ input: String) throws -> String { try CXLib.jsonToYaml(input) }
public func jsonToToml(_ input: String) throws -> String { try CXLib.jsonToToml(input) }
public func jsonToMd  (_ input: String) throws -> String { try CXLib.jsonToMd(input)   }

public func yamlToCx  (_ input: String) throws -> String { try CXLib.yamlToCx(input)   }
public func yamlToXml (_ input: String) throws -> String { try CXLib.yamlToXml(input)  }
public func yamlToAst (_ input: String) throws -> String { try CXLib.yamlToAst(input)  }
public func yamlToJson(_ input: String) throws -> String { try CXLib.yamlToJson(input) }
public func yamlToYaml(_ input: String) throws -> String { try CXLib.yamlToYaml(input) }
public func yamlToToml(_ input: String) throws -> String { try CXLib.yamlToToml(input) }
public func yamlToMd  (_ input: String) throws -> String { try CXLib.yamlToMd(input)   }

public func tomlToCx  (_ input: String) throws -> String { try CXLib.tomlToCx(input)   }
public func tomlToXml (_ input: String) throws -> String { try CXLib.tomlToXml(input)  }
public func tomlToAst (_ input: String) throws -> String { try CXLib.tomlToAst(input)  }
public func tomlToJson(_ input: String) throws -> String { try CXLib.tomlToJson(input) }
public func tomlToYaml(_ input: String) throws -> String { try CXLib.tomlToYaml(input) }
public func tomlToToml(_ input: String) throws -> String { try CXLib.tomlToToml(input) }
public func tomlToMd  (_ input: String) throws -> String { try CXLib.tomlToMd(input)   }

public func mdToCx  (_ input: String) throws -> String { try CXLib.mdToCx(input)   }
public func mdToXml (_ input: String) throws -> String { try CXLib.mdToXml(input)  }
public func mdToAst (_ input: String) throws -> String { try CXLib.mdToAst(input)  }
public func mdToJson(_ input: String) throws -> String { try CXLib.mdToJson(input) }
public func mdToYaml(_ input: String) throws -> String { try CXLib.mdToYaml(input) }
public func mdToToml(_ input: String) throws -> String { try CXLib.mdToToml(input) }
public func mdToMd  (_ input: String) throws -> String { try CXLib.mdToMd(input)   }
