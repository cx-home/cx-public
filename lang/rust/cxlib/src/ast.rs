//! CX native AST types — parse, emit, and query.

use serde_json::Value;

// ── Node types ────────────────────────────────────────────────────────────────

#[derive(Debug, Clone)]
pub struct Attr {
    pub name: String,
    pub value: Value,
    pub data_type: Option<String>,
}

#[derive(Debug, Clone)]
pub struct Element {
    pub name: String,
    pub anchor: Option<String>,
    pub merge: Option<String>,
    pub data_type: Option<String>,
    pub attrs: Vec<Attr>,
    pub items: Vec<Node>,
}

#[derive(Debug, Clone)]
pub enum Node {
    Element(Element),
    Text(String),
    Scalar { data_type: String, value: Value },
    Comment(String),
    RawText(String),
    EntityRef(String),
    Alias(String),
    PI { target: String, data: Option<String> },
    XMLDecl { version: String, encoding: Option<String>, standalone: Option<String> },
    CXDirective(Vec<Attr>),
    DoctypeDecl { name: String, external_id: Option<Value>, int_subset: Vec<Value> },
    BlockContent(Vec<Node>),
}

#[derive(Debug, Clone)]
pub struct Document {
    pub elements: Vec<Node>,
    pub prolog: Vec<Node>,
}

// ── Element methods ───────────────────────────────────────────────────────────

impl Element {
    /// Create a new empty element with the given name.
    pub fn new(name: impl Into<String>) -> Self {
        Element {
            name: name.into(),
            anchor: None,
            merge: None,
            data_type: None,
            attrs: Vec::new(),
            items: Vec::new(),
        }
    }

    /// Attribute value by name, or None.
    pub fn attr(&self, name: &str) -> Option<&Value> {
        self.attrs.iter().find(|a| a.name == name).map(|a| &a.value)
    }

    /// Concatenated Text and Scalar child content.
    pub fn text(&self) -> String {
        let parts: Vec<String> = self.items.iter().filter_map(|item| match item {
            Node::Text(s) => Some(s.clone()),
            Node::Scalar { value, .. } => Some(match value {
                Value::Null => "null".to_string(),
                _ => json_value_to_display(value),
            }),
            _ => None,
        }).collect();
        parts.join(" ")
    }

    /// Value of first Scalar child, or None.
    pub fn scalar(&self) -> Option<&Value> {
        self.items.iter().find_map(|item| {
            if let Node::Scalar { value, .. } = item { Some(value) } else { None }
        })
    }

    /// All child Elements (excludes Text, Scalar, and other nodes).
    pub fn children(&self) -> Vec<&Element> {
        self.items.iter().filter_map(|item| {
            if let Node::Element(e) = item { Some(e) } else { None }
        }).collect()
    }

    /// First child Element with this name.
    pub fn get(&self, name: &str) -> Option<&Element> {
        self.items.iter().find_map(|item| {
            if let Node::Element(e) = item {
                if e.name == name { Some(e) } else { None }
            } else {
                None
            }
        })
    }

    /// All child Elements with this name.
    pub fn get_all(&self, name: &str) -> Vec<&Element> {
        self.items.iter().filter_map(|item| {
            if let Node::Element(e) = item {
                if e.name == name { Some(e) } else { None }
            } else {
                None
            }
        }).collect()
    }

    /// All descendant Elements with this name (depth-first).
    pub fn find_all(&self, name: &str) -> Vec<&Element> {
        let mut result = Vec::new();
        for item in &self.items {
            if let Node::Element(e) = item {
                if e.name == name {
                    result.push(e);
                }
                result.extend(e.find_all(name));
            }
        }
        result
    }

    /// First descendant Element with this name (depth-first).
    pub fn find_first(&self, name: &str) -> Option<&Element> {
        for item in &self.items {
            if let Node::Element(e) = item {
                if e.name == name {
                    return Some(e);
                }
                if let Some(found) = e.find_first(name) {
                    return Some(found);
                }
            }
        }
        None
    }

    /// Navigate by slash-separated path: `el.at("server/host")`.
    pub fn at(&self, path: &str) -> Option<&Element> {
        let mut cur: Option<&Element> = Some(self);
        for part in path.split('/').filter(|p| !p.is_empty()) {
            cur = cur.and_then(|e| e.get(part));
        }
        cur
    }

