//! CXPath parser, evaluator, and transform helpers.
//!
//! Ported from the Python reference implementation in lang/python/cxlib/cxpath.py.

use serde_json::Value;
use crate::ast::{Document, Element, Node};

// ── CXPath AST ────────────────────────────────────────────────────────────────

#[derive(Debug, Clone)]
pub enum CXPred {
    AttrExists(String),
    AttrCmp { attr: String, op: String, val: CXVal },
    ChildExists(String),
    Not(Box<CXPred>),
    BoolAnd(Box<CXPred>, Box<CXPred>),
    BoolOr(Box<CXPred>, Box<CXPred>),
    Position { pos: usize, is_last: bool },
    FuncContains { attr: String, val: String },
    FuncStartsWith { attr: String, val: String },
}

#[derive(Debug, Clone)]
pub enum CXVal {
    Bool(bool),
    Int(i64),
    Float(f64),
    Str(String),
    Null,
}

#[derive(Debug, Clone)]
pub struct CXStep {
    pub axis: Axis,
    pub name: String, // "" = wildcard
    pub preds: Vec<CXPred>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum Axis {
    Child,
    Descendant,
}

#[derive(Debug, Clone)]
pub struct CXPathExpr {
    pub steps: Vec<CXStep>,
}

// ── Lexer ─────────────────────────────────────────────────────────────────────

struct Lexer {
    src: Vec<char>,
    pos: usize,
}

impl Lexer {
    fn new(src: &str) -> Self {
        Lexer { src: src.chars().collect(), pos: 0 }
    }

    fn skip_ws(&mut self) {
        while self.pos < self.src.len() && self.src[self.pos] == ' ' {
            self.pos += 1;
        }
    }

    fn peek_str(&self, s: &str) -> bool {
        let chars: Vec<char> = s.chars().collect();
        if self.pos + chars.len() > self.src.len() {
            return false;
        }
        self.src[self.pos..self.pos + chars.len()] == chars[..]
    }

    fn eat_str(&mut self, s: &str) -> bool {
        if self.peek_str(s) {
            let n = s.chars().count();
            self.pos += n;
            true
        } else {
            false
        }
    }

    fn eat_char(&mut self, c: char) -> bool {
        if self.pos < self.src.len() && self.src[self.pos] == c {
            self.pos += 1;
            true
        } else {
            false
        }
    }

    fn read_ident(&mut self) -> String {
        let start = self.pos;
        while self.pos < self.src.len() {
            let c = self.src[self.pos];
            if c.is_alphanumeric() || "_-.:%".contains(c) {
                self.pos += 1;
            } else {
                break;
            }
        }
        self.src[start..self.pos].iter().collect()
    }

    fn read_quoted(&mut self) -> Result<String, String> {
        if !self.eat_char('\'') {
            return Err(format!("CXPath parse error: expected ' at pos {}  expr: {}", self.pos, self.src_str()));
        }
        let start = self.pos;
        while self.pos < self.src.len() && self.src[self.pos] != '\'' {
            self.pos += 1;
        }
        let s: String = self.src[start..self.pos].iter().collect();
        if !self.eat_char('\'') {
            return Err(format!("CXPath parse error: unterminated string at pos {}  expr: {}", self.pos, self.src_str()));
        }
        Ok(s)
    }

