module cxlib

// transform returns a new Document with the element at `path` replaced by
// f(original). If the path does not exist, returns the original document
// unchanged. Path format: "a/b/c" (leading slash stripped).
pub fn (d Document) transform(path string, f fn (Element) Element) Document {
	parts := path.split('/').filter(it.len > 0)
	if parts.len == 0 {
		return d
	}
	for i, node in d.elements {
		if node is Element && node.name == parts[0] {
			if parts.len == 1 {
				return doc_replace_element_at(d, i, f(elem_detached(node)))
			}
			if updated := path_copy_element(node, parts[1..], f) {
				return doc_replace_element_at(d, i, updated)
			}
			return d
		}
	}
	return d
}

// elem_detached returns an element with its own backing arrays for attrs and items,
// preventing set_attr in transform functions from mutating the source document.
fn elem_detached(e Element) Element {
	return Element{
		name:      e.name
		anchor:    e.anchor
		merge:     e.merge
		data_type: e.data_type
		attrs:     e.attrs.clone()
		items:     e.items
	}
}

fn doc_replace_element_at(d Document, idx int, el Element) Document {
	mut new_elements := []Node{cap: d.elements.len}
	for i, n in d.elements {
		if i == idx {
			new_elements << Node(el)
		} else {
			new_elements << n
		}
	}
	return Document{
		prolog:   d.prolog
		doctype:  d.doctype
		elements: new_elements
	}
}

fn path_copy_element(e Element, parts []string, f fn (Element) Element) ?Element {
	for i, item in e.items {
		if item is Element && item.name == parts[0] {
			if parts.len == 1 {
				return elem_replace_item_at(e, i, f(elem_detached(item)))
			}
			if updated := path_copy_element(item, parts[1..], f) {
				return elem_replace_item_at(e, i, updated)
			}
			return none
		}
	}
	return none
}

fn elem_replace_item_at(e Element, idx int, child Element) Element {
	mut new_items := []Node{cap: e.items.len}
	for i, n in e.items {
		if i == idx {
			new_items << Node(child)
		} else {
			new_items << n
		}
	}
	return Element{
		name:      e.name
		anchor:    e.anchor
		merge:     e.merge
		data_type: e.data_type
		attrs:     e.attrs
		items:     new_items
	}
}

// transform_all applies f to every element matching the CXPath expression and
// returns a new Document. If no elements match, returns the original document
// unchanged. Invalid expressions panic.
pub fn (d Document) transform_all(expr string, f fn (Element) Element) Document {
	cx_expr := cxpath_parse(expr)
	mut new_elements := []Node{cap: d.elements.len}
	for node in d.elements {
		new_elements << transform_rebuild_node(node, cx_expr, f)
	}
	return Document{
		prolog:   d.prolog
		doctype:  d.doctype
		elements: new_elements
	}
}

fn transform_rebuild_node(node Node, expr CXPathExpr, f fn (Element) Element) Node {
	if node !is Element {
		return node
	}
	el := node as Element
	mut new_items := []Node{cap: el.items.len}
	for item in el.items {
		new_items << transform_rebuild_node(item, expr, f)
	}
	new_el := Element{
		name:      el.name
		anchor:    el.anchor
		merge:     el.merge
		data_type: el.data_type
		attrs:     el.attrs
		items:     new_items
	}
	if cxpath_elem_matches(new_el, expr) {
		return Node(f(elem_detached(new_el)))
	}
	return Node(new_el)
}