    /// Set an attribute value, updating if it already exists.
    pub fn set_attr(&mut self, name: &str, value: Value, data_type: Option<String>) {
        if let Some(a) = self.attrs.iter_mut().find(|a| a.name == name) {
            a.value = value;
            a.data_type = data_type;
        } else {
            self.attrs.push(Attr { name: name.to_string(), value, data_type });
        }
    }

    /// Remove an attribute by name.
    pub fn remove_attr(&mut self, name: &str) {
        self.attrs.retain(|a| a.name != name);
    }

    /// Append a child node.
    pub fn append(&mut self, node: Node) {
        self.items.push(node);
    }

    /// Prepend a child node.
    pub fn prepend(&mut self, node: Node) {
        self.items.insert(0, node);
    }

    /// Remove a child node by index.
    pub fn remove_child_at(&mut self, index: usize) {
        if index < self.items.len() {
            self.items.remove(index);
        }
    }

    /// Remove the first child Element with a given name.
    pub fn remove_named(&mut self, name: &str) {
        if let Some(pos) = self.items.iter().position(|item| {
            matches!(item, Node::Element(e) if e.name == name)
        }) {
            self.items.remove(pos);
        }
    }

    /// Remove all direct child Elements with the given name.
    pub fn remove_child(&mut self, name: &str) {
        self.items.retain(|item| {
            !matches!(item, Node::Element(e) if e.name == name)
        });
    }

    /// Remove child node at index (no-op if out of bounds). Alias for remove_child_at.
    pub fn remove_at(&mut self, index: usize) {
        self.remove_child_at(index);
    }

    /// First Element matching a CXPath expression (searches subtree of this element).
    pub fn select(&self, expr: &str) -> Result<Option<Element>, String> {
        let results = self.select_all(expr)?;
        Ok(results.into_iter().next())
    }

    /// All Elements matching a CXPath expression (searches subtree of this element).
    pub fn select_all(&self, expr: &str) -> Result<Vec<Element>, String> {
        let cx = crate::cxpath::cxpath_parse(expr)?;
        let mut result = Vec::new();
        crate::cxpath::collect_step(self, &cx, 0, &mut result);
        Ok(result)
    }
}

// ── Document methods ──────────────────────────────────────────────────────────

impl Document {
    /// Create an empty document.
    pub fn new() -> Self {
        Document { elements: Vec::new(), prolog: Vec::new() }
    }

    /// First top-level Element.
    pub fn root(&self) -> Option<&Element> {
        self.elements.iter().find_map(|n| {
            if let Node::Element(e) = n { Some(e) } else { None }
        })
    }

    /// First top-level Element with this name.
    pub fn get(&self, name: &str) -> Option<&Element> {
        self.elements.iter().find_map(|n| {
            if let Node::Element(e) = n {
                if e.name == name { Some(e) } else { None }
            } else {
                None
            }
        })
    }

    /// Navigate by slash-separated path from root: `doc.at("article/body/p")`.
    pub fn at(&self, path: &str) -> Option<&Element> {
        let parts: Vec<&str> = path.split('/').filter(|p| !p.is_empty()).collect();
        if parts.is_empty() {
            return self.root();
        }
        let first = self.get(parts[0])?;
        if parts.len() == 1 {
            return Some(first);
        }
        first.at(&parts[1..].join("/"))
    }

    /// All descendant Elements with this name (depth-first through entire document).
    pub fn find_all(&self, name: &str) -> Vec<&Element> {
        let mut result = Vec::new();
        for node in &self.elements {
            if let Node::Element(e) = node {
                if e.name == name {
                    result.push(e);
                }
                result.extend(e.find_all(name));
            }
        }
        result
    }

    /// First descendant Element with this name (depth-first through entire document).
    pub fn find_first(&self, name: &str) -> Option<&Element> {
        for node in &self.elements {
            if let Node::Element(e) = node {
                if e.name == name {
                    return Some(e);
                }
                if let Some(found) = e.find_first(name) {
                    return Some(found);
                }
            }
        }
        None
    }

    /// Append a top-level node.
    pub fn append(&mut self, node: Node) {
        self.elements.push(node);
    }

    /// Prepend a top-level node.
    pub fn prepend(&mut self, node: Node) {
        self.elements.insert(0, node);
    }

