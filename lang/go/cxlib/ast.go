// Package cxlib — CX Document API: types, parse, query, mutation, CX emitter.
package cxlib

import (
	"encoding/json"
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

// ── Node interface ────────────────────────────────────────────────────────────

// Node is the common interface for all AST node types.
type Node interface{ cxNode() }

// ── Attr ─────────────────────────────────────────────────────────────────────

// Attr represents an element attribute (name=value pair).
type Attr struct {
	Name     string
	Value    any    // string | int64 | float64 | bool | nil
	DataType string // "" means string (omitted in JSON)
}

// ── Concrete node types ───────────────────────────────────────────────────────

// TextNode is an inline text node.
type TextNode struct{ Value string }

func (n *TextNode) cxNode() {}

// ScalarNode is a typed scalar value (int, float, bool, null, date, etc.).
type ScalarNode struct {
	DataType string
	Value    any // int64 | float64 | bool | nil | string
}

func (n *ScalarNode) cxNode() {}

// CommentNode is a CX comment `[- ... ]`.
type CommentNode struct{ Value string }

func (n *CommentNode) cxNode() {}

// RawTextNode is a raw text block `[# ... #]`.
type RawTextNode struct{ Value string }

func (n *RawTextNode) cxNode() {}

// EntityRefNode is `&name;`.
type EntityRefNode struct{ Name string }

func (n *EntityRefNode) cxNode() {}

// AliasNode is `[*name]`.
type AliasNode struct{ Name string }

func (n *AliasNode) cxNode() {}

// PINode is a processing instruction `[?target data]`.
type PINode struct {
	Target string
	Data   string
}

func (n *PINode) cxNode() {}

// XMLDeclNode is `[?xml version=... ]`.
type XMLDeclNode struct {
	Version    string
	Encoding   string
	Standalone string
}

func (n *XMLDeclNode) cxNode() {}

// CXDirectiveNode is `[?cx ...]`.
type CXDirectiveNode struct{ Attrs []Attr }

func (n *CXDirectiveNode) cxNode() {}

// DoctypeDeclNode is `[!DOCTYPE ...]`.
type DoctypeDeclNode struct {
	Name       string
	ExternalID map[string]any
	IntSubset  []any
}

func (n *DoctypeDeclNode) cxNode() {}

// BlockContentNode is `[| ... |]`.
type BlockContentNode struct{ Items []Node }

func (n *BlockContentNode) cxNode() {}

// ── Element ───────────────────────────────────────────────────────────────────

// Element is the main structural node in a CX document.
type Element struct {
	Name     string
	Anchor   string
	Merge    string
	DataType string // type annotation e.g. "int[]"
	Attrs    []Attr
	Items    []Node
}

func (e *Element) cxNode() {}

// Attr returns the value of the named attribute, or nil if not found.
func (e *Element) Attr(name string) any {
	for _, a := range e.Attrs {
		if a.Name == name {
			return a.Value
		}
	}
	return nil
}

// Text returns the concatenated text and scalar content of the element.
func (e *Element) Text() string {
	var parts []string
	for _, item := range e.Items {
		switch n := item.(type) {
		case *TextNode:
			parts = append(parts, n.Value)
		case *ScalarNode:
			if n.Value == nil {
				parts = append(parts, "null")
			} else {
				parts = append(parts, fmt.Sprintf("%v", n.Value))
			}
		}
	}
	return strings.Join(parts, " ")
}

// Scalar returns the value of the first ScalarNode child, or nil.
func (e *Element) Scalar() any {
	for _, item := range e.Items {
		if s, ok := item.(*ScalarNode); ok {
			return s.Value
		}
	}
	return nil
}

// Children returns all direct child Element nodes.
func (e *Element) Children() []*Element {
	var result []*Element
	for _, item := range e.Items {
		if el, ok := item.(*Element); ok {
			result = append(result, el)
		}
	}
	return result
}

// Get returns the first direct child Element with the given name, or nil.
func (e *Element) Get(name string) *Element {
	for _, item := range e.Items {
		if el, ok := item.(*Element); ok && el.Name == name {
			return el
		}
	}
	return nil
}

// GetAll returns all direct child Elements with the given name.
func (e *Element) GetAll(name string) []*Element {
	var result []*Element
	for _, item := range e.Items {
		if el, ok := item.(*Element); ok && el.Name == name {
			result = append(result, el)
		}
	}
	return result
}

// FindAll returns all descendant Elements with the given name (depth-first).
func (e *Element) FindAll(name string) []*Element {
	var result []*Element
	for _, item := range e.Items {
		if el, ok := item.(*Element); ok {
			if el.Name == name {
				result = append(result, el)
			}
			result = append(result, el.FindAll(name)...)
		}
	}
	return result
}

// FindFirst returns the first descendant Element with the given name (depth-first).
func (e *Element) FindFirst(name string) *Element {
	for _, item := range e.Items {
		if el, ok := item.(*Element); ok {
			if el.Name == name {
				return el
			}
			if found := el.FindFirst(name); found != nil {
				return found
			}
		}
	}
	return nil
}

// At navigates by slash-separated path (e.g. "server/host").
func (e *Element) At(path string) *Element {
	parts := splitPath(path)
	cur := e
	for _, part := range parts {
		if cur == nil {
			return nil
		}
		cur = cur.Get(part)
	}
	return cur
}

// SetAttr upserts an attribute value.
func (e *Element) SetAttr(name string, value any, dataType string) {
	for i := range e.Attrs {
		if e.Attrs[i].Name == name {
			e.Attrs[i].Value = value
			e.Attrs[i].DataType = dataType
			return
		}
	}
	e.Attrs = append(e.Attrs, Attr{Name: name, Value: value, DataType: dataType})
}

// RemoveAttr removes an attribute by name.
func (e *Element) RemoveAttr(name string) {
	filtered := e.Attrs[:0]
	for _, a := range e.Attrs {
		if a.Name != name {
			filtered = append(filtered, a)
		}
	}
	e.Attrs = filtered
}

// Append adds a child node to the end.
func (e *Element) Append(n Node) {
	e.Items = append(e.Items, n)
}

// Prepend adds a child node to the front.
func (e *Element) Prepend(n Node) {
	e.Items = append([]Node{n}, e.Items...)
}

// Insert inserts a child node at the given index.
func (e *Element) Insert(index int, n Node) {
	e.Items = append(e.Items, nil)
	copy(e.Items[index+1:], e.Items[index:])
	e.Items[index] = n
}

// Remove removes a child node by pointer identity.
func (e *Element) Remove(n Node) {
	filtered := e.Items[:0]
	for _, item := range e.Items {
		if item != n {
			filtered = append(filtered, item)
		}
	}
	e.Items = filtered
}

// RemoveChild removes all direct child Elements with the given name.
func (e *Element) RemoveChild(name string) {
	filtered := e.Items[:0]
	for _, item := range e.Items {
		if el, ok := item.(*Element); ok && el.Name == name {
			continue
		}
		filtered = append(filtered, item)
	}
	e.Items = filtered
}

// RemoveAt removes the child node at the given index (no-op if out of bounds).
func (e *Element) RemoveAt(index int) {
	if index < 0 || index >= len(e.Items) {
		return
	}
	e.Items = append(e.Items[:index], e.Items[index+1:]...)
}

// Select returns the first Element matching the CXPath expression.
func (e *Element) Select(expr string) (*Element, error) {
	results, err := e.SelectAll(expr)
	if err != nil || len(results) == 0 {
		return nil, err
	}
	return results[0], nil
}

// SelectAll returns all Elements matching the CXPath expression relative to this element.
func (e *Element) SelectAll(expr string) ([]*Element, error) {
	cx, err := cxpathParse(expr)
	if err != nil {
		return nil, err
	}
	var result []*Element
	collectStep(e, cx, 0, &result)
	return result, nil
}

// ── Document ──────────────────────────────────────────────────────────────────

// Document is the top-level CX document.
type Document struct {
	Elements []Node
	Prolog   []Node
	Doctype  *DoctypeDeclNode
}

// Root returns the first top-level Element.
func (d *Document) Root() *Element {
	for _, e := range d.Elements {
		if el, ok := e.(*Element); ok {
			return el
		}
	}
	return nil
}

// Get returns the first top-level Element with the given name.
func (d *Document) Get(name string) *Element {
	for _, e := range d.Elements {
		if el, ok := e.(*Element); ok && el.Name == name {
			return el
		}
	}
	return nil
}

// At navigates by slash-separated path from root.
func (d *Document) At(path string) *Element {
	parts := splitPath(path)
	if len(parts) == 0 {
		return d.Root()
	}
	cur := d.Get(parts[0])
	if cur == nil || len(parts) == 1 {
		return cur
	}
	return cur.At(strings.Join(parts[1:], "/"))
}

// FindAll returns all descendant Elements with the given name (depth-first).
func (d *Document) FindAll(name string) []*Element {
	var result []*Element
	for _, e := range d.Elements {
		if el, ok := e.(*Element); ok {
			if el.Name == name {
				result = append(result, el)
			}
			result = append(result, el.FindAll(name)...)
		}
	}
	return result
}

// FindFirst returns the first descendant Element with the given name.
func (d *Document) FindFirst(name string) *Element {
	for _, e := range d.Elements {
		if el, ok := e.(*Element); ok {
			if el.Name == name {
				return el
			}
			if found := el.FindFirst(name); found != nil {
				return found
			}
		}
	}
	return nil
}

// Select returns the first Element matching the CXPath expression.
func (d *Document) Select(expr string) (*Element, error) {
	results, err := d.SelectAll(expr)
	if err != nil || len(results) == 0 {
		return nil, err
	}
	return results[0], nil
}

// SelectAll returns all Elements matching the CXPath expression.
func (d *Document) SelectAll(expr string) ([]*Element, error) {
	cx, err := cxpathParse(expr)
	if err != nil {
		return nil, err
	}
	// Virtual root for sibling context at top level
	vroot := &Element{Name: "#document", Items: append([]Node{}, d.Elements...)}
	var result []*Element
	collectStep(vroot, cx, 0, &result)
	return result, nil
}

// Transform returns a new Document with the element at path replaced by f(element).
func (d *Document) Transform(path string, f func(*Element) *Element) *Document {
	parts := splitPath(path)
	if len(parts) == 0 {
		return d
	}
	for i, node := range d.Elements {
		if el, ok := node.(*Element); ok && el.Name == parts[0] {
			if len(parts) == 1 {
				return docReplaceAt(d, i, f(elemDetached(el)))
			}
			updated := pathCopyElement(el, parts[1:], f)
			if updated != nil {
				return docReplaceAt(d, i, updated)
			}
			return d
		}
	}
	return d
}

// TransformAll returns a new Document with all elements matching expr replaced by f(element).
func (d *Document) TransformAll(expr string, f func(*Element) *Element) (*Document, error) {
	cx, err := cxpathParse(expr)
	if err != nil {
		return nil, err
	}
	newElements := make([]Node, len(d.Elements))
	for i, node := range d.Elements {
		newElements[i] = rebuildNode(node, cx, f)
	}
	return &Document{Elements: newElements, Prolog: d.Prolog, Doctype: d.Doctype}, nil
}

// Append adds a top-level node to the end.
func (d *Document) Append(n Node) {
	d.Elements = append(d.Elements, n)
}

// Prepend adds a top-level node to the front.
func (d *Document) Prepend(n Node) {
	d.Elements = append([]Node{n}, d.Elements...)
}

// ToCx emits the document as a CX string using the native emitter.
func (d *Document) ToCx() string {
	return emitDoc(d)
}

// ToXml converts the document to XML via the C library.
func (d *Document) ToXml() (string, error) {
	return ToXml(d.ToCx())
}

// ToJson converts the document to JSON via the C library.
func (d *Document) ToJson() (string, error) {
	return ToJson(d.ToCx())
}

// ToYaml converts the document to YAML via the C library.
func (d *Document) ToYaml() (string, error) {
	return ToYaml(d.ToCx())
}

// ToToml converts the document to TOML via the C library.
func (d *Document) ToToml() (string, error) {
	return ToToml(d.ToCx())
}

// ToMd converts the document to Markdown via the C library.
func (d *Document) ToMd() (string, error) {
	return ToMd(d.ToCx())
}

// ── JSON deserialization ──────────────────────────────────────────────────────

func attrFromMap(m map[string]json.RawMessage) (Attr, error) {
	var name string
	if err := json.Unmarshal(m["name"], &name); err != nil {
		return Attr{}, err
	}
	var dataType string
	if raw, ok := m["dataType"]; ok {
		_ = json.Unmarshal(raw, &dataType)
	}
	val, err := unmarshalValue(m["value"])
	if err != nil {
		return Attr{}, err
	}
	return Attr{Name: name, Value: val, DataType: dataType}, nil
}

// unmarshalValue decodes a JSON RawMessage into a Go native value.
// Numbers are decoded as int64 if they are integer-valued, else float64.
func unmarshalValue(raw json.RawMessage) (any, error) {
	if raw == nil {
		return nil, nil
	}
	var generic any
	if err := json.Unmarshal(raw, &generic); err != nil {
		return nil, err
	}
	if generic == nil {
		return nil, nil
	}
	// json.Unmarshal decodes numbers as float64 by default.
	// Promote to int64 if the number is integral.
	if f, ok := generic.(float64); ok {
		if f == float64(int64(f)) {
			// check if the original token has a decimal point or exponent
			s := strings.TrimSpace(string(raw))
			if !strings.ContainsAny(s, ".eE") {
				return int64(f), nil
			}
		}
		return f, nil
	}
	return generic, nil
}

func nodeFromJSON(raw json.RawMessage) (Node, error) {
	var m map[string]json.RawMessage
	if err := json.Unmarshal(raw, &m); err != nil {
		return &TextNode{Value: string(raw)}, nil
	}
	var typeName string
	if err := json.Unmarshal(m["type"], &typeName); err != nil {
		return &TextNode{Value: string(raw)}, nil
	}

	switch typeName {
	case "Element":
		return elementFromMap(m)

	case "Text":
		var v string
		json.Unmarshal(m["value"], &v)
		return &TextNode{Value: v}, nil

	case "Scalar":
		var dt string
		json.Unmarshal(m["dataType"], &dt)
		val, _ := unmarshalValue(m["value"])
		return &ScalarNode{DataType: dt, Value: val}, nil

	case "Comment":
		var v string
		json.Unmarshal(m["value"], &v)
		return &CommentNode{Value: v}, nil

	case "RawText":
		var v string
		json.Unmarshal(m["value"], &v)
		return &RawTextNode{Value: v}, nil

	case "EntityRef":
		var name string
		json.Unmarshal(m["name"], &name)
		return &EntityRefNode{Name: name}, nil

	case "Alias":
		var name string
		json.Unmarshal(m["name"], &name)
		return &AliasNode{Name: name}, nil

	case "PI":
		var target, data string
		json.Unmarshal(m["target"], &target)
		if d, ok := m["data"]; ok {
			json.Unmarshal(d, &data)
		}
		return &PINode{Target: target, Data: data}, nil

	case "XMLDecl":
		var version, encoding, standalone string
		version = "1.0"
		if v, ok := m["version"]; ok {
			json.Unmarshal(v, &version)
		}
		if v, ok := m["encoding"]; ok {
			json.Unmarshal(v, &encoding)
		}
		if v, ok := m["standalone"]; ok {
			json.Unmarshal(v, &standalone)
		}
		return &XMLDeclNode{Version: version, Encoding: encoding, Standalone: standalone}, nil

	case "CXDirective":
		node := &CXDirectiveNode{}
		if rawAttrs, ok := m["attrs"]; ok {
			var arrRaw []json.RawMessage
			json.Unmarshal(rawAttrs, &arrRaw)
			for _, ar := range arrRaw {
				var am map[string]json.RawMessage
				json.Unmarshal(ar, &am)
				a, _ := attrFromMap(am)
				node.Attrs = append(node.Attrs, a)
			}
		}
		return node, nil

	case "DoctypeDecl":
		var name string
		json.Unmarshal(m["name"], &name)
		node := &DoctypeDeclNode{Name: name}
		if v, ok := m["externalID"]; ok {
			var extID map[string]any
			json.Unmarshal(v, &extID)
			node.ExternalID = extID
		}
		if v, ok := m["intSubset"]; ok {
			var subset []any
			json.Unmarshal(v, &subset)
			node.IntSubset = subset
		}
		return node, nil

	case "BlockContent":
		node := &BlockContentNode{}
		if rawItems, ok := m["items"]; ok {
			var arrRaw []json.RawMessage
			json.Unmarshal(rawItems, &arrRaw)
			for _, ir := range arrRaw {
				child, _ := nodeFromJSON(ir)
				node.Items = append(node.Items, child)
			}
		}
		return node, nil

	default:
		return &TextNode{Value: string(raw)}, nil
	}
}

func elementFromMap(m map[string]json.RawMessage) (*Element, error) {
	el := &Element{}
	json.Unmarshal(m["name"], &el.Name)
	if v, ok := m["anchor"]; ok {
		json.Unmarshal(v, &el.Anchor)
	}
	if v, ok := m["merge"]; ok {
		json.Unmarshal(v, &el.Merge)
	}
	if v, ok := m["dataType"]; ok {
		json.Unmarshal(v, &el.DataType)
	}
	if rawAttrs, ok := m["attrs"]; ok {
		var arrRaw []json.RawMessage
		json.Unmarshal(rawAttrs, &arrRaw)
		for _, ar := range arrRaw {
			var am map[string]json.RawMessage
			json.Unmarshal(ar, &am)
			a, err := attrFromMap(am)
			if err == nil {
				el.Attrs = append(el.Attrs, a)
			}
		}
	}
	if rawItems, ok := m["items"]; ok {
		var arrRaw []json.RawMessage
		json.Unmarshal(rawItems, &arrRaw)
		for _, ir := range arrRaw {
			child, err := nodeFromJSON(ir)
			if err == nil {
				el.Items = append(el.Items, child)
			}
		}
	}
	return el, nil
}

func docFromMap(m map[string]json.RawMessage) (*Document, error) {
	doc := &Document{}
	if rawProlog, ok := m["prolog"]; ok {
		var arrRaw []json.RawMessage
		json.Unmarshal(rawProlog, &arrRaw)
		for _, ir := range arrRaw {
			n, _ := nodeFromJSON(ir)
			doc.Prolog = append(doc.Prolog, n)
		}
	}
	if rawDoctype, ok := m["doctype"]; ok {
		var dm map[string]json.RawMessage
		if json.Unmarshal(rawDoctype, &dm) == nil {
			var name string
			json.Unmarshal(dm["name"], &name)
			dt := &DoctypeDeclNode{Name: name}
			if v, ok := dm["externalID"]; ok {
				var extID map[string]any
				json.Unmarshal(v, &extID)
				dt.ExternalID = extID
			}
			doc.Doctype = dt
		}
	}
	if rawElems, ok := m["elements"]; ok {
		var arrRaw []json.RawMessage
		json.Unmarshal(rawElems, &arrRaw)
		for _, ir := range arrRaw {
			n, _ := nodeFromJSON(ir)
			doc.Elements = append(doc.Elements, n)
		}
	}
	return doc, nil
}

// ── Public parse / loads / dumps ──────────────────────────────────────────────

// Parse parses a CX string into a Document using the binary wire protocol.
func Parse(cxStr string) (*Document, error) {
	data, err := ToAstBin(cxStr)
	if err != nil {
		return nil, err
	}
	return decodeAST(data)
}

// ParseXml parses an XML string into a Document.
func ParseXml(xmlStr string) (*Document, error) {
	astJSON, err := XmlToAst(xmlStr)
	if err != nil {
		return nil, err
	}
	var m map[string]json.RawMessage
	if err := json.Unmarshal([]byte(astJSON), &m); err != nil {
		return nil, fmt.Errorf("ast json unmarshal: %w", err)
	}
	return docFromMap(m)
}

// ParseJson parses a JSON string into a Document.
func ParseJson(jsonStr string) (*Document, error) {
	astJSON, err := JsonToAst(jsonStr)
	if err != nil {
		return nil, err
	}
	var m map[string]json.RawMessage
	if err := json.Unmarshal([]byte(astJSON), &m); err != nil {
		return nil, fmt.Errorf("ast json unmarshal: %w", err)
	}
	return docFromMap(m)
}

// ParseYaml parses a YAML string into a Document.
func ParseYaml(yamlStr string) (*Document, error) {
	astJSON, err := YamlToAst(yamlStr)
	if err != nil {
		return nil, err
	}
	var m map[string]json.RawMessage
	if err := json.Unmarshal([]byte(astJSON), &m); err != nil {
		return nil, fmt.Errorf("ast json unmarshal: %w", err)
	}
	return docFromMap(m)
}

// ParseToml parses a TOML string into a Document.
func ParseToml(tomlStr string) (*Document, error) {
	astJSON, err := TomlToAst(tomlStr)
	if err != nil {
		return nil, err
	}
	var m map[string]json.RawMessage
	if err := json.Unmarshal([]byte(astJSON), &m); err != nil {
		return nil, fmt.Errorf("ast json unmarshal: %w", err)
	}
	return docFromMap(m)
}

// ParseMd parses a Markdown string into a Document.
func ParseMd(mdStr string) (*Document, error) {
	astJSON, err := MdToAst(mdStr)
	if err != nil {
		return nil, err
	}
	var m map[string]json.RawMessage
	if err := json.Unmarshal([]byte(astJSON), &m); err != nil {
		return nil, fmt.Errorf("ast json unmarshal: %w", err)
	}
	return docFromMap(m)
}

// LoadsXml deserializes an XML string into native Go types (map/slice/scalar).
func LoadsXml(xmlStr string) (any, error) {
	jsonStr, err := XmlToJson(xmlStr)
	if err != nil {
		return nil, err
	}
	var result any
	if err := json.Unmarshal([]byte(jsonStr), &result); err != nil {
		return nil, fmt.Errorf("loads xml json unmarshal: %w", err)
	}
	return result, nil
}

// LoadsJson deserializes a JSON string into native Go types (map/slice/scalar).
func LoadsJson(jsonStr string) (any, error) {
	converted, err := JsonToJson(jsonStr)
	if err != nil {
		return nil, err
	}
	var result any
	if err := json.Unmarshal([]byte(converted), &result); err != nil {
		return nil, fmt.Errorf("loads json json unmarshal: %w", err)
	}
	return result, nil
}

// LoadsYaml deserializes a YAML string into native Go types (map/slice/scalar).
func LoadsYaml(yamlStr string) (any, error) {
	jsonStr, err := YamlToJson(yamlStr)
	if err != nil {
		return nil, err
	}
	var result any
	if err := json.Unmarshal([]byte(jsonStr), &result); err != nil {
		return nil, fmt.Errorf("loads yaml json unmarshal: %w", err)
	}
	return result, nil
}

// LoadsToml deserializes a TOML string into native Go types (map/slice/scalar).
func LoadsToml(tomlStr string) (any, error) {
	jsonStr, err := TomlToJson(tomlStr)
	if err != nil {
		return nil, err
	}
	var result any
	if err := json.Unmarshal([]byte(jsonStr), &result); err != nil {
		return nil, fmt.Errorf("loads toml json unmarshal: %w", err)
	}
	return result, nil
}

// LoadsMd deserializes a Markdown string into native Go types (map/slice/scalar).
func LoadsMd(mdStr string) (any, error) {
	jsonStr, err := MdToJson(mdStr)
	if err != nil {
		return nil, err
	}
	var result any
	if err := json.Unmarshal([]byte(jsonStr), &result); err != nil {
		return nil, fmt.Errorf("loads md json unmarshal: %w", err)
	}
	return result, nil
}

// Loads deserializes a CX string into native Go types (map/slice/scalar).
func Loads(cxStr string) (any, error) {
	jsonStr, err := ToJson(cxStr)
	if err != nil {
		return nil, err
	}
	var result any
	if err := json.Unmarshal([]byte(jsonStr), &result); err != nil {
		return nil, fmt.Errorf("loads json unmarshal: %w", err)
	}
	return result, nil
}

// Dumps serializes native Go types to a CX string.
func Dumps(data any) (string, error) {
	jsonBytes, err := json.Marshal(data)
	if err != nil {
		return "", fmt.Errorf("dumps marshal: %w", err)
	}
	return JsonToCx(string(jsonBytes))
}

// ── CX emitter ────────────────────────────────────────────────────────────────

var (
	_dateRE     = regexp.MustCompile(`^\d{4}-\d{2}-\d{2}$`)
	_datetimeRE = regexp.MustCompile(`^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}`)
	_hexRE      = regexp.MustCompile(`^0[xX][0-9a-fA-F]+$`)
)

func wouldAutotype(s string) bool {
	if strings.Contains(s, " ") {
		return false
	}
	if _hexRE.MatchString(s) {
		return true
	}
	if _, err := strconv.ParseInt(s, 10, 64); err == nil {
		return true
	}
	lower := strings.ToLower(s)
	if strings.Contains(s, ".") || strings.Contains(lower, "e") {
		if _, err := strconv.ParseFloat(s, 64); err == nil {
			return true
		}
	}
	if s == "true" || s == "false" || s == "null" {
		return true
	}
	if _datetimeRE.MatchString(s) {
		return true
	}
	if _dateRE.MatchString(s) {
		return true
	}
	return false
}

func cxChooseQuote(s string) string {
	if !strings.Contains(s, "'") {
		return "'" + s + "'"
	}
	if !strings.Contains(s, `"`) {
		return `"` + s + `"`
	}
	if !strings.Contains(s, "'''") {
		return "'''" + s + "'''"
	}
	return `"` + s + `"` // best effort
}

func cxQuoteText(s string) string {
	needs := strings.HasPrefix(s, " ") || strings.HasSuffix(s, " ") ||
		strings.Contains(s, "  ") || strings.Contains(s, "\n") ||
		strings.Contains(s, "\t") || strings.Contains(s, "[") ||
		strings.Contains(s, "]") || strings.Contains(s, "&") ||
		strings.HasPrefix(s, ":") || strings.HasPrefix(s, "'") ||
		strings.HasPrefix(s, `"`) || wouldAutotype(s)
	if needs {
		return cxChooseQuote(s)
	}
	return s
}

func cxQuoteAttr(s string) string {
	if s == "" || strings.Contains(s, " ") || strings.Contains(s, "'") || strings.Contains(s, `"`) {
		return "'" + s + "'"
	}
	return s
}

func emitScalar(s *ScalarNode) string {
	if s.Value == nil {
		return "null"
	}
	switch v := s.Value.(type) {
	case bool:
		if v {
			return "true"
		}
		return "false"
	case int64:
		return strconv.FormatInt(v, 10)
	case float64:
		f := strconv.FormatFloat(v, 'f', -1, 64)
		if !strings.Contains(f, ".") && !strings.Contains(strings.ToLower(f), "e") {
			f += ".0"
		}
		return f
	default:
		return fmt.Sprintf("%v", v)
	}
}

func emitAttr(a Attr) string {
	switch a.DataType {
	case "int":
		switch v := a.Value.(type) {
		case int64:
			return fmt.Sprintf("%s=%d", a.Name, v)
		case float64:
			return fmt.Sprintf("%s=%d", a.Name, int64(v))
		default:
			return fmt.Sprintf("%s=%v", a.Name, a.Value)
		}
	case "float":
		var f float64
		switch v := a.Value.(type) {
		case float64:
			f = v
		case int64:
			f = float64(v)
		default:
			return fmt.Sprintf("%s=%v", a.Name, a.Value)
		}
		fs := strconv.FormatFloat(f, 'f', -1, 64)
		if !strings.Contains(fs, ".") && !strings.Contains(strings.ToLower(fs), "e") {
			fs += ".0"
		}
		return fmt.Sprintf("%s=%s", a.Name, fs)
	case "bool":
		if b, ok := a.Value.(bool); ok {
			if b {
				return a.Name + "=true"
			}
			return a.Name + "=false"
		}
		return fmt.Sprintf("%s=%v", a.Name, a.Value)
	case "null":
		return a.Name + "=null"
	default:
		// string attr — quote if would autotype
		s := fmt.Sprintf("%v", a.Value)
		var v string
		if wouldAutotype(s) {
			v = cxChooseQuote(s)
		} else {
			v = cxQuoteAttr(s)
		}
		return a.Name + "=" + v
	}
}

func emitInline(node Node) string {
	switch n := node.(type) {
	case *TextNode:
		if strings.TrimSpace(n.Value) == "" {
			return ""
		}
		return cxQuoteText(n.Value)
	case *ScalarNode:
		return emitScalar(n)
	case *EntityRefNode:
		return "&" + n.Name + ";"
	case *RawTextNode:
		return "[#" + n.Value + "#]"
	case *Element:
		return strings.TrimRight(emitElement(n, 0), "\n")
	case *BlockContentNode:
		var sb strings.Builder
		for _, child := range n.Items {
			switch c := child.(type) {
			case *TextNode:
				sb.WriteString(c.Value)
			case *Element:
				sb.WriteString(strings.TrimRight(emitElement(c, 0), "\n"))
			}
		}
		return "[|" + sb.String() + "|]"
	}
	return ""
}

func emitElement(e *Element, depth int) string {
	ind := strings.Repeat("  ", depth)
	hasChildElems := false
	hasText := false
	for _, item := range e.Items {
		switch item.(type) {
		case *Element:
			hasChildElems = true
		case *TextNode, *ScalarNode, *EntityRefNode, *RawTextNode:
			hasText = true
		}
	}
	isMultiline := hasChildElems && !hasText

	var metaParts []string
	if e.Anchor != "" {
		metaParts = append(metaParts, "&"+e.Anchor)
	}
	if e.Merge != "" {
		metaParts = append(metaParts, "*"+e.Merge)
	}
	if e.DataType != "" {
		metaParts = append(metaParts, ":"+e.DataType)
	}
	for _, a := range e.Attrs {
		metaParts = append(metaParts, emitAttr(a))
	}
	meta := ""
	if len(metaParts) > 0 {
		meta = " " + strings.Join(metaParts, " ")
	}

	if isMultiline {
		var sb strings.Builder
		sb.WriteString(ind + "[" + e.Name + meta + "\n")
		for _, item := range e.Items {
			sb.WriteString(emitNode(item, depth+1))
		}
		sb.WriteString(ind + "]\n")
		return sb.String()
	}

	if len(e.Items) == 0 && meta == "" {
		return ind + "[" + e.Name + "]\n"
	}

	var bodyParts []string
	for _, item := range e.Items {
		p := emitInline(item)
		if p != "" {
			bodyParts = append(bodyParts, p)
		}
	}
	body := strings.Join(bodyParts, " ")
	sep := ""
	if body != "" {
		sep = " "
	}
	return ind + "[" + e.Name + meta + sep + body + "]\n"
}

func emitNode(node Node, depth int) string {
	ind := strings.Repeat("  ", depth)
	switch n := node.(type) {
	case *Element:
		return emitElement(n, depth)
	case *TextNode:
		return cxQuoteText(n.Value)
	case *ScalarNode:
		return emitScalar(n)
	case *CommentNode:
		return ind + "[-" + n.Value + "]\n"
	case *RawTextNode:
		return ind + "[#" + n.Value + "#]\n"
	case *EntityRefNode:
		return "&" + n.Name + ";"
	case *AliasNode:
		return ind + "[*" + n.Name + "]\n"
	case *BlockContentNode:
		var sb strings.Builder
		for _, item := range n.Items {
			sb.WriteString(emitNode(item, 0))
		}
		return ind + "[|" + sb.String() + "|]\n"
	case *PINode:
		data := ""
		if n.Data != "" {
			data = " " + n.Data
		}
		return ind + "[?" + n.Target + data + "]\n"
	case *XMLDeclNode:
		parts := []string{"version=" + n.Version}
		if n.Encoding != "" {
			parts = append(parts, "encoding="+n.Encoding)
		}
		if n.Standalone != "" {
			parts = append(parts, "standalone="+n.Standalone)
		}
		return "[?xml " + strings.Join(parts, " ") + "]\n"
	case *CXDirectiveNode:
		var attrParts []string
		for _, a := range n.Attrs {
			attrParts = append(attrParts, a.Name+"="+cxQuoteAttr(fmt.Sprintf("%v", a.Value)))
		}
		return "[?cx " + strings.Join(attrParts, " ") + "]\n"
	case *DoctypeDeclNode:
		ext := ""
		if n.ExternalID != nil {
			if pub, ok := n.ExternalID["public"]; ok {
				sys := ""
				if s, ok2 := n.ExternalID["system"]; ok2 {
					sys = fmt.Sprintf("%v", s)
				}
				ext = fmt.Sprintf(" PUBLIC '%v' '%s'", pub, sys)
			} else if sys, ok := n.ExternalID["system"]; ok {
				ext = fmt.Sprintf(" SYSTEM '%v'", sys)
			}
		}
		return "[!DOCTYPE " + n.Name + ext + "]\n"
	}
	return ""
}

func emitDoc(doc *Document) string {
	var parts []string
	for _, node := range doc.Prolog {
		parts = append(parts, emitNode(node, 0))
	}
	if doc.Doctype != nil {
		parts = append(parts, emitNode(doc.Doctype, 0))
	}
	for _, node := range doc.Elements {
		parts = append(parts, emitNode(node, 0))
	}
	result := strings.Join(parts, "")
	return strings.TrimRight(result, "\n")
}

// ── helpers ───────────────────────────────────────────────────────────────────

func splitPath(path string) []string {
	var parts []string
	for _, p := range strings.Split(path, "/") {
		if p != "" {
			parts = append(parts, p)
		}
	}
	return parts
}
