module cxlib

// ── Event types ───────────────────────────────────────────────────────────────

pub enum EventType {
	start_doc
	end_doc
	start_element
	end_element
	text
	scalar
	comment
	pi
	entity_ref
	raw_text
	alias_
}

pub struct StreamEvent {
pub:
	typ       EventType
	// StartElement
	name      string
	anchor    ?string
	data_type ?string // StartElement type annotation or Scalar data type
	merge     ?string
	attrs     []Attr
	// Text / Comment / RawText / EntityRef name / Alias name / Scalar raw string
	value     string
	// PI
	target    string
	data      ?string
}

pub fn (e StreamEvent) is_start_element(names ...string) bool {
	if e.typ != .start_element {
		return false
	}
	return names.len == 0 || e.name == names[0]
}

pub fn (e StreamEvent) is_end_element(names ...string) bool {
	if e.typ != .end_element {
		return false
	}
	return names.len == 0 || e.name == names[0]
}

// ── stream ────────────────────────────────────────────────────────────────────

// stream parses CX source and returns all events by walking the document tree.
pub fn stream(src string) ![]StreamEvent {
	doc := parse(src)!
	mut events := []StreamEvent{}
	events << StreamEvent{ typ: .start_doc }
	for n in doc.prolog   { collect_events(n, mut events) }
	for n in doc.elements { collect_events(n, mut events) }
	events << StreamEvent{ typ: .end_doc }
	return events
}

fn collect_events(n Node, mut events []StreamEvent) {
	match n {
		Element {
			events << StreamEvent{
				typ:       .start_element
				name:      n.name
				attrs:     n.attrs
				data_type: n.data_type
				anchor:    n.anchor
				merge:     n.merge
			}
			for child in n.items {
				collect_events(child, mut events)
			}
			events << StreamEvent{ typ: .end_element, name: n.name }
		}
		TextNode {
			events << StreamEvent{ typ: .text, value: n.value }
		}
		ScalarNode {
			events << StreamEvent{
				typ:       .scalar
				data_type: scalar_type_name(n.data_type)
				value:     n.value.str()
			}
		}
		CommentNode {
			events << StreamEvent{ typ: .comment, value: n.value }
		}
		RawTextNode {
			events << StreamEvent{ typ: .raw_text, value: n.value }
		}
		EntityRefNode {
			events << StreamEvent{ typ: .entity_ref, value: n.name }
		}
		AliasNode {
			events << StreamEvent{ typ: .alias_, value: n.name }
		}
		PINode {
			events << StreamEvent{ typ: .pi, target: n.target, data: n.data }
		}
		BlockContentNode {
			for item in n.items {
				collect_events(item, mut events)
			}
		}
		else {}
	}
}