    /// Emit this document as a CX string (native emitter, no C library call).
    pub fn to_cx(&self) -> String {
        emit_doc(self)
    }

    /// Convert to XML via the CX library.
    pub fn to_xml(&self) -> Result<String, String> {
        crate::to_xml(&self.to_cx())
    }

    /// Convert to JSON via the CX library.
    pub fn to_json(&self) -> Result<String, String> {
        crate::to_json(&self.to_cx())
    }

    /// Convert to YAML via the CX library.
    pub fn to_yaml(&self) -> Result<String, String> {
        crate::to_yaml(&self.to_cx())
    }

    /// Convert to TOML via the CX library.
    pub fn to_toml(&self) -> Result<String, String> {
        crate::to_toml(&self.to_cx())
    }

    /// Convert to Markdown via the CX library.
    pub fn to_md(&self) -> Result<String, String> {
        crate::to_md(&self.to_cx())
    }

    /// First Element matching a CXPath expression.
    pub fn select(&self, expr: &str) -> Result<Option<Element>, String> {
        let results = self.select_all(expr)?;
        Ok(results.into_iter().next())
    }

    /// All Elements matching a CXPath expression.
    pub fn select_all(&self, expr: &str) -> Result<Vec<Element>, String> {
        let cx = crate::cxpath::cxpath_parse(expr)?;
        let vroot = Element {
            name: "#document".to_string(),
            anchor: None,
            merge: None,
            data_type: None,
            attrs: Vec::new(),
            items: self.elements.clone(),
        };
        let mut result = Vec::new();
        crate::cxpath::collect_step(&vroot, &cx, 0, &mut result);
        Ok(result)
    }

    /// Return new Document with element at path replaced by f(element).
    pub fn transform<F>(&self, path: &str, f: F) -> Document
    where
        F: Fn(Element) -> Element,
    {
        use crate::cxpath::{elem_detached, doc_replace_at, path_copy_element};
        let parts: Vec<&str> = path.split('/').filter(|p| !p.is_empty()).collect();
        if parts.is_empty() {
            return self.clone();
        }
        for (i, node) in self.elements.iter().enumerate() {
            if let Node::Element(el) = node {
                if el.name == parts[0] {
                    if parts.len() == 1 {
                        return doc_replace_at(self, i, f(elem_detached(el)));
                    }
                    if let Some(updated) = path_copy_element(el, &parts[1..], &f) {
                        return doc_replace_at(self, i, updated);
                    }
                    return self.clone();
                }
            }
        }
        self.clone()
    }

    /// Return new Document with all matching elements replaced by f(element).
    pub fn transform_all<F>(&self, expr: &str, f: F) -> Result<Document, String>
    where
        F: Fn(Element) -> Element,
    {
        let cx = crate::cxpath::cxpath_parse(expr)?;
        let new_elements: Vec<Node> = self.elements.iter()
            .map(|n| crate::cxpath::rebuild_node(n, &cx, &f))
            .collect();
        Ok(Document { elements: new_elements, prolog: self.prolog.clone() })
    }
}

impl Default for Document {
    fn default() -> Self {
        Self::new()
    }
}

// ── JSON deserialization ──────────────────────────────────────────────────────

