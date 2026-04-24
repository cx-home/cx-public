module cxlib

import x.json2
import strconv

// ── Node sum type ─────────────────────────────────────────────────────────────

pub type Node = Element
	| TextNode
	| ScalarNode
	| CommentNode
	| RawTextNode
	| EntityRefNode
	| BlockContentNode
	| AliasNode
	| PINode
	| XMLDeclNode
	| CXDirectiveNode
	| DoctypeDeclNode

// ── Scalar types ──────────────────────────────────────────────────────────────

pub enum ScalarType {
	int_type
	float_type
	bool_type
	null_type
	string_type
	date_type
	datetime_type
	bytes_type
}

pub fn scalar_type_from_str(s string) ScalarType {
	return match s {
		'int'      { .int_type }
		'float'    { .float_type }
		'bool'     { .bool_type }
		'null'     { .null_type }
		'string'   { .string_type }
		'date'     { .date_type }
		'datetime' { .datetime_type }
		'bytes'    { .bytes_type }
		else       { .string_type }
	}
}

pub fn scalar_type_name(t ScalarType) string {
	return match t {
		.int_type      { 'int' }
		.float_type    { 'float' }
		.bool_type     { 'bool' }
		.null_type     { 'null' }
		.string_type   { 'string' }
		.date_type     { 'date' }
		.datetime_type { 'datetime' }
		.bytes_type    { 'bytes' }
	}
}

// ScalarVal holds a typed scalar value. int/float/bool/null/string all use
// this union. date/datetime/bytes are stored as string.
pub type ScalarVal = bool | f64 | i64 | string | NullVal

pub struct NullVal {}

pub fn (v ScalarVal) str() string {
	return match v {
		i64    { v.str() }
		f64    { cx_fmt_float(v) }
		bool   { if v { 'true' } else { 'false' } }
		NullVal { 'null' }
		string { v }
	}
}

fn cx_fmt_float(v f64) string {
	s := '${v}'
	return if s.contains('.') || s.contains('e') { s } else { '${s}.0' }
}

// ── Attribute ─────────────────────────────────────────────────────────────────

pub struct Attr {
pub mut:
	name      string
	value     ScalarVal   // string when data_type is none
	data_type ?ScalarType // none = string (omitted in JSON)
}

// ── Node structs ──────────────────────────────────────────────────────────────

pub struct TextNode {
pub mut:
	value string
}

pub struct ScalarNode {
pub mut:
	data_type ScalarType
	value     ScalarVal
}

pub struct CommentNode {
pub mut:
	value string
}

pub struct RawTextNode {
pub mut:
	value string
}

pub struct EntityRefNode {
pub mut:
	name string
}

pub struct AliasNode {
pub mut:
	name string
}

pub struct PINode {
pub mut:
	target string
	data   ?string
}

pub struct XMLDeclNode {
pub mut:
	version    string
	encoding   ?string
	standalone ?string
}

pub struct CXDirectiveNode {
pub mut:
	attrs []Attr
}

pub struct BlockContentNode {
pub mut:
	items []Node
}

pub struct DoctypeDeclNode {
pub mut:
	name        string
	external_id ?ExternalID
	int_subset  []Node
}

pub struct ExternalID {
pub mut:
	public_id ?string
	system_id ?string
}

// ── Element ───────────────────────────────────────────────────────────────────

pub struct Element {
pub mut:
	name      string
	anchor    ?string
	merge     ?string
	data_type ?string   // TypeAnnotation e.g. "int[]"
	attrs     []Attr
	items     []Node
}

// get returns the first child Element with the given name.
pub fn (e Element) get(name string) ?Element {
	for item in e.items {
		if item is Element && item.name == name {
			return item
		}
	}
	return none
}

// get_all returns all child Elements with the given name.
pub fn (e Element) get_all(name string) []Element {
	mut result := []Element{}
	for item in e.items {
		if item is Element && item.name == name {
			result << item
		}
	}
	return result
}

// attr returns the value of the attribute with the given name, or none.
pub fn (e Element) attr(name string) ?ScalarVal {
	for a in e.attrs {
		if a.name == name {
			return a.value
		}
	}
	return none
}

