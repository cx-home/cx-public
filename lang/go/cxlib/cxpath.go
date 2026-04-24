// Package cxlib — CXPath parser, evaluator, and transform helpers.
package cxlib

import (
	"fmt"
	"strconv"
	"strings"
)

// ── CXPath predicate types ────────────────────────────────────────────────────

type cxPredAttrExists struct{ attr string }
type cxPredAttrCmp struct {
	attr string
	op   string
	val  any
}
type cxPredChildExists struct{ name string }
type cxPredNot struct{ inner any }
type cxPredBoolAnd struct{ left, right any }
type cxPredBoolOr struct{ left, right any }
type cxPredPosition struct {
	pos    int
	isLast bool
}
type cxPredFuncContains struct{ attr, val string }
type cxPredFuncStartsWith struct{ attr, val string }

// ── CXPath AST ────────────────────────────────────────────────────────────────

type cxStep struct {
	axis  string // "child" | "descendant"
	name  string // "" = wildcard (*)
	preds []any
}

type cxPathExpr struct {
	steps []cxStep
}

// ── Lexer ─────────────────────────────────────────────────────────────────────

type cxLexer struct {
	src string
	pos int
}

func (l *cxLexer) skipWS() {
	for l.pos < len(l.src) && l.src[l.pos] == ' ' {
		l.pos++
	}
}

func (l *cxLexer) peekStr(s string) bool {
	return strings.HasPrefix(l.src[l.pos:], s)
}

func (l *cxLexer) eatStr(s string) bool {
	if l.peekStr(s) {
		l.pos += len(s)
		return true
	}
	return false
}

func (l *cxLexer) eatChar(c byte) bool {
	if l.pos < len(l.src) && l.src[l.pos] == c {
		l.pos++
		return true
	}
	return false
}

func (l *cxLexer) readIdent() string {
	start := l.pos
	for l.pos < len(l.src) {
		c := l.src[l.pos]
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
			c == '_' || c == '-' || c == '.' || c == ':' || c == '%' {
			l.pos++
		} else {
			break
		}
	}
	return l.src[start:l.pos]
}

func (l *cxLexer) readQuoted() (string, error) {
	if !l.eatChar('\'') {
		return "", fmt.Errorf("CXPath parse error: expected ' at pos %d  expr: %s", l.pos, l.src)
	}
	start := l.pos
	for l.pos < len(l.src) && l.src[l.pos] != '\'' {
		l.pos++
	}
	s := l.src[start:l.pos]
	if !l.eatChar('\'') {
		return "", fmt.Errorf("CXPath parse error: unterminated string at pos %d  expr: %s", l.pos, l.src)
	}
	return s, nil
}

// ── Parser ────────────────────────────────────────────────────────────────────

func cxpathParse(expr string) (*cxPathExpr, error) {
	l := &cxLexer{src: expr}
	steps, err := parseSteps(l)
	if err != nil {
		return nil, err
	}
	if l.pos != len(l.src) {
		return nil, fmt.Errorf("CXPath parse error: unexpected characters at pos %d  expr: %s", l.pos, expr)
	}
	if len(steps) == 0 {
		return nil, fmt.Errorf("CXPath parse error: empty expression  expr: %s", expr)
	}
	return &cxPathExpr{steps: steps}, nil
}

func parseSteps(l *cxLexer) ([]cxStep, error) {
	var steps []cxStep
	axis := "child"
	if l.peekStr("//") {
		l.pos += 2
		axis = "descendant"
	} else if l.peekStr("/") {
		l.pos++
		axis = "child"
	}
	step, err := parseOneStep(l, axis)
	if err != nil {
		return nil, err
	}
	steps = append(steps, step)
	for {
		l.skipWS()
		if l.peekStr("//") {
			l.pos += 2
			s, err := parseOneStep(l, "descendant")
			if err != nil {
				return nil, err
			}
			steps = append(steps, s)
		} else if l.peekStr("/") {
			l.pos++
			s, err := parseOneStep(l, "child")
			if err != nil {
				return nil, err
			}
			steps = append(steps, s)
		} else {
			break
		}
	}
	return steps, nil
}