fn node_from_value(v: &Value) -> Node {
    let t = v["type"].as_str().unwrap_or("");
    match t {
        "Element" => Node::Element(element_from_value(v)),
        "Text" => Node::Text(v["value"].as_str().unwrap_or("").to_string()),
        "Scalar" => Node::Scalar {
            data_type: v["dataType"].as_str().unwrap_or("string").to_string(),
            value: v["value"].clone(),
        },
        "Comment" => Node::Comment(v["value"].as_str().unwrap_or("").to_string()),
        "RawText" => Node::RawText(v["value"].as_str().unwrap_or("").to_string()),
        "EntityRef" => Node::EntityRef(v["name"].as_str().unwrap_or("").to_string()),
        "Alias" => Node::Alias(v["name"].as_str().unwrap_or("").to_string()),
        "PI" => Node::PI {
            target: v["target"].as_str().unwrap_or("").to_string(),
            data: v["data"].as_str().map(|s| s.to_string()),
        },
        "XMLDecl" => Node::XMLDecl {
            version: v["version"].as_str().unwrap_or("1.0").to_string(),
            encoding: v["encoding"].as_str().map(|s| s.to_string()),
            standalone: v["standalone"].as_str().map(|s| s.to_string()),
        },
        "CXDirective" => {
            let attrs = v["attrs"].as_array()
                .map(|arr| arr.iter().map(attr_from_value).collect())
                .unwrap_or_default();
            Node::CXDirective(attrs)
        }
        "DoctypeDecl" => {
            let int_subset = v["intSubset"].as_array()
                .map(|arr| arr.iter().cloned().collect())
                .unwrap_or_default();
            let external_id = v.get("externalID")
                .filter(|v| !v.is_null())
                .cloned();
            Node::DoctypeDecl {
                name: v["name"].as_str().unwrap_or("").to_string(),
                external_id,
                int_subset,
            }
        }
        "BlockContent" => {
            let items = v["items"].as_array()
                .map(|arr| arr.iter().map(node_from_value).collect())
                .unwrap_or_default();
            Node::BlockContent(items)
        }
        _ => Node::Text(v.to_string()),
    }
}

fn attr_from_value(a: &Value) -> Attr {
    Attr {
        name: a["name"].as_str().unwrap_or("").to_string(),
        value: a["value"].clone(),
        data_type: a["dataType"].as_str().map(|s| s.to_string()),
    }
}

fn element_from_value(v: &Value) -> Element {
    let attrs = v["attrs"].as_array()
        .map(|arr| arr.iter().map(attr_from_value).collect())
        .unwrap_or_default();
    let items = v["items"].as_array()
        .map(|arr| arr.iter().map(node_from_value).collect())
        .unwrap_or_default();
    Element {
        name: v["name"].as_str().unwrap_or("").to_string(),
        anchor: v["anchor"].as_str().map(|s| s.to_string()),
        merge: v["merge"].as_str().map(|s| s.to_string()),
        data_type: v["dataType"].as_str().map(|s| s.to_string()),
        attrs,
        items,
    }
}

fn doc_from_value(v: &Value) -> Document {
    let prolog = v["prolog"].as_array()
        .map(|arr| arr.iter().map(node_from_value).collect())
        .unwrap_or_default();
    let elements = v["elements"].as_array()
        .map(|arr| arr.iter().map(node_from_value).collect())
        .unwrap_or_default();
    Document { prolog, elements }
}

// ── Public parse/loads/dumps functions ────────────────────────────────────────

/// Parse a CX string into a Document (uses binary wire protocol).
pub fn parse(cx_str: &str) -> Result<Document, String> {
    let data = crate::call_bin(cx_str, "cx_to_ast_bin")?;
    crate::binary::decode_ast(&data)
}

/// Parse an XML string into a Document.
pub fn parse_xml(xml_str: &str) -> Result<Document, String> {
    let ast_json = crate::xml_to_ast(xml_str)?;
    let v: Value = serde_json::from_str(&ast_json).map_err(|e| e.to_string())?;
    Ok(doc_from_value(&v))
}

/// Parse a JSON string into a Document.
pub fn parse_json(json_str: &str) -> Result<Document, String> {
    let ast_json = crate::json_to_ast(json_str)?;
    let v: Value = serde_json::from_str(&ast_json).map_err(|e| e.to_string())?;
    Ok(doc_from_value(&v))
}

/// Parse a YAML string into a Document.
pub fn parse_yaml(yaml_str: &str) -> Result<Document, String> {
    let ast_json = crate::yaml_to_ast(yaml_str)?;
    let v: Value = serde_json::from_str(&ast_json).map_err(|e| e.to_string())?;
    Ok(doc_from_value(&v))
}

/// Parse a TOML string into a Document.
pub fn parse_toml(toml_str: &str) -> Result<Document, String> {
    let ast_json = crate::toml_to_ast(toml_str)?;
    let v: Value = serde_json::from_str(&ast_json).map_err(|e| e.to_string())?;
    Ok(doc_from_value(&v))
}

/// Parse a Markdown string into a Document.
pub fn parse_md(md_str: &str) -> Result<Document, String> {
    let ast_json = crate::md_to_ast(md_str)?;
    let v: Value = serde_json::from_str(&ast_json).map_err(|e| e.to_string())?;
    Ok(doc_from_value(&v))
}