// text returns concatenated text and scalar child content.
pub fn (e Element) text() string {
	mut parts := []string{}
	for item in e.items {
		match item {
			TextNode   { parts << item.value }
			ScalarNode { parts << item.value.str() }
			else       {}
		}
	}
	return parts.join(' ')
}

// scalar returns the value of the first Scalar child, or none.
pub fn (e Element) scalar() ?ScalarVal {
	for item in e.items {
		if item is ScalarNode {
			return item.value
		}
	}
	return none
}

// children returns all child Elements (excludes Text, Scalar, and other nodes).
pub fn (e Element) children() []Element {
	mut result := []Element{}
	for item in e.items {
		if item is Element {
			result << item
		}
	}
	return result
}

// find_all returns all descendant Elements with the given name (depth-first).
pub fn (e Element) find_all(name string) []Element {
	mut result := []Element{}
	for item in e.items {
		if item is Element {
			if item.name == name {
				result << item
			}
			result << item.find_all(name)
		}
	}
	return result
}

// find_first returns the first descendant Element with the given name.
pub fn (e Element) find_first(name string) ?Element {
	for item in e.items {
		if item is Element {
			if item.name == name {
				return item
			}
			if found := item.find_first(name) {
				return found
			}
		}
	}
	return none
}

// at navigates to a nested element by slash-separated path: el.at('server/host').
pub fn (e Element) at(path string) ?Element {
	parts := path.split('/').filter(it.len > 0)
	if parts.len == 0 {
		return none
	}
	mut cur := e.get(parts[0]) or { return none }
	for part in parts[1..] {
		cur = cur.get(part) or { return none }
	}
	return cur
}

// append adds a child node at the end.
pub fn (mut e Element) append(node Node) {
	e.items << node
}

// prepend inserts a child node at the beginning.
pub fn (mut e Element) prepend(node Node) {
	e.items.insert(0, node)
}

// insert inserts a child node at the given index.
pub fn (mut e Element) insert(index int, node Node) {
	e.items.insert(index, node)
}

// remove_at removes the child node at the given index.
pub fn (mut e Element) remove_at(index int) {
	if index >= 0 && index < e.items.len {
		e.items.delete(index)
	}
}

// set_attr sets an attribute value, updating it if it already exists.
// The scalar type is inferred from the value: i64→int, f64→float, bool→bool, NullVal→null, string→string.
pub fn (mut e Element) set_attr(name string, value ScalarVal) {
	dt := infer_scalar_type(value)
	// Clone before in-place mutation to avoid writing through shared slice backing.
	e.attrs = e.attrs.clone()
	for mut a in e.attrs {
		if a.name == name {
			a.value = value
			a.data_type = dt
			return
		}
	}
	e.attrs << Attr{ name: name, value: value, data_type: dt }
}

fn infer_scalar_type(v ScalarVal) ?ScalarType {
	match v {
		i64     { return ScalarType.int_type }
		f64     { return ScalarType.float_type }
		bool    { return ScalarType.bool_type }
		NullVal { return ScalarType.null_type }
		string  { return none }
	}
}

// remove_attr removes the attribute with the given name.
pub fn (mut e Element) remove_attr(name string) {
	e.attrs = e.attrs.filter(it.name != name)
}

// remove_child removes direct child Elements with the given name.
pub fn (mut e Element) remove_child(name string) {
	mut new_items := []Node{}
	for item in e.items {
		if item is Element && item.name == name {
			continue
		}
		new_items << item
	}
	e.items = new_items
}

// ── Document ──────────────────────────────────────────────────────────────────

pub struct Document {
pub mut:
	prolog   []Node
	doctype  ?DoctypeDeclNode
	elements []Node
}

// root returns the first top-level Element.
pub fn (d Document) root() ?Element {
	for e in d.elements {
		if e is Element {
			return e
		}
	}
	return none
}

// get returns the first top-level Element with the given name.
pub fn (d Document) get(name string) ?Element {
	for e in d.elements {
		if e is Element && e.name == name {
			return e
		}
	}
	return none
}

