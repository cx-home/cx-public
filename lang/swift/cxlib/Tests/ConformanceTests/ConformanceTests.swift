import XCTest
import CXLib
import Foundation

/// CX Swift conformance test suite.
final class ConformanceTests: XCTestCase {

    // ── suite parser ─────────────────────────────────────────────────────────

    struct TestCase {
        let name: String
        var sections: [String: String] = [:]
    }

    static func conformanceDir() throws -> URL {
        // Walk up from multiple candidate starting points to find conformance/core.txt
        var candidates: [URL] = []

        // Current working directory (swift test runs from package root = lang/swift/cxlib/)
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath))

        // Source file location: Tests/ConformanceTests/ConformanceTests.swift
        // Go up 5 levels to reach repo root
        var src = URL(fileURLWithPath: #file)
        for _ in 0..<5 { src.deleteLastPathComponent() }
        candidates.append(src)

        for base in candidates {
            // Try direct subdir
            for suffix in ["conformance", "../conformance", "../../conformance"] {
                let candidate = base.appendingPathComponent(suffix).standardized
                let coreFile  = candidate.appendingPathComponent("core.txt")
                if FileManager.default.fileExists(atPath: coreFile.path) {
                    return candidate
                }
            }
            // Walk up the tree
            var dir: URL? = base
            while let d = dir {
                let candidate = d.appendingPathComponent("conformance")
                let coreFile  = candidate.appendingPathComponent("core.txt")
                if FileManager.default.fileExists(atPath: coreFile.path) {
                    return candidate
                }
                let parent = d.deletingLastPathComponent()
                dir = parent.path == d.path ? nil : parent
            }
        }
        throw XCTSkip("conformance/ not found; run 'swift test --package-path lang/swift/cxlib' from repo root")
    }

    static func parseSuite(_ path: String) throws -> [TestCase] {
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        let lines = contents.components(separatedBy: "\n")

        var tests: [TestCase] = []
        var cur: TestCase? = nil
        var section: String? = nil
        var buf: [String] = []

        func flush() {
            guard let c = cur, let s = section else { return }
            var lines_ = buf
            while !lines_.isEmpty && lines_.first!.trimmingCharacters(in: .whitespaces).isEmpty { lines_.removeFirst() }
            while !lines_.isEmpty && lines_.last!.trimmingCharacters(in: .whitespaces).isEmpty { lines_.removeLast() }
            var tc = c
            tc.sections[s] = lines_.joined(separator: "\n")
            cur = tc
        }

        for line in lines {
            let l = line.hasSuffix("\r") ? String(line.dropLast()) : line
            if l.hasPrefix("=== test:") {
                flush()
                if let c = cur { tests.append(c) }
                cur = TestCase(name: String(l.dropFirst(9)).trimmingCharacters(in: .whitespaces))
                section = nil; buf = []
            } else if l.hasPrefix("--- ") && cur != nil {
                flush()
                section = String(l.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                buf = []
            } else if section != nil && cur != nil {
                buf.append(l)
            }
        }
        flush()
        if let c = cur { tests.append(c) }
        return tests
    }

    // ── JSON equality ────────────────────────────────────────────────────────

    static func jsonEqual(_ a: Any?, _ b: Any?) -> Bool {
        // Both nil or NSNull
        let aNil = a == nil || a is NSNull
        let bNil = b == nil || b is NSNull
        if aNil && bNil { return true }
        if aNil || bNil { return false }
        let a = a!
        let b = b!
        if a is NSNull && b is NSNull { return true }
        if a is NSNull || b is NSNull { return false }
        if let ao = a as? [String: Any], let bo = b as? [String: Any] {
            guard ao.count == bo.count else { return false }
            for (k, av) in ao {
                guard let bv = bo[k] else { return false }
                if !jsonEqual(av, bv) { return false }
            }
            return true
        }
        if let aa = a as? [Any], let ba = b as? [Any] {
            guard aa.count == ba.count else { return false }
            return zip(aa, ba).allSatisfy { jsonEqual($0, $1) }
        }
        if let an = a as? NSNumber, let bn = b as? NSNumber { return an == bn }
        if let as_ = a as? String, let bs = b as? String { return as_ == bs }
        return false
    }

    static func parseJson(_ s: String) -> Any? {
        guard let data = s.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    // ── dispatch ─────────────────────────────────────────────────────────────

    static func dispatch(_ inFmt: String, _ outFmt: String, _ input: String) throws -> String {
        switch "\(inFmt):\(outFmt)" {
        case "cx:cx":     return try toCx(input)
        case "cx:xml":    return try toXml(input)
        case "cx:ast":    return try toAst(input)
        case "cx:json":   return try toJson(input)
        case "cx:yaml":   return try toYaml(input)
        case "cx:toml":   return try toToml(input)
        case "cx:md":     return try toMd(input)
        case "xml:cx":    return try xmlToCx(input)
        case "xml:xml":   return try xmlToXml(input)
        case "xml:ast":   return try xmlToAst(input)
        case "xml:json":  return try xmlToJson(input)
        case "xml:yaml":  return try xmlToYaml(input)
        case "xml:toml":  return try xmlToToml(input)
        case "xml:md":    return try xmlToMd(input)
        case "json:cx":   return try jsonToCx(input)
        case "json:xml":  return try jsonToXml(input)
        case "json:ast":  return try jsonToAst(input)
        case "json:json": return try jsonToJson(input)
        case "json:yaml": return try jsonToYaml(input)
        case "json:toml": return try jsonToToml(input)
        case "json:md":   return try jsonToMd(input)
        case "yaml:cx":   return try yamlToCx(input)
        case "yaml:xml":  return try yamlToXml(input)
        case "yaml:ast":  return try yamlToAst(input)
        case "yaml:json": return try yamlToJson(input)
        case "yaml:yaml": return try yamlToYaml(input)
        case "yaml:toml": return try yamlToToml(input)
        case "yaml:md":   return try yamlToMd(input)
        case "toml:cx":   return try tomlToCx(input)
        case "toml:xml":  return try tomlToXml(input)
        case "toml:ast":  return try tomlToAst(input)
        case "toml:json": return try tomlToJson(input)
        case "toml:yaml": return try tomlToYaml(input)
        case "toml:toml": return try tomlToToml(input)
        case "toml:md":   return try tomlToMd(input)
        case "md:cx":     return try mdToCx(input)
        case "md:xml":    return try mdToXml(input)
        case "md:ast":    return try mdToAst(input)
        case "md:json":   return try mdToJson(input)
        case "md:yaml":   return try mdToYaml(input)
        case "md:toml":   return try mdToToml(input)
        case "md:md":     return try mdToMd(input)
        default: throw CXError.parse("no dispatch for \(inFmt):\(outFmt)")
        }
    }

    // ── test runner ──────────────────────────────────────────────────────────

    static func runSuite(_ path: String) -> (Int, Int) {
        let tests: [TestCase]
        do { tests = try parseSuite(path) }
        catch { print("Error parsing \(path): \(error)"); return (0, 1) }

        var passed = 0, failed = 0
        for t in tests {
            var failures: [String] = []
            let s = t.sections

            var src: String? = nil
            var inFmt: String? = nil
            for (k, fmt) in [("in_cx","cx"),("in_xml","xml"),("in_json","json"),
                             ("in_yaml","yaml"),("in_toml","toml"),("in_md","md")] {
                if let v = s[k] { src = v; inFmt = fmt; break }
            }
            guard let src, let inFmt else { passed += 1; continue }

            func call(_ outFmt: String) -> (String?, String?) {
                do    { return (try dispatch(inFmt, outFmt, src), nil) }
                catch { return (nil, "\(error)") }
            }

            if let exp = s["out_ast"] {
                let (out, err) = call("ast")
                if let err { failures.append("out_ast parse error: \(err)") }
                else if !jsonEqual(parseJson(exp), parseJson(out!)) {
                    failures.append("out_ast mismatch\n  expected: \(exp)\n  got:      \(out!)")
                }
            }
            if let exp = s["out_xml"] {
                let (out, err) = call("xml")
                if let err { failures.append("out_xml parse error: \(err)") }
                else if exp.trimmingCharacters(in: .whitespacesAndNewlines) !=
                        out!.trimmingCharacters(in: .whitespacesAndNewlines) {
                    failures.append("out_xml mismatch\n  expected:\n\(exp)\n  got:\n\(out!)")
                }
            }
            if let exp = s["out_cx"] {
                let (out, err) = call("cx")
                if let err { failures.append("out_cx parse error: \(err)") }
                else if exp.trimmingCharacters(in: .whitespacesAndNewlines) !=
                        out!.trimmingCharacters(in: .whitespacesAndNewlines) {
                    failures.append("out_cx mismatch\n  expected:\n\(exp)\n  got:\n\(out!)")
                }
            }
            if let exp = s["out_json"] {
                let (out, err) = call("json")
                if let err { failures.append("out_json parse error: \(err)") }
                else if !jsonEqual(parseJson(exp), parseJson(out!)) {
                    failures.append("out_json mismatch\n  expected: \(exp)\n  got:      \(out!)")
                }
            }
            if let exp = s["out_md"] {
                let (out, err) = call("md")
                if let err { failures.append("out_md parse error: \(err)") }
                else if exp.trimmingCharacters(in: .whitespacesAndNewlines) !=
                        out!.trimmingCharacters(in: .whitespacesAndNewlines) {
                    failures.append("out_md mismatch\n  expected:\n\(exp)\n  got:\n\(out!)")
                }
            }

            if failures.isEmpty { passed += 1 }
            else {
                failed += 1
                print("FAIL  \(t.name)")
                for f in failures {
                    for line in f.split(separator: "\n", omittingEmptySubsequences: false) {
                        print("      \(line)")
                    }
                }
            }
        }
        print("\(path): \(passed) passed, \(failed) failed")
        return (passed, failed)
    }

    // ── JUnit-style test methods ──────────────────────────────────────────────

    func testCore() throws {
        let dir = try ConformanceTests.conformanceDir()
        let (_, f) = ConformanceTests.runSuite(dir.appendingPathComponent("core.txt").path)
        XCTAssertEqual(f, 0, "core.txt had failures")
    }
    func testExtended() throws {
        let dir = try ConformanceTests.conformanceDir()
        let (_, f) = ConformanceTests.runSuite(dir.appendingPathComponent("extended.txt").path)
        XCTAssertEqual(f, 0, "extended.txt had failures")
    }
    func testXml() throws {
        let dir = try ConformanceTests.conformanceDir()
        let (_, f) = ConformanceTests.runSuite(dir.appendingPathComponent("xml.txt").path)
        XCTAssertEqual(f, 0, "xml.txt had failures")
    }
    func testMd() throws {
        let dir = try ConformanceTests.conformanceDir()
        let (_, f) = ConformanceTests.runSuite(dir.appendingPathComponent("md.txt").path)
        XCTAssertEqual(f, 0, "md.txt had failures")
    }
}