/// Deserialize a CX string into a JSON Value (dict/list/scalar).
pub fn loads(cx_str: &str) -> Result<Value, String> {
    let json_str = crate::to_json(cx_str)?;
    serde_json::from_str(&json_str).map_err(|e| e.to_string())
}

/// Deserialize an XML string into a JSON Value.
pub fn loads_xml(xml_str: &str) -> Result<Value, String> {
    let json_str = crate::xml_to_json(xml_str)?;
    serde_json::from_str(&json_str).map_err(|e| e.to_string())
}

/// Deserialize a JSON string via the CX semantic bridge.
pub fn loads_json(json_str: &str) -> Result<Value, String> {
    let out = crate::json_to_json(json_str)?;
    serde_json::from_str(&out).map_err(|e| e.to_string())
}

/// Deserialize a YAML string into a JSON Value.
pub fn loads_yaml(yaml_str: &str) -> Result<Value, String> {
    let json_str = crate::yaml_to_json(yaml_str)?;
    serde_json::from_str(&json_str).map_err(|e| e.to_string())
}

/// Deserialize a TOML string into a JSON Value.
pub fn loads_toml(toml_str: &str) -> Result<Value, String> {
    let json_str = crate::toml_to_json(toml_str)?;
    serde_json::from_str(&json_str).map_err(|e| e.to_string())
}

/// Deserialize a Markdown string into a JSON Value.
pub fn loads_md(md_str: &str) -> Result<Value, String> {
    let json_str = crate::md_to_json(md_str)?;
    serde_json::from_str(&json_str).map_err(|e| e.to_string())
}

/// Serialize a JSON Value into a CX string.
pub fn dumps(data: &Value) -> Result<String, String> {
    crate::json_to_cx(&data.to_string())
}

// ── CX emitter helpers ────────────────────────────────────────────────────────

fn json_value_to_display(v: &Value) -> String {
    match v {
        Value::Null => "null".to_string(),
        Value::Bool(b) => if *b { "true".to_string() } else { "false".to_string() },
        Value::Number(n) => n.to_string(),
        Value::String(s) => s.clone(),
        _ => v.to_string(),
    }
}

/// Returns true if the string would be auto-typed by the CX parser (i.e. needs quoting).
fn would_autotype(s: &str) -> bool {
    if s.is_empty() || s.contains(' ') {
        return false;
    }
    // hex literal: 0x... or 0X...
    if s.len() > 2 {
        let bytes = s.as_bytes();
        if bytes[0] == b'0' && (bytes[1] == b'x' || bytes[1] == b'X') {
            if s[2..].chars().all(|c| c.is_ascii_hexdigit()) {
                return true;
            }
        }
    }
    // integer
    if s.parse::<i64>().is_ok() {
        return true;
    }
    // float — only if it contains '.' or 'e'/'E'
    let sl = s.to_ascii_lowercase();
    if sl.contains('.') || sl.contains('e') {
        if s.parse::<f64>().is_ok() {
            return true;
        }
    }
    // boolean / null keywords
    if matches!(s, "true" | "false" | "null") {
        return true;
    }
    // date: YYYY-MM-DD
    if is_date(s) {
        return true;
    }
    // datetime: YYYY-MM-DDTHH:MM:SS...
    if is_datetime(s) {
        return true;
    }
    false
}

fn is_date(s: &str) -> bool {
    // YYYY-MM-DD  (exactly 10 chars, pattern \d{4}-\d{2}-\d{2})
    if s.len() != 10 { return false; }
    let b = s.as_bytes();
    b[4] == b'-' && b[7] == b'-'
        && b[0..4].iter().all(|c| c.is_ascii_digit())
        && b[5..7].iter().all(|c| c.is_ascii_digit())
        && b[8..10].iter().all(|c| c.is_ascii_digit())
}

fn is_datetime(s: &str) -> bool {
    // YYYY-MM-DDTHH:MM:SS... (at least 19 chars)
    if s.len() < 19 { return false; }
    let b = s.as_bytes();
    b[4] == b'-' && b[7] == b'-' && (b[10] == b'T' || b[10] == b't')
        && b[13] == b':' && b[16] == b':'
        && b[0..4].iter().all(|c| c.is_ascii_digit())
        && b[5..7].iter().all(|c| c.is_ascii_digit())
        && b[8..10].iter().all(|c| c.is_ascii_digit())
        && b[11..13].iter().all(|c| c.is_ascii_digit())
        && b[14..16].iter().all(|c| c.is_ascii_digit())
        && b[17..19].iter().all(|c| c.is_ascii_digit())
}