// at navigates by slash-separated path from the first matching top-level element.
pub fn (d Document) at(path string) ?Element {
	parts := path.split('/').filter(it.len > 0)
	if parts.len == 0 {
		return d.root()
	}
	mut cur := d.get(parts[0]) or { return none }
	for part in parts[1..] {
		cur = cur.get(part) or { return none }
	}
	return cur
}

// find_first returns the first descendant Element with the given name across the entire document.
pub fn (d Document) find_first(name string) ?Element {
	for e in d.elements {
		if e is Element {
			if e.name == name {
				return e
			}
			if found := e.find_first(name) {
				return found
			}
		}
	}
	return none
}

// find_all returns all descendant Elements with the given name across the entire document.
pub fn (d Document) find_all(name string) []Element {
	mut result := []Element{}
	for e in d.elements {
		if e is Element {
			if e.name == name {
				result << e
			}
			result << e.find_all(name)
		}
	}
	return result
}

// append adds a top-level node.
pub fn (mut d Document) append(node Node) {
	d.elements << node
}

// prepend inserts a top-level node at the beginning.
pub fn (mut d Document) prepend(node Node) {
	d.elements.insert(0, node)
}

pub fn (d Document) to_cx() string {
	return ast_emit_cx(d)
}

pub fn (d Document) to_xml() !string {
	return to_xml(d.to_cx())
}

pub fn (d Document) to_json() !string {
	return to_json(d.to_cx())
}

pub fn (d Document) to_yaml() !string {
	return to_yaml(d.to_cx())
}

pub fn (d Document) to_toml() !string {
	return to_toml(d.to_cx())
}

pub fn (d Document) to_md() !string {
	return to_md(d.to_cx())
}

// ── Parse functions ───────────────────────────────────────────────────────────

pub fn parse(src string) !Document {
	ast_json := to_ast(src)!
	return ast_doc_from_json(ast_json)!
}

pub fn parse_xml(src string) !Document {
	ast_json := xml_to_ast(src)!
	return ast_doc_from_json(ast_json)!
}

pub fn parse_json(src string) !Document {
	ast_json := json_to_ast(src)!
	return ast_doc_from_json(ast_json)!
}

pub fn parse_yaml(src string) !Document {
	ast_json := yaml_to_ast(src)!
	return ast_doc_from_json(ast_json)!
}

pub fn parse_toml(src string) !Document {
	ast_json := toml_to_ast(src)!
	return ast_doc_from_json(ast_json)!
}

pub fn parse_md(src string) !Document {
	ast_json := md_to_ast(src)!
	return ast_doc_from_json(ast_json)!
}

// loads deserializes a CX string into native V types (json2.Any: map/array/scalar).
pub fn loads(cx_str string) !json2.Any {
	json_str := to_json(cx_str)!
	return json2.decode[json2.Any](json_str)!
}

// dumps serializes native V types (json2.Any) to a CX string.
pub fn dumps(data json2.Any) !string {
	return json_to_cx(data.str())!
}

// ── JSON → AST deserialization ────────────────────────────────────────────────

fn jmap(v json2.Any) map[string]json2.Any {
	return v.as_map()
}

fn jstr(v json2.Any) string {
	return v.str()
}

fn jf64(v json2.Any) f64 {
	return v.f64()
}

fn jbool(v json2.Any) bool {
	return v.bool()
}

fn jobj_str(obj map[string]json2.Any, key string) string {
	v := obj[key] or { return '' }
	return v.str()
}

fn jobj_str_opt(obj map[string]json2.Any, key string) ?string {
	v := obj[key] or { return none }
	if v.type_name() == 'x.json2.Null' { return none }
	s := v.str()
	return if s.len > 0 { s } else { none }
}

fn jobj_arr(obj map[string]json2.Any, key string) []json2.Any {
	v := obj[key] or { return [] }
	return v.as_array()
}

fn ast_doc_from_json(src string) !Document {
	root := json2.decode[json2.Any](src)!
	obj := root.as_map()
	prolog_arr := jobj_arr(obj, 'prolog')
	elems_arr  := jobj_arr(obj, 'elements')

	mut prolog := []Node{}
	for n in prolog_arr { prolog << ast_node_from_any(n)! }

	mut elements := []Node{}
	for n in elems_arr { elements << ast_node_from_any(n)! }

	mut doctype := ?DoctypeDeclNode(none)
	if dt_any := obj['doctype'] {
		doctype = ast_doctype_from_any(dt_any)!
	}

	return Document{ prolog: prolog, doctype: doctype, elements: elements }
}