func parseOneStep(l *cxLexer, axis string) (cxStep, error) {
	l.skipWS()
	var name string
	if l.eatChar('*') {
		name = ""
	} else {
		name = l.readIdent()
		if name == "" {
			return cxStep{}, fmt.Errorf("CXPath parse error: expected element name at pos %d  expr: %s", l.pos, l.src)
		}
	}
	var preds []any
	for {
		l.skipWS()
		if l.peekStr("[") {
			pred, err := parsePredBracket(l)
			if err != nil {
				return cxStep{}, err
			}
			preds = append(preds, pred)
		} else {
			break
		}
	}
	return cxStep{axis: axis, name: name, preds: preds}, nil
}

func parsePredBracket(l *cxLexer) (any, error) {
	if !l.eatChar('[') {
		return nil, fmt.Errorf("CXPath parse error: expected [ at pos %d  expr: %s", l.pos, l.src)
	}
	l.skipWS()
	pred, err := parsePredExpr(l)
	if err != nil {
		return nil, err
	}
	l.skipWS()
	if !l.eatChar(']') {
		return nil, fmt.Errorf("CXPath parse error: expected ] at pos %d  expr: %s", l.pos, l.src)
	}
	return pred, nil
}

func parsePredExpr(l *cxLexer) (any, error) {
	left, err := parsePredTerm(l)
	if err != nil {
		return nil, err
	}
	l.skipWS()
	saved := l.pos
	word := l.readIdent()
	if word == "or" {
		l.skipWS()
		right, err := parsePredTerm(l)
		if err != nil {
			return nil, err
		}
		return cxPredBoolOr{left: left, right: right}, nil
	}
	l.pos = saved
	return left, nil
}

func parsePredTerm(l *cxLexer) (any, error) {
	left, err := parsePredFactor(l)
	if err != nil {
		return nil, err
	}
	l.skipWS()
	saved := l.pos
	word := l.readIdent()
	if word == "and" {
		l.skipWS()
		right, err := parsePredFactor(l)
		if err != nil {
			return nil, err
		}
		return cxPredBoolAnd{left: left, right: right}, nil
	}
	l.pos = saved
	return left, nil
}