fn cx_choose_quote(s: &str) -> String {
    if !s.contains('\'') {
        return format!("'{}'", s);
    }
    if !s.contains('"') {
        return format!("\"{}\"", s);
    }
    if !s.contains("'''") {
        return format!("'''{}'''", s);
    }
    format!("\"{}\"", s)
}

fn cx_quote_text(s: &str) -> String {
    let needs = s.starts_with(' ')
        || s.ends_with(' ')
        || s.contains("  ")
        || s.contains('\n')
        || s.contains('\t')
        || s.contains('[')
        || s.contains(']')
        || s.contains('&')
        || s.starts_with(':')
        || s.starts_with('\'')
        || s.starts_with('"')
        || would_autotype(s);
    if needs { cx_choose_quote(s) } else { s.to_string() }
}

fn cx_quote_attr(s: &str) -> String {
    if s.is_empty() || s.contains(' ') || s.contains('\'') || s.contains('"') {
        return format!("'{}'", s);
    }
    s.to_string()
}

fn emit_scalar_value(data_type: &str, value: &Value) -> String {
    match value {
        Value::Null => "null".to_string(),
        Value::Bool(b) => if *b { "true".to_string() } else { "false".to_string() },
        Value::Number(n) => {
            if data_type == "float" {
                let f = n.as_f64().unwrap_or(0.0);
                let s = format!("{}", f);
                if s.contains('.') || s.to_ascii_lowercase().contains('e') {
                    s
                } else {
                    format!("{}.0", s)
                }
            } else {
                n.to_string()
            }
        }
        Value::String(s) => s.clone(),
        _ => value.to_string(),
    }
}

fn emit_attr(a: &Attr) -> String {
    let dt = a.data_type.as_deref();
    match dt {
        Some("int") => {
            let n = match &a.value {
                Value::Number(n) => n.to_string(),
                Value::String(s) => s.clone(),
                _ => a.value.to_string(),
            };
            format!("{}={}", a.name, n)
        }
        Some("float") => {
            let f = match &a.value {
                Value::Number(n) => n.as_f64().unwrap_or(0.0),
                Value::String(s) => s.parse::<f64>().unwrap_or(0.0),
                _ => 0.0,
            };
            let s = format!("{}", f);
            let v = if s.contains('.') || s.to_ascii_lowercase().contains('e') { s } else { format!("{}.0", s) };
            format!("{}={}", a.name, v)
        }
        Some("bool") => {
            let b = matches!(&a.value, Value::Bool(true));
            format!("{}={}", a.name, if b { "true" } else { "false" })
        }
        Some("null") => format!("{}=null", a.name),
        _ => {
            // string attr — quote if would autotype
            let s = json_value_to_display(&a.value);
            let v = if would_autotype(&s) { cx_choose_quote(&s) } else { cx_quote_attr(&s) };
            format!("{}={}", a.name, v)
        }
    }
}

fn emit_inline(node: &Node) -> String {
    match node {
        Node::Text(s) => {
            if s.trim().is_empty() { String::new() } else { cx_quote_text(s) }
        }
        Node::Scalar { data_type, value } => emit_scalar_value(data_type, value),
        Node::EntityRef(name) => format!("&{};", name),
        Node::RawText(s) => format!("[#{}#]", s),
        Node::Element(e) => {
            let emitted = emit_element(e, 0);
            emitted.trim_end_matches('\n').to_string()
        }
        Node::BlockContent(items) => {
            let inner: String = items.iter().map(|n| match n {
                Node::Text(s) => s.clone(),
                Node::Element(e) => emit_element(e, 0).trim_end_matches('\n').to_string(),
                _ => emit_inline(n),
            }).collect();
            format!("[|{}|]", inner)
        }
        _ => String::new(),
    }
}