fn ast_node_from_any(v json2.Any) !Node {
	obj := v.as_map()
	typ := jobj_str(obj, 'type')
	return match typ {
		'Element'         { Node(ast_element_from_any(obj)!) }
		'Text'            { Node(TextNode{ value: jobj_str(obj, 'value') }) }
		'Scalar'          { Node(ast_scalar_from_any(obj)!) }
		'Comment'         { Node(CommentNode{ value: jobj_str(obj, 'value') }) }
		'RawText'         { Node(RawTextNode{ value: jobj_str(obj, 'value') }) }
		'EntityRef'       { Node(EntityRefNode{ name: jobj_str(obj, 'name') }) }
		'Alias'           { Node(AliasNode{ name: jobj_str(obj, 'name') }) }
		'PI'              { Node(ast_pi_from_any(obj)) }
		'XMLDecl'         { Node(ast_xmldecl_from_any(obj)) }
		'CXDirective'     { Node(ast_cxdir_from_any(obj)!) }
		'BlockContent'    { Node(ast_block_from_any(obj)!) }
		'DoctypeDecl'     { Node(ast_doctype_node_from_any(obj)!) }
		else              { Node(TextNode{ value: typ }) }
	}
}

fn ast_element_from_any(obj map[string]json2.Any) !Element {
	mut attrs := []Attr{}
	for a in jobj_arr(obj, 'attrs') {
		attrs << ast_attr_from_any(a.as_map())!
	}
	mut items := []Node{}
	for n in jobj_arr(obj, 'items') {
		items << ast_node_from_any(n)!
	}
	return Element{
		name:      jobj_str(obj, 'name')
		anchor:    jobj_str_opt(obj, 'anchor')
		merge:     jobj_str_opt(obj, 'merge')
		data_type: jobj_str_opt(obj, 'dataType')
		attrs:     attrs
		items:     items
	}
}

fn ast_attr_from_any(obj map[string]json2.Any) !Attr {
	name := jobj_str(obj, 'name')
	dt_str := jobj_str_opt(obj, 'dataType')
	val_any := obj['value'] or { json2.Any('') }

	if dt := dt_str {
		st := scalar_type_from_str(dt)
		val := ast_scalar_val_from_any(val_any, st)
		return Attr{ name: name, value: val, data_type: st }
	}
	// no dataType → string
	return Attr{ name: name, value: ScalarVal(jstr(val_any)), data_type: none }
}

fn ast_scalar_from_any(obj map[string]json2.Any) !ScalarNode {
	dt_str := jobj_str(obj, 'dataType')
	st := scalar_type_from_str(dt_str)
	val_any := obj['value'] or { json2.Any('') }
	return ScalarNode{ data_type: st, value: ast_scalar_val_from_any(val_any, st) }
}

fn ast_scalar_val_from_any(v json2.Any, st ScalarType) ScalarVal {
	return match st {
		.int_type      { ScalarVal(i64(v.f64())) }
		.float_type    { ScalarVal(v.f64()) }
		.bool_type     { ScalarVal(v.bool()) }
		.null_type     { ScalarVal(NullVal{}) }
		else           { ScalarVal(v.str()) }
	}
}

fn ast_pi_from_any(obj map[string]json2.Any) PINode {
	return PINode{
		target: jobj_str(obj, 'target')
		data:   jobj_str_opt(obj, 'data')
	}
}

fn ast_xmldecl_from_any(obj map[string]json2.Any) XMLDeclNode {
	return XMLDeclNode{
		version:    jobj_str(obj, 'version')
		encoding:   jobj_str_opt(obj, 'encoding')
		standalone: jobj_str_opt(obj, 'standalone')
	}
}

fn ast_cxdir_from_any(obj map[string]json2.Any) !CXDirectiveNode {
	mut attrs := []Attr{}
	for a in jobj_arr(obj, 'attrs') {
		attrs << ast_attr_from_any(a.as_map())!
	}
	return CXDirectiveNode{ attrs: attrs }
}

