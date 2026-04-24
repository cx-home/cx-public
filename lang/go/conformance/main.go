// CX Go conformance runner.
//
// Run: cd lang/go/conformance && go run .
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	cxlib "github.com/ardec/cx/lang/go"
)

// ── suite parser ──────────────────────────────────────────────────────────────

type test struct {
	name     string
	sections map[string]string
}

func parseSuite(path string) ([]test, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var tests []test
	var cur *test
	var section string
	var buf []string

	flush := func() {
		if cur != nil && section != "" {
			lines := buf
			for len(lines) > 0 && strings.TrimSpace(lines[0]) == "" {
				lines = lines[1:]
			}
			for len(lines) > 0 && strings.TrimSpace(lines[len(lines)-1]) == "" {
				lines = lines[:len(lines)-1]
			}
			cur.sections[section] = strings.Join(lines, "\n")
		}
		buf = buf[:0]
	}

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "=== test:") {
			flush()
			if cur != nil {
				tests = append(tests, *cur)
			}
			cur = &test{name: strings.TrimSpace(line[9:]), sections: make(map[string]string)}
			section = ""
		} else if strings.HasPrefix(line, "--- ") && cur != nil {
			flush()
			section = strings.TrimSpace(line[4:])
		} else if section != "" && cur != nil {
			buf = append(buf, line)
		}
	}
	flush()
	if cur != nil {
		tests = append(tests, *cur)
	}
	return tests, scanner.Err()
}

// ── dispatch ──────────────────────────────────────────────────────────────────

type convFn func(string) (string, error)

func dispatch(fmt, out string) convFn {
	type key struct{ in, out string }
	table := map[key]convFn{
		{"cx", "cx"}:     cxlib.ToCx,
		{"cx", "xml"}:    cxlib.ToXml,
		{"cx", "ast"}:    cxlib.ToAst,
		{"cx", "json"}:   cxlib.ToJson,
		{"cx", "yaml"}:   cxlib.ToYaml,
		{"cx", "toml"}:   cxlib.ToToml,
		{"cx", "md"}:     cxlib.ToMd,
		{"xml", "cx"}:    cxlib.XmlToCx,
		{"xml", "xml"}:   cxlib.XmlToXml,
		{"xml", "ast"}:   cxlib.XmlToAst,
		{"xml", "json"}:  cxlib.XmlToJson,
		{"xml", "yaml"}:  cxlib.XmlToYaml,
		{"xml", "toml"}:  cxlib.XmlToToml,
		{"xml", "md"}:    cxlib.XmlToMd,
		{"json", "cx"}:   cxlib.JsonToCx,
		{"json", "xml"}:  cxlib.JsonToXml,
		{"json", "ast"}:  cxlib.JsonToAst,
		{"json", "json"}: cxlib.JsonToJson,
		{"json", "yaml"}: cxlib.JsonToYaml,
		{"json", "toml"}: cxlib.JsonToToml,
		{"json", "md"}:   cxlib.JsonToMd,
		{"yaml", "cx"}:   cxlib.YamlToCx,
		{"yaml", "xml"}:  cxlib.YamlToXml,
		{"yaml", "ast"}:  cxlib.YamlToAst,
		{"yaml", "json"}: cxlib.YamlToJson,
		{"yaml", "yaml"}: cxlib.YamlToYaml,
		{"yaml", "toml"}: cxlib.YamlToToml,
		{"yaml", "md"}:   cxlib.YamlToMd,
		{"toml", "cx"}:   cxlib.TomlToCx,
		{"toml", "xml"}:  cxlib.TomlToXml,
		{"toml", "ast"}:  cxlib.TomlToAst,
		{"toml", "json"}: cxlib.TomlToJson,
		{"toml", "yaml"}: cxlib.TomlToYaml,
		{"toml", "toml"}: cxlib.TomlToToml,
		{"toml", "md"}:   cxlib.TomlToMd,
		{"md", "cx"}:     cxlib.MdToCx,
		{"md", "xml"}:    cxlib.MdToXml,
		{"md", "ast"}:    cxlib.MdToAst,
		{"md", "json"}:   cxlib.MdToJson,
		{"md", "yaml"}:   cxlib.MdToYaml,
		{"md", "toml"}:   cxlib.MdToToml,
		{"md", "md"}:     cxlib.MdToMd,
	}
	return table[key{fmt, out}]
}

// ── test runner ───────────────────────────────────────────────────────────────