fn emit_element(e: &Element, depth: usize) -> String {
    let ind = "  ".repeat(depth);
    let has_child_elems = e.items.iter().any(|i| matches!(i, Node::Element(_)));
    let has_text = e.items.iter().any(|i| matches!(i,
        Node::Text(_) | Node::Scalar { .. } | Node::EntityRef(_) | Node::RawText(_)
    ));
    let is_multiline = has_child_elems && !has_text;

    let mut meta_parts: Vec<String> = Vec::new();
    if let Some(ref anchor) = e.anchor {
        meta_parts.push(format!("&{}", anchor));
    }
    if let Some(ref merge) = e.merge {
        meta_parts.push(format!("*{}", merge));
    }
    if let Some(ref dt) = e.data_type {
        meta_parts.push(format!(":{}", dt));
    }
    for a in &e.attrs {
        meta_parts.push(emit_attr(a));
    }
    let meta = if meta_parts.is_empty() {
        String::new()
    } else {
        format!(" {}", meta_parts.join(" "))
    };

    if is_multiline {
        let mut out = format!("{}[{}{}\n", ind, e.name, meta);
        for item in &e.items {
            out.push_str(&emit_node(item, depth + 1));
        }
        out.push_str(&format!("{}]\n", ind));
        return out;
    }

    if e.items.is_empty() && meta.is_empty() {
        return format!("{}[{}]\n", ind, e.name);
    }

    let body_parts: Vec<String> = e.items.iter()
        .map(emit_inline)
        .filter(|s| !s.is_empty())
        .collect();
    let body = body_parts.join(" ");
    let sep = if body.is_empty() { "" } else { " " };
    format!("{}[{}{}{}{}]\n", ind, e.name, meta, sep, body)
}

fn emit_node(node: &Node, depth: usize) -> String {
    let ind = "  ".repeat(depth);
    match node {
        Node::Element(e) => emit_element(e, depth),
        Node::Text(s) => cx_quote_text(s),
        Node::Scalar { data_type, value } => emit_scalar_value(data_type, value),
        Node::Comment(s) => format!("{}[-{}]\n", ind, s),
        Node::RawText(s) => format!("{}[#{}#]\n", ind, s),
        Node::EntityRef(name) => format!("&{};", name),
        Node::Alias(name) => format!("{}[*{}]\n", ind, name),
        Node::BlockContent(items) => {
            let inner: String = items.iter().map(|n| emit_node(n, 0)).collect();
            format!("{}[|{}|]\n", ind, inner)
        }
        Node::PI { target, data } => {
            let d = data.as_ref().map(|s| format!(" {}", s)).unwrap_or_default();
            format!("{}[?{}{}]\n", ind, target, d)
        }
        Node::XMLDecl { version, encoding, standalone } => {
            let mut parts = vec![format!("version={}", version)];
            if let Some(enc) = encoding {
                parts.push(format!("encoding={}", enc));
            }
            if let Some(sa) = standalone {
                parts.push(format!("standalone={}", sa));
            }
            format!("[?xml {}]\n", parts.join(" "))
        }
        Node::CXDirective(attrs) => {
            let attrs_str = attrs.iter().map(|a| {
                let v = match &a.value {
                    Value::String(s) => cx_quote_attr(s),
                    _ => a.value.to_string(),
                };
                format!("{}={}", a.name, v)
            }).collect::<Vec<_>>().join(" ");
            format!("[?cx {}]\n", attrs_str)
        }
        Node::DoctypeDecl { name, external_id, .. } => {
            let ext = match external_id {
                Some(Value::Object(map)) => {
                    if let Some(Value::String(pub_id)) = map.get("public") {
                        let sys = map.get("system")
                            .and_then(|v| v.as_str())
                            .unwrap_or("");
                        format!(" PUBLIC '{}' '{}'", pub_id, sys)
                    } else if let Some(Value::String(sys)) = map.get("system") {
                        format!(" SYSTEM '{}'", sys)
                    } else {
                        String::new()
                    }
                }
                _ => String::new(),
            };
            format!("[!DOCTYPE {}{}]\n", name, ext)
        }
    }
}

fn emit_doc(doc: &Document) -> String {
    let mut out = String::new();
    for node in &doc.prolog {
        out.push_str(&emit_node(node, 0));
    }
    for node in &doc.elements {
        out.push_str(&emit_node(node, 0));
    }
    // Strip trailing newlines like the Python implementation.
    let trimmed = out.trim_end_matches('\n');
    trimmed.to_string()
}