fn ast_block_from_any(obj map[string]json2.Any) !BlockContentNode {
	mut items := []Node{}
	for n in jobj_arr(obj, 'items') {
		items << ast_node_from_any(n)!
	}
	return BlockContentNode{ items: items }
}

fn ast_doctype_from_any(v json2.Any) !DoctypeDeclNode {
	return ast_doctype_node_from_any(v.as_map())!
}

fn ast_doctype_node_from_any(obj map[string]json2.Any) !DoctypeDeclNode {
	name := jobj_str(obj, 'name')
	mut ext_id := ?ExternalID(none)
	if eid_any := obj['externalID'] {
		eid := eid_any.as_map()
		ext_id = ExternalID{
			public_id: jobj_str_opt(eid, 'public')
			system_id: jobj_str_opt(eid, 'system')
		}
	}
	mut subset := []Node{}
	for n in jobj_arr(obj, 'intSubset') {
		subset << ast_node_from_any(n)!
	}
	return DoctypeDeclNode{ name: name, external_id: ext_id, int_subset: subset }
}

// ── CX emitter ────────────────────────────────────────────────────────────────

fn ast_emit_cx(doc Document) string {
	mut out := []string{}
	for n in doc.prolog   { ast_emit_node(n, 0, mut out) }
	if dt := doc.doctype  { ast_emit_doctype(dt, mut out) }
	for n in doc.elements { ast_emit_node(n, 0, mut out) }
	result := out.join('')
	return result.trim_right('\n')
}

fn cx_ind(depth int) string {
	return '  '.repeat(depth)
}

fn ast_emit_node(n Node, depth int, mut out []string) {
	match n {
		Element          { ast_emit_element(n, depth, mut out) }
		TextNode         { out << cx_qt_text(n.value) }
		ScalarNode       { out << ast_emit_scalar(n) }
		CommentNode      { out << '${cx_ind(depth)}[-${n.value}]\n' }
		RawTextNode      { out << '${cx_ind(depth)}[#${n.value}#]\n' }
		EntityRefNode    { out << '&${n.name};' }
		AliasNode        { out << '${cx_ind(depth)}[*${n.name}]\n' }
		BlockContentNode { ast_emit_block(n, depth, mut out) }
		PINode           {
			data := n.data or { '' }
			sep := if data.len > 0 { ' ' } else { '' }
			out << '${cx_ind(depth)}[?${n.target}${sep}${data}]\n'
		}
		XMLDeclNode      {
			mut s := '[?xml version=${n.version}'
			if enc := n.encoding   { s += ' encoding=${enc}' }
			if sa  := n.standalone  { s += ' standalone=${sa}' }
			out << '${s}]\n'
		}
		CXDirectiveNode  {
			attrs := n.attrs.map(' ${it.name}=${cx_qa(it.value.str())}').join('')
			out << '[?cx${attrs}]\n'
		}
		DoctypeDeclNode  { ast_emit_doctype(n, mut out) }
	}
}

fn ast_emit_element(e Element, depth int, mut out []string) {
	ind := cx_ind(depth)
	has_child_elems := e.items.any(it is Element)
	has_text := e.items.any(it is TextNode || it is ScalarNode || it is EntityRefNode || it is RawTextNode)
	is_multiline := has_child_elems && !has_text

	meta := ast_build_meta(e)

	if is_multiline {
		out << '${ind}[${e.name}${meta}\n'
		for item in e.items { ast_emit_node(item, depth + 1, mut out) }
		out << '${ind}]\n'
	} else if e.items.len == 0 && meta.len == 0 {
		out << '${ind}[${e.name}]\n'
	} else {
		body := ast_build_inline(e.items)
		sep := if body.len > 0 { ' ' } else { '' }
		out << '${ind}[${e.name}${meta}${sep}${body}]\n'
	}
}

fn ast_build_meta(e Element) string {
	mut s := ''
	if a := e.anchor    { s += ' &${a}' }
	if m := e.merge     { s += ' *${m}' }
	if dt := e.data_type { s += ' :${dt}' }
	for a in e.attrs {
		vs := a.value.str()
		emitted := if a.data_type == none && cx_would_autotype(vs) {
			cx_choose_quote(vs)
		} else {
			cx_qa(vs)
		}
		s += ' ${a.name}=${emitted}'
	}
	return s
}