func parsePredFactor(l *cxLexer) (any, error) {
	l.skipWS()

	// not(...)
	if l.peekStr("not(") || l.peekStr("not (") {
		l.readIdent() // consume 'not'
		l.skipWS()
		if !l.eatChar('(') {
			return nil, fmt.Errorf("CXPath parse error: expected ( after not  expr: %s", l.src)
		}
		l.skipWS()
		inner, err := parsePredExpr(l)
		if err != nil {
			return nil, err
		}
		l.skipWS()
		if !l.eatChar(')') {
			return nil, fmt.Errorf("CXPath parse error: expected ) after not(...)  expr: %s", l.src)
		}
		return cxPredNot{inner: inner}, nil
	}

	// contains(@attr, val)
	if l.peekStr("contains(") {
		l.readIdent() // consume 'contains'
		l.skipWS()
		if !l.eatChar('(') {
			return nil, fmt.Errorf("CXPath parse error: expected ( after contains  expr: %s", l.src)
		}
		l.skipWS()
		if !l.eatChar('@') {
			return nil, fmt.Errorf("CXPath parse error: expected @attr in contains()  expr: %s", l.src)
		}
		attr := l.readIdent()
		l.skipWS()
		if !l.eatChar(',') {
			return nil, fmt.Errorf("CXPath parse error: expected , in contains()  expr: %s", l.src)
		}
		l.skipWS()
		val, err := parseScalarStr(l)
		if err != nil {
			return nil, err
		}
		l.skipWS()
		if !l.eatChar(')') {
			return nil, fmt.Errorf("CXPath parse error: expected ) after contains(...)  expr: %s", l.src)
		}
		return cxPredFuncContains{attr: attr, val: val}, nil
	}

	// starts-with(@attr, val)
	if l.peekStr("starts-with(") {
		// advance past 'starts-with'
		for l.pos < len(l.src) && l.src[l.pos] != '(' {
			l.pos++
		}
		if !l.eatChar('(') {
			return nil, fmt.Errorf("CXPath parse error: expected ( after starts-with  expr: %s", l.src)
		}
		l.skipWS()
		if !l.eatChar('@') {
			return nil, fmt.Errorf("CXPath parse error: expected @attr in starts-with()  expr: %s", l.src)
		}
		attr := l.readIdent()
		l.skipWS()
		if !l.eatChar(',') {
			return nil, fmt.Errorf("CXPath parse error: expected , in starts-with()  expr: %s", l.src)
		}
		l.skipWS()
		val, err := parseScalarStr(l)
		if err != nil {
			return nil, err
		}
		l.skipWS()
		if !l.eatChar(')') {
			return nil, fmt.Errorf("CXPath parse error: expected ) after starts-with(...)  expr: %s", l.src)
		}
		return cxPredFuncStartsWith{attr: attr, val: val}, nil
	}

	// last()
	if l.peekStr("last()") {
		l.pos += 6
		return cxPredPosition{isLast: true}, nil
	}

	// (grouped expr)
	if l.pos < len(l.src) && l.src[l.pos] == '(' {
		l.eatChar('(')
		l.skipWS()
		inner, err := parsePredExpr(l)
		if err != nil {
			return nil, err
		}
		l.skipWS()
		if !l.eatChar(')') {
			return nil, fmt.Errorf("CXPath parse error: expected ) at pos %d  expr: %s", l.pos, l.src)
		}
		return inner, nil
	}

	// @attr comparison or existence
	if l.pos < len(l.src) && l.src[l.pos] == '@' {
		l.eatChar('@')
		attr := l.readIdent()
		l.skipWS()
		op := parseOp(l)
		if op == "" {
			return cxPredAttrExists{attr: attr}, nil
		}
		l.skipWS()
		val, err := parseScalarVal(l)
		if err != nil {
			return nil, err
		}
		return cxPredAttrCmp{attr: attr, op: op, val: val}, nil
	}

	// integer position predicate
	if l.pos < len(l.src) && l.src[l.pos] >= '0' && l.src[l.pos] <= '9' {
		start := l.pos
		for l.pos < len(l.src) && l.src[l.pos] >= '0' && l.src[l.pos] <= '9' {
			l.pos++
		}
		n, _ := strconv.Atoi(l.src[start:l.pos])
		return cxPredPosition{pos: n}, nil
	}

	// bare name → child existence
	name := l.readIdent()
	if name != "" {
		return cxPredChildExists{name: name}, nil
	}

	return nil, fmt.Errorf("CXPath parse error: unexpected character at pos %d  expr: %s", l.pos, l.src)
}

func parseOp(l *cxLexer) string {
	for _, op := range []string{"!=", ">=", "<=", "=", ">", "<"} {
		if l.eatStr(op) {
			return op
		}
	}
	return ""
}

func autotypeValue(s string) any {
	if s == "true" {
		return true
	}
	if s == "false" {
		return false
	}
	if s == "null" {
		return nil
	}
	if i, err := strconv.ParseInt(s, 10, 64); err == nil {
		return i
	}
	if f, err := strconv.ParseFloat(s, 64); err == nil {
		return f
	}
	return s
}

func parseScalarVal(l *cxLexer) (any, error) {
	if l.peekStr("'") {
		s, err := l.readQuoted()
		if err != nil {
			return nil, err
		}
		return s, nil
	}
	s := l.readIdent()
	if s == "" {
		return nil, fmt.Errorf("CXPath parse error: expected value at pos %d  expr: %s", l.pos, l.src)
	}
	return autotypeValue(s), nil
}

func parseScalarStr(l *cxLexer) (string, error) {
	if l.peekStr("'") {
		return l.readQuoted()
	}
	return l.readIdent(), nil
}

// ── Evaluator ─────────────────────────────────────────────────────────────────