func runTest(t test) []string {
	var failures []string
	s := t.sections

	var src, inFmt string
	for _, pair := range [][2]string{
		{"in_cx", "cx"}, {"in_xml", "xml"}, {"in_json", "json"},
		{"in_yaml", "yaml"}, {"in_toml", "toml"}, {"in_md", "md"},
	} {
		if v, ok := s[pair[0]]; ok {
			src, inFmt = v, pair[1]
			break
		}
	}
	if inFmt == "" {
		return failures
	}

	call := func(outFmt string) (string, error) {
		fn := dispatch(inFmt, outFmt)
		if fn == nil {
			return "", fmt.Errorf("no dispatch for %s->%s", inFmt, outFmt)
		}
		return fn(src)
	}

	// out_ast
	if exp, ok := s["out_ast"]; ok {
		out, err := call("ast")
		if err != nil {
			failures = append(failures, fmt.Sprintf("out_ast parse error: %v", err))
		} else {
			var expected, got interface{}
			if e := json.Unmarshal([]byte(exp), &expected); e != nil {
				failures = append(failures, fmt.Sprintf("out_ast: bad expected json: %v", e))
			} else if e := json.Unmarshal([]byte(out), &got); e != nil {
				failures = append(failures, fmt.Sprintf("out_ast: bad got json: %v", e))
			} else {
				eb, _ := json.Marshal(expected)
				gb, _ := json.Marshal(got)
				if string(eb) != string(gb) {
					failures = append(failures, fmt.Sprintf("out_ast mismatch\n  expected: %s\n  got:      %s", eb, gb))
				}
			}
		}
	}

	// out_xml
	if exp, ok := s["out_xml"]; ok {
		out, err := call("xml")
		if err != nil {
			failures = append(failures, fmt.Sprintf("out_xml parse error: %v", err))
		} else if strings.TrimSpace(exp) != strings.TrimSpace(out) {
			failures = append(failures, fmt.Sprintf("out_xml mismatch\n  expected:\n%s\n  got:\n%s", exp, out))
		}
	}

	// out_cx
	if exp, ok := s["out_cx"]; ok {
		out, err := call("cx")
		if err != nil {
			failures = append(failures, fmt.Sprintf("out_cx parse error: %v", err))
		} else if strings.TrimSpace(exp) != strings.TrimSpace(out) {
			failures = append(failures, fmt.Sprintf("out_cx mismatch\n  expected:\n%s\n  got:\n%s", exp, out))
		}
	}

	// out_json
	if exp, ok := s["out_json"]; ok {
		out, err := call("json")
		if err != nil {
			failures = append(failures, fmt.Sprintf("out_json parse error: %v", err))
		} else {
			var expected, got interface{}
			if e := json.Unmarshal([]byte(exp), &expected); e != nil {
				failures = append(failures, fmt.Sprintf("out_json: bad expected json: %v", e))
			} else if e := json.Unmarshal([]byte(out), &got); e != nil {
				failures = append(failures, fmt.Sprintf("out_json: bad got json: %v", e))
			} else {
				eb, _ := json.Marshal(expected)
				gb, _ := json.Marshal(got)
				if string(eb) != string(gb) {
					failures = append(failures, fmt.Sprintf("out_json mismatch\n  expected: %s\n  got:      %s", eb, gb))
				}
			}
		}
	}

	// out_md
	if exp, ok := s["out_md"]; ok {
		out, err := call("md")
		if err != nil {
			failures = append(failures, fmt.Sprintf("out_md parse error: %v", err))
		} else if strings.TrimSpace(exp) != strings.TrimSpace(out) {
			failures = append(failures, fmt.Sprintf("out_md mismatch\n  expected:\n%s\n  got:\n%s", exp, out))
		}
	}

	return failures
}

// ── suite runner ──────────────────────────────────────────────────────────────

func runSuite(path string) int {
	tests, err := parseSuite(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error reading %s: %v\n", path, err)
		return 1
	}
	passed, failed := 0, 0
	for _, t := range tests {
		failures := runTest(t)
		if len(failures) == 0 {
			passed++
		} else {
			failed++
			fmt.Printf("FAIL  %s\n", t.name)
			for _, f := range failures {
				for _, line := range strings.Split(f, "\n") {
					fmt.Printf("      %s\n", line)
				}
			}
		}
	}
	fmt.Printf("%s: %d passed, %d failed\n", path, passed, failed)
	return failed
}

// ── entry point ───────────────────────────────────────────────────────────────

func main() {
	_, file, _, _ := runtime.Caller(0)
	// file is lang/go/conformance/main.go; conformance/ is ../../../conformance/
	base := filepath.Join(filepath.Dir(file), "..", "..", "..", "conformance")

	suites := os.Args[1:]
	if len(suites) == 0 {
		suites = []string{
			filepath.Join(base, "core.txt"),
			filepath.Join(base, "extended.txt"),
			filepath.Join(base, "xml.txt"),
			filepath.Join(base, "md.txt"),
		}
	}

	totalFailed := 0
	for _, s := range suites {
		totalFailed += runSuite(s)
	}
	if totalFailed > 0 {
		os.Exit(1)
	}
}