fn ast_build_inline(items []Node) string {
	mut parts := []string{}
	for item in items {
		match item {
			TextNode {
				if item.value.trim_space().len == 0 { continue }
				parts << cx_qt_text(item.value)
			}
			ScalarNode    { parts << ast_emit_scalar(item) }
			EntityRefNode { parts << '&${item.name};' }
			RawTextNode   { parts << '[#${item.value}#]' }
			Element {
				mut tmp := []string{}
				ast_emit_element(item, 0, mut tmp)
				parts << tmp.join('').trim_right('\n')
			}
			BlockContentNode {
				mut s := '[|'
				for bi in item.items {
					match bi {
						TextNode { s += bi.value }
						Element  {
							mut tmp := []string{}
							ast_emit_element(bi, 0, mut tmp)
							s += tmp.join('').trim_right('\n')
						}
						else {}
					}
				}
				s += '|]'
				parts << s
			}
			else {}
		}
	}
	return parts.join(' ')
}

fn ast_emit_scalar(s ScalarNode) string {
	return s.value.str()
}

fn ast_emit_block(bc BlockContentNode, depth int, mut out []string) {
	out << '${cx_ind(depth)}[|'
	for item in bc.items {
		match item {
			TextNode { out << item.value }
			Element  {
				mut tmp := []string{}
				ast_emit_element(item, 0, mut tmp)
				out << tmp.join('').trim_right('\n')
			}
			else {}
		}
	}
	out << '|]\n'
}

fn ast_emit_doctype(d DoctypeDeclNode, mut out []string) {
	mut header := '[!DOCTYPE ${d.name}'
	if ext := d.external_id {
		if pub_id := ext.public_id {
			sys := ext.system_id or { '' }
			header += " PUBLIC '${pub_id}' '${sys}'"
		} else if sys := ext.system_id {
			header += " SYSTEM '${sys}'"
		}
	}
	if d.int_subset.len == 0 {
		out << '${header}]\n'
	} else {
		out << '${header} [\n'
		for n in d.int_subset { ast_emit_node(n, 1, mut out) }
		out << ']]\n'
	}
}

// ── Quoting helpers ───────────────────────────────────────────────────────────

fn cx_qt_text(s string) string {
	needs := s.starts_with(' ') || s.ends_with(' ')
		|| s.contains('  ') || s.contains('\n') || s.contains('\t')
		|| s.contains('[') || s.contains(']') || s.contains('&')
		|| s.starts_with(':') || s.starts_with("'") || s.starts_with('"')
		|| cx_would_autotype(s)
	return if needs { cx_choose_quote(s) } else { s }
}

fn cx_qa(s string) string {
	if s.contains(' ') || s.contains("'") || s.contains('"') || s.len == 0 {
		return "'${s}'"
	}
	return s
}

fn cx_choose_quote(s string) string {
	if !s.contains("'") { return "'${s}'" }
	if !s.contains('"') { return '"${s}"' }
	if !s.contains("'''") { return "'''${s}'''" }
	return '"${s}"'
}

fn cx_would_autotype(s string) bool {
	if s.contains(' ') { return false }
	if s.starts_with('0x') || s.starts_with('0X') { return true }
	if s == 'true' || s == 'false' || s == 'null' { return true }
	if _ := s.parse_int(10, 64) { return true }
	if s.contains('.') || s.contains('e') || s.contains('E') {
		if _ := strconv.atof64(s) { return true }
	}
	if cx_is_datetime(s) { return true }
	if cx_is_date(s)     { return true }
	return false
}

fn cx_is_date(s string) bool {
	if s.len != 10 { return false }
	return s[4] == `-` && s[7] == `-`
		&& s[0..4].bytes().all(it >= `0` && it <= `9`)
		&& s[5..7].bytes().all(it >= `0` && it <= `9`)
		&& s[8..10].bytes().all(it >= `0` && it <= `9`)
}

fn cx_is_datetime(s string) bool {
	if s.len < 19 { return false }
	return cx_is_date(s[0..10]) && s[10] == `T`
}