// collectStep dispatches from context element into its children for the given step.
func collectStep(ctx *Element, expr *cxPathExpr, stepIdx int, result *[]*Element) {
	if stepIdx >= len(expr.steps) {
		return
	}
	step := expr.steps[stepIdx]
	if step.axis == "child" {
		var candidates []*Element
		for _, item := range ctx.Items {
			if el, ok := item.(*Element); ok && (step.name == "" || el.Name == step.name) {
				candidates = append(candidates, el)
			}
		}
		isLast := stepIdx == len(expr.steps)-1
		for i, child := range candidates {
			if predsMatch(child, step.preds, candidates, i) {
				if isLast {
					*result = append(*result, child)
				} else {
					collectStep(child, expr, stepIdx+1, result)
				}
			}
		}
	} else {
		collectDescendants(ctx, expr, stepIdx, result)
	}
}

// collectDescendants handles the descendant axis with proper sibling context for position predicates.
func collectDescendants(ctx *Element, expr *cxPathExpr, stepIdx int, result *[]*Element) {
	step := expr.steps[stepIdx]
	isLast := stepIdx == len(expr.steps)-1

	var candidates []*Element
	for _, item := range ctx.Items {
		if el, ok := item.(*Element); ok && (step.name == "" || el.Name == step.name) {
			candidates = append(candidates, el)
		}
	}
	for i, child := range candidates {
		if predsMatch(child, step.preds, candidates, i) {
			if isLast {
				*result = append(*result, child)
			} else {
				collectStep(child, expr, stepIdx+1, result)
			}
		}
		// Always recurse deeper (even after a match) for descendant axis
		collectDescendants(child, expr, stepIdx, result)
	}
	// Also descend into non-matching children for named steps (not needed for wildcard)
	if step.name != "" {
		for _, item := range ctx.Items {
			if el, ok := item.(*Element); ok && el.Name != step.name {
				collectDescendants(el, expr, stepIdx, result)
			}
		}
	}
}

// ── Predicate evaluators ──────────────────────────────────────────────────────

func predsMatch(el *Element, preds []any, siblings []*Element, idx int) bool {
	for _, p := range preds {
		if !predEval(el, p, siblings, idx) {
			return false
		}
	}
	return true
}

func predEval(el *Element, pred any, siblings []*Element, idx int) bool {
	switch p := pred.(type) {
	case cxPredAttrExists:
		return el.Attr(p.attr) != nil
	case cxPredAttrCmp:
		v := el.Attr(p.attr)
		if v == nil {
			return false
		}
		return cxCompare(v, p.op, p.val)
	case cxPredChildExists:
		return el.Get(p.name) != nil
	case cxPredNot:
		return !predEval(el, p.inner, siblings, idx)
	case cxPredBoolAnd:
		return predEval(el, p.left, siblings, idx) && predEval(el, p.right, siblings, idx)
	case cxPredBoolOr:
		return predEval(el, p.left, siblings, idx) || predEval(el, p.right, siblings, idx)
	case cxPredPosition:
		if p.isLast {
			return idx == len(siblings)-1
		}
		return idx == p.pos-1
	case cxPredFuncContains:
		v := el.Attr(p.attr)
		if v == nil {
			return false
		}
		return strings.Contains(valToStr(v), p.val)
	case cxPredFuncStartsWith:
		v := el.Attr(p.attr)
		if v == nil {
			return false
		}
		return strings.HasPrefix(valToStr(v), p.val)
	}
	return false
}

func valToStr(v any) string {
	if v == nil {
		return "null"
	}
	if b, ok := v.(bool); ok {
		if b {
			return "true"
		}
		return "false"
	}
	return fmt.Sprintf("%v", v)
}

func scalarEq(a, b any) bool {
	// Guard against cross-type bool/int matches
	_, aBool := a.(bool)
	_, bBool := b.(bool)
	if aBool != bBool {
		return false
	}
	// Numeric: compare as float64
	af, aIsNum := toF64(a)
	bf, bIsNum := toF64(b)
	if aIsNum && bIsNum {
		return af == bf
	}
	return a == b
}