    fn src_str(&self) -> String {
        self.src.iter().collect()
    }
}

// ── Parser ────────────────────────────────────────────────────────────────────

pub fn cxpath_parse(expr: &str) -> Result<CXPathExpr, String> {
    let mut l = Lexer::new(expr);
    let steps = parse_steps(&mut l)?;
    if l.pos != l.src.len() {
        return Err(format!("CXPath parse error: unexpected characters at pos {}  expr: {}", l.pos, expr));
    }
    if steps.is_empty() {
        return Err(format!("CXPath parse error: empty expression  expr: {}", expr));
    }
    Ok(CXPathExpr { steps })
}

fn parse_steps(l: &mut Lexer) -> Result<Vec<CXStep>, String> {
    let mut steps = Vec::new();
    let axis = if l.eat_str("//") {
        Axis::Descendant
    } else {
        l.eat_str("/");
        Axis::Child
    };
    steps.push(parse_one_step(l, axis)?);
    loop {
        l.skip_ws();
        if l.eat_str("//") {
            steps.push(parse_one_step(l, Axis::Descendant)?);
        } else if l.eat_str("/") {
            steps.push(parse_one_step(l, Axis::Child)?);
        } else {
            break;
        }
    }
    Ok(steps)
}

fn parse_one_step(l: &mut Lexer, axis: Axis) -> Result<CXStep, String> {
    l.skip_ws();
    let name = if l.eat_char('*') {
        String::new()
    } else {
        let n = l.read_ident();
        if n.is_empty() {
            return Err(format!("CXPath parse error: expected element name at pos {}  expr: {}", l.pos, l.src_str()));
        }
        n
    };
    let mut preds = Vec::new();
    loop {
        l.skip_ws();
        if l.peek_str("[") {
            preds.push(parse_pred_bracket(l)?);
        } else {
            break;
        }
    }
    Ok(CXStep { axis, name, preds })
}

fn parse_pred_bracket(l: &mut Lexer) -> Result<CXPred, String> {
    if !l.eat_char('[') {
        return Err(format!("CXPath parse error: expected [ at pos {}  expr: {}", l.pos, l.src_str()));
    }
    l.skip_ws();
    let pred = parse_pred_expr(l)?;
    l.skip_ws();
    if !l.eat_char(']') {
        return Err(format!("CXPath parse error: expected ] at pos {}  expr: {}", l.pos, l.src_str()));
    }
    Ok(pred)
}

fn parse_pred_expr(l: &mut Lexer) -> Result<CXPred, String> {
    let left = parse_pred_term(l)?;
    l.skip_ws();
    let saved = l.pos;
    let word = l.read_ident();
    if word == "or" {
        l.skip_ws();
        let right = parse_pred_term(l)?;
        return Ok(CXPred::BoolOr(Box::new(left), Box::new(right)));
    }
    l.pos = saved;
    Ok(left)
}

fn parse_pred_term(l: &mut Lexer) -> Result<CXPred, String> {
    let left = parse_pred_factor(l)?;
    l.skip_ws();
    let saved = l.pos;
    let word = l.read_ident();
    if word == "and" {
        l.skip_ws();
        let right = parse_pred_factor(l)?;
        return Ok(CXPred::BoolAnd(Box::new(left), Box::new(right)));
    }
    l.pos = saved;
    Ok(left)
}

fn parse_pred_factor(l: &mut Lexer) -> Result<CXPred, String> {
    l.skip_ws();

    // not(...)
    if l.peek_str("not(") || l.peek_str("not (") {
        l.read_ident(); // consume 'not'
        l.skip_ws();
        if !l.eat_char('(') {
            return Err(format!("CXPath parse error: expected ( after not  expr: {}", l.src_str()));
        }
        l.skip_ws();
        let inner = parse_pred_expr(l)?;
        l.skip_ws();
        if !l.eat_char(')') {
            return Err(format!("CXPath parse error: expected ) after not(...)  expr: {}", l.src_str()));
        }
        return Ok(CXPred::Not(Box::new(inner)));
    }

    // contains(@attr, val)
    if l.peek_str("contains(") {
        l.read_ident(); // consume 'contains'
        l.skip_ws();
        if !l.eat_char('(') {
            return Err(format!("CXPath parse error: expected ( after contains  expr: {}", l.src_str()));
        }
        l.skip_ws();
        if !l.eat_char('@') {
            return Err(format!("CXPath parse error: expected @attr in contains()  expr: {}", l.src_str()));
        }
        let attr = l.read_ident();
        l.skip_ws();
        if !l.eat_char(',') {
            return Err(format!("CXPath parse error: expected , in contains()  expr: {}", l.src_str()));
        }
        l.skip_ws();
        let val = parse_scalar_str(l)?;
        l.skip_ws();
        if !l.eat_char(')') {
            return Err(format!("CXPath parse error: expected ) after contains(...)  expr: {}", l.src_str()));
        }
        return Ok(CXPred::FuncContains { attr, val });
    }

    // starts-with(@attr, val)
    if l.peek_str("starts-with(") {
        // advance past 'starts-with'
        while l.pos < l.src.len() && l.src[l.pos] != '(' {
            l.pos += 1;
        }
        if !l.eat_char('(') {
            return Err(format!("CXPath parse error: expected ( after starts-with  expr: {}", l.src_str()));
        }
        l.skip_ws();
        if !l.eat_char('@') {
            return Err(format!("CXPath parse error: expected @attr in starts-with()  expr: {}", l.src_str()));
        }
        let attr = l.read_ident();
        l.skip_ws();
        if !l.eat_char(',') {
            return Err(format!("CXPath parse error: expected , in starts-with()  expr: {}", l.src_str()));
        }
        l.skip_ws();
        let val = parse_scalar_str(l)?;
        l.skip_ws();
        if !l.eat_char(')') {
            return Err(format!("CXPath parse error: expected ) after starts-with(...)  expr: {}", l.src_str()));
        }
        return Ok(CXPred::FuncStartsWith { attr, val });
    }

    // last()
    if l.eat_str("last()") {
        return Ok(CXPred::Position { pos: 0, is_last: true });
    }

    // (grouped expr)
    if l.peek_str("(") {
        l.eat_char('(');
        l.skip_ws();
        let inner = parse_pred_expr(l)?;
        l.skip_ws();
        if !l.eat_char(')') {
            return Err(format!("CXPath parse error: expected ) at pos {}  expr: {}", l.pos, l.src_str()));
        }
        return Ok(inner);
    }

    // @attr comparison or existence
    if l.pos < l.src.len() && l.src[l.pos] == '@' {
        l.eat_char('@');
        let attr = l.read_ident();
        l.skip_ws();
        let op = parse_op(l);
        if op.is_empty() {
            return Ok(CXPred::AttrExists(attr));
        }
        l.skip_ws();
        let val = parse_scalar_val(l)?;
        return Ok(CXPred::AttrCmp { attr, op, val });
    }

    // integer position predicate
    if l.pos < l.src.len() && l.src[l.pos].is_ascii_digit() {
        let start = l.pos;
        while l.pos < l.src.len() && l.src[l.pos].is_ascii_digit() {
            l.pos += 1;
        }
        let s: String = l.src[start..l.pos].iter().collect();
        let n: usize = s.parse().map_err(|e| format!("CXPath parse error: {}", e))?;
        return Ok(CXPred::Position { pos: n, is_last: false });
    }

    // bare name → child existence
    let name = l.read_ident();
    if !name.is_empty() {
        return Ok(CXPred::ChildExists(name));
    }

    Err(format!("CXPath parse error: unexpected character at pos {}  expr: {}", l.pos, l.src_str()))
}

fn parse_op(l: &mut Lexer) -> String {
    for op in &["!=", ">=", "<=", "=", ">", "<"] {
        if l.eat_str(op) {
            return op.to_string();
        }
    }
    String::new()
}

fn autotype_value(s: &str) -> CXVal {
    if s == "true"  { return CXVal::Bool(true); }
    if s == "false" { return CXVal::Bool(false); }
    if s == "null"  { return CXVal::Null; }
    if let Ok(i) = s.parse::<i64>() { return CXVal::Int(i); }
    if let Ok(f) = s.parse::<f64>() { return CXVal::Float(f); }
    CXVal::Str(s.to_string())
}

fn parse_scalar_val(l: &mut Lexer) -> Result<CXVal, String> {
    if l.peek_str("'") {
        return Ok(CXVal::Str(l.read_quoted()?));
    }
    let s = l.read_ident();
    if s.is_empty() {
        return Err(format!("CXPath parse error: expected value at pos {}  expr: {}", l.pos, l.src_str()));
    }
    Ok(autotype_value(&s))
}

fn parse_scalar_str(l: &mut Lexer) -> Result<String, String> {
    if l.peek_str("'") {
        return l.read_quoted();
    }
    Ok(l.read_ident())
}

// ── Evaluator ─────────────────────────────────────────────────────────────────

/// Dispatch from context element into its children for the given step.
pub fn collect_step(ctx: &Element, expr: &CXPathExpr, step_idx: usize, result: &mut Vec<Element>) {
    if step_idx >= expr.steps.len() {
        return;
    }
    let step = &expr.steps[step_idx];
    if step.axis == Axis::Child {
        let candidates: Vec<Element> = ctx.items.iter().filter_map(|item| {
            if let Node::Element(e) = item {
                if step.name.is_empty() || e.name == step.name {
                    Some(e.clone())
                } else {
                    None
                }
            } else {
                None
            }
        }).collect();
        let is_last = step_idx == expr.steps.len() - 1;
        for (i, child) in candidates.iter().enumerate() {
            if preds_match(child, &step.preds, &candidates, i) {
                if is_last {
                    result.push(child.clone());
                } else {
                    collect_step(child, expr, step_idx + 1, result);
                }
            }
        }
    } else {
        collect_descendants(ctx, expr, step_idx, result);
    }
}

/// Descendant axis: match at every depth with proper sibling context for position preds.
fn collect_descendants(ctx: &Element, expr: &CXPathExpr, step_idx: usize, result: &mut Vec<Element>) {
    let step = &expr.steps[step_idx];
    let is_last = step_idx == expr.steps.len() - 1;

    let candidates: Vec<Element> = ctx.items.iter().filter_map(|item| {
        if let Node::Element(e) = item {
            if step.name.is_empty() || e.name == step.name {
                Some(e.clone())
            } else {
                None
            }
        } else {
            None
        }
    }).collect();

    for (i, child) in candidates.iter().enumerate() {
        if preds_match(child, &step.preds, &candidates, i) {
            if is_last {
                result.push(child.clone());
            } else {
                collect_step(child, expr, step_idx + 1, result);
            }
        }
        // Always recurse deeper (even after a match) for descendant axis
        collect_descendants(child, expr, step_idx, result);
    }

    // Also descend into non-matching children for named steps
    if !step.name.is_empty() {
        for item in &ctx.items {
            if let Node::Element(child) = item {
                if child.name != step.name {
                    collect_descendants(child, expr, step_idx, result);
                }
            }
        }
    }
}

// ── Predicate evaluators ──────────────────────────────────────────────────────

fn preds_match(el: &Element, preds: &[CXPred], siblings: &[Element], idx: usize) -> bool {
    preds.iter().all(|p| pred_eval(el, p, siblings, idx))
}

fn pred_eval(el: &Element, pred: &CXPred, siblings: &[Element], idx: usize) -> bool {
    match pred {
        CXPred::AttrExists(attr) => el.attr(attr).is_some(),
        CXPred::AttrCmp { attr, op, val } => {
            match el.attr(attr) {
                None => false,
                Some(v) => compare(v, op, val),
            }
        }
        CXPred::ChildExists(name) => el.get(name).is_some(),
        CXPred::Not(inner) => !pred_eval(el, inner, siblings, idx),
        CXPred::BoolAnd(left, right) => {
            pred_eval(el, left, siblings, idx) && pred_eval(el, right, siblings, idx)
        }
        CXPred::BoolOr(left, right) => {
            pred_eval(el, left, siblings, idx) || pred_eval(el, right, siblings, idx)
        }
        CXPred::Position { pos, is_last } => {
            if *is_last {
                idx == siblings.len().saturating_sub(1)
            } else {
                idx == pos.saturating_sub(1)
            }
        }
        CXPred::FuncContains { attr, val } => {
            match el.attr(attr) {
                None => false,
                Some(v) => val_to_str(v).contains(val.as_str()),
            }
        }
        CXPred::FuncStartsWith { attr, val } => {
            match el.attr(attr) {
                None => false,
                Some(v) => val_to_str(v).starts_with(val.as_str()),
            }
        }
    }
}

fn val_to_str(v: &Value) -> String {
    match v {
        Value::Null => "null".to_string(),
        Value::Bool(b) => if *b { "true".to_string() } else { "false".to_string() },
        Value::Number(n) => n.to_string(),
        Value::String(s) => s.clone(),
        _ => v.to_string(),
    }
}

fn scalar_eq(a: &Value, b: &CXVal) -> bool {
    match (a, b) {
        (Value::Bool(av), CXVal::Bool(bv)) => av == bv,
        (Value::Bool(_), _) => false,
        (_, CXVal::Bool(_)) => false,
        (Value::Null, CXVal::Null) => true,
        (Value::Null, _) => false,
        (_, CXVal::Null) => false,
        (Value::Number(an), CXVal::Int(bi)) => {
            an.as_f64().map(|f| f == *bi as f64).unwrap_or(false)
        }
        (Value::Number(an), CXVal::Float(bf)) => {
            an.as_f64().map(|f| (f - bf).abs() < f64::EPSILON).unwrap_or(false)
        }
        (Value::String(av), CXVal::Str(bv)) => av == bv,
        _ => false,
    }
}

fn to_f64_val(v: &Value) -> Result<f64, String> {
    match v {
        Value::Bool(_) => Err(format!("CXPath: numeric comparison requires numeric value, got bool: {}", v)),
        Value::Number(n) => n.as_f64().ok_or_else(|| format!("CXPath: cannot convert to f64: {}", n)),
        _ => Err(format!("CXPath: numeric comparison requires numeric attribute value, got: {}", v)),
    }
}

fn to_f64_cxval(v: &CXVal) -> Result<f64, String> {
    match v {
        CXVal::Int(i) => Ok(*i as f64),
        CXVal::Float(f) => Ok(*f),
        _ => Err(format!("CXPath: numeric comparison requires numeric value")),
    }
}

fn compare(actual: &Value, op: &str, expected: &CXVal) -> bool {
    if op == "=" {
        return scalar_eq(actual, expected);
    }
    if op == "!=" {
        return !scalar_eq(actual, expected);
    }
    let a = match to_f64_val(actual) { Ok(f) => f, Err(_) => return false };
    let b = match to_f64_cxval(expected) { Ok(f) => f, Err(_) => return false };
    match op {
        ">"  => a > b,
        "<"  => a < b,
        ">=" => a >= b,
        "<=" => a <= b,
        _ => false,
    }
}

// ── cxpath_elem_matches (for transform_all) ───────────────────────────────────

/// Check whether element matches the last step of expr (ignoring position preds).
pub fn cxpath_elem_matches(el: &Element, expr: &CXPathExpr) -> bool {
    if expr.steps.is_empty() {
        return false;
    }
    let last = &expr.steps[expr.steps.len() - 1];
    if !last.name.is_empty() && last.name != el.name {
        return false;
    }
    let non_pos: Vec<&CXPred> = last.preds.iter().filter(|p| {
        !matches!(p, CXPred::Position { .. })
    }).collect();
    non_pos.iter().all(|p| pred_eval(el, p, &[], 0))
}

// ── Transform helpers ─────────────────────────────────────────────────────────

/// Return a clone of e (independent attrs+items vecs).
pub fn elem_detached(e: &Element) -> Element {
    e.clone()
}

/// Return a new Document with element at idx replaced.
pub fn doc_replace_at(d: &Document, idx: usize, el: Element) -> Document {
    let new_elements: Vec<Node> = d.elements.iter().enumerate().map(|(i, n)| {
        if i == idx { Node::Element(el.clone()) } else { n.clone() }
    }).collect();
    Document { elements: new_elements, prolog: d.prolog.clone() }
}

/// Return a new Element with child node at idx replaced.
pub fn elem_replace_item_at(e: &Element, idx: usize, child: Node) -> Element {
    let new_items: Vec<Node> = e.items.iter().enumerate().map(|(i, n)| {
        if i == idx { child.clone() } else { n.clone() }
    }).collect();
    Element {
        name: e.name.clone(),
        anchor: e.anchor.clone(),
        merge: e.merge.clone(),
        data_type: e.data_type.clone(),
        attrs: e.attrs.clone(),
        items: new_items,
    }
}

/// Return a new Element with f applied at parts[...], or None if path not found.
pub fn path_copy_element(e: &Element, parts: &[&str], f: &dyn Fn(Element) -> Element) -> Option<Element> {
    for (i, item) in e.items.iter().enumerate() {
        if let Node::Element(child) = item {
            if child.name == parts[0] {
                if parts.len() == 1 {
                    let updated = f(elem_detached(child));
                    return Some(elem_replace_item_at(e, i, Node::Element(updated)));
                }
                let updated = path_copy_element(child, &parts[1..], f)?;
                return Some(elem_replace_item_at(e, i, Node::Element(updated)));
            }
        }
    }
    None
}

/// Recursively rebuild node tree, applying f to every element matching expr.
pub fn rebuild_node(node: &Node, expr: &CXPathExpr, f: &dyn Fn(Element) -> Element) -> Node {
    match node {
        Node::Element(el) => {
            let new_items: Vec<Node> = el.items.iter().map(|item| rebuild_node(item, expr, f)).collect();
            let new_el = Element {
                name: el.name.clone(),
                anchor: el.anchor.clone(),
                merge: el.merge.clone(),
                data_type: el.data_type.clone(),
                attrs: el.attrs.clone(),
                items: new_items,
            };
            if cxpath_elem_matches(&new_el, expr) {
                Node::Element(f(elem_detached(&new_el)))
            } else {
                Node::Element(new_el)
            }
        }
        other => other.clone(),
    }
}