func toF64(v any) (float64, bool) {
	switch n := v.(type) {
	case int64:
		return float64(n), true
	case float64:
		return n, true
	}
	return 0, false
}

func cxCompare(actual any, op string, expected any) bool {
	switch op {
	case "=":
		return scalarEq(actual, expected)
	case "!=":
		return !scalarEq(actual, expected)
	}
	// Numeric comparison
	a, aOk := toF64(actual)
	b, bOk := toF64(expected)
	if !aOk || !bOk {
		return false
	}
	switch op {
	case ">":
		return a > b
	case "<":
		return a < b
	case ">=":
		return a >= b
	case "<=":
		return a <= b
	}
	return false
}

// ── cxpathElemMatches (for TransformAll) ─────────────────────────────────────

// cxpathElemMatches checks whether el matches the last step of expr (ignoring position predicates).
func cxpathElemMatches(el *Element, expr *cxPathExpr) bool {
	if len(expr.steps) == 0 {
		return false
	}
	last := expr.steps[len(expr.steps)-1]
	if last.name != "" && last.name != el.Name {
		return false
	}
	var nonPos []any
	for _, p := range last.preds {
		if _, ok := p.(cxPredPosition); !ok {
			nonPos = append(nonPos, p)
		}
	}
	return predsMatch(el, nonPos, nil, 0)
}

// ── Transform helpers ─────────────────────────────────────────────────────────

// elemDetached returns a copy of e with independent attrs and items slices.
func elemDetached(e *Element) *Element {
	newAttrs := make([]Attr, len(e.Attrs))
	copy(newAttrs, e.Attrs)
	newItems := make([]Node, len(e.Items))
	copy(newItems, e.Items)
	return &Element{
		Name:     e.Name,
		Anchor:   e.Anchor,
		Merge:    e.Merge,
		DataType: e.DataType,
		Attrs:    newAttrs,
		Items:    newItems,
	}
}

// docReplaceAt returns a new Document with element at idx replaced by el.
func docReplaceAt(d *Document, idx int, el *Element) *Document {
	newElements := make([]Node, len(d.Elements))
	copy(newElements, d.Elements)
	newElements[idx] = el
	return &Document{Elements: newElements, Prolog: d.Prolog, Doctype: d.Doctype}
}

// elemReplaceItemAt returns a new Element with item at idx replaced by child.
func elemReplaceItemAt(e *Element, idx int, child Node) *Element {
	newItems := make([]Node, len(e.Items))
	copy(newItems, e.Items)
	newItems[idx] = child
	return &Element{
		Name:     e.Name,
		Anchor:   e.Anchor,
		Merge:    e.Merge,
		DataType: e.DataType,
		Attrs:    e.Attrs,
		Items:    newItems,
	}
}

// pathCopyElement returns a new Element with f applied at the path given by parts, or nil if not found.
func pathCopyElement(e *Element, parts []string, f func(*Element) *Element) *Element {
	for i, item := range e.Items {
		if el, ok := item.(*Element); ok && el.Name == parts[0] {
			if len(parts) == 1 {
				return elemReplaceItemAt(e, i, f(elemDetached(el)))
			}
			updated := pathCopyElement(el, parts[1:], f)
			if updated != nil {
				return elemReplaceItemAt(e, i, updated)
			}
			return nil
		}
	}
	return nil
}

// rebuildNode recursively rebuilds the node tree, applying f to every element matching expr.
func rebuildNode(node Node, expr *cxPathExpr, f func(*Element) *Element) Node {
	el, ok := node.(*Element)
	if !ok {
		return node
	}
	newItems := make([]Node, len(el.Items))
	for i, item := range el.Items {
		newItems[i] = rebuildNode(item, expr, f)
	}
	newEl := &Element{
		Name:     el.Name,
		Anchor:   el.Anchor,
		Merge:    el.Merge,
		DataType: el.DataType,
		Attrs:    el.Attrs,
		Items:    newItems,
	}
	if cxpathElemMatches(newEl, expr) {
		return f(elemDetached(newEl))
	}
	return newEl
}
