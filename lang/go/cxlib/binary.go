package cxlib

import (
	"encoding/binary"
	"fmt"
)

// StreamEvent represents a single CX streaming event.
type StreamEvent struct {
	Type     string
	Name     string
	Anchor   *string
	DataType *string
	Merge    *string
	Attrs    []Attr
	Value    any
	Target   string
	Data     *string
}

// ── buffer reader ─────────────────────────────────────────────────────────────

type binBuf struct {
	data []byte
	pos  int
}

func (b *binBuf) u8() (uint8, error) {
	if b.pos >= len(b.data) {
		return 0, fmt.Errorf("binary decode: unexpected end of data reading u8")
	}
	v := b.data[b.pos]
	b.pos++
	return v, nil
}

func (b *binBuf) u16() (uint16, error) {
	if b.pos+2 > len(b.data) {
		return 0, fmt.Errorf("binary decode: unexpected end of data reading u16")
	}
	v := binary.LittleEndian.Uint16(b.data[b.pos:])
	b.pos += 2
	return v, nil
}

func (b *binBuf) u32() (uint32, error) {
	if b.pos+4 > len(b.data) {
		return 0, fmt.Errorf("binary decode: unexpected end of data reading u32")
	}
	v := binary.LittleEndian.Uint32(b.data[b.pos:])
	b.pos += 4
	return v, nil
}

func (b *binBuf) str() (string, error) {
	n, err := b.u32()
	if err != nil {
		return "", err
	}
	if b.pos+int(n) > len(b.data) {
		return "", fmt.Errorf("binary decode: unexpected end of data reading string of length %d", n)
	}
	s := string(b.data[b.pos : b.pos+int(n)])
	b.pos += int(n)
	return s, nil
}

func (b *binBuf) optstr() (*string, error) {
	flag, err := b.u8()
	if err != nil {
		return nil, err
	}
	if flag == 0 {
		return nil, nil
	}
	s, err := b.str()
	if err != nil {
		return nil, err
	}
	return &s, nil
}

// ── scalar coercion ───────────────────────────────────────────────────────────

func coerceAttrValue(typeStr, valueStr string) any {
	switch typeStr {
	case "int":
		var v int64
		fmt.Sscan(valueStr, &v)
		return v
	case "float":
		var v float64
		fmt.Sscan(valueStr, &v)
		return v
	case "bool":
		return valueStr == "true"
	case "null":
		return nil
	default:
		return valueStr
	}
}

// ── AST decoder ───────────────────────────────────────────────────────────────

func readAttr(b *binBuf) (Attr, error) {
	name, err := b.str()
	if err != nil {
		return Attr{}, err
	}
	valueStr, err := b.str()
	if err != nil {
		return Attr{}, err
	}
	typeStr, err := b.str()
	if err != nil {
		return Attr{}, err
	}
	dt := typeStr
	if typeStr == "string" {
		dt = ""
	}
	return Attr{
		Name:     name,
		Value:    coerceAttrValue(typeStr, valueStr),
		DataType: dt,
	}, nil
}

func readNode(b *binBuf) (Node, error) {
	tid, err := b.u8()
	if err != nil {
		return nil, err
	}
	switch tid {
	case 0x01: // Element
		name, err := b.str()
		if err != nil {
			return nil, err
		}
		anchor, err := b.optstr()
		if err != nil {
			return nil, err
		}
		dataType, err := b.optstr()
		if err != nil {
			return nil, err
		}
		merge, err := b.optstr()
		if err != nil {
			return nil, err
		}
		attrCount, err := b.u16()
		if err != nil {
			return nil, err
		}
		attrs := make([]Attr, 0, attrCount)
		for i := uint16(0); i < attrCount; i++ {
			a, err := readAttr(b)
			if err != nil {
				return nil, err
			}
			attrs = append(attrs, a)
		}
		childCount, err := b.u16()
		if err != nil {
			return nil, err
		}
		items := make([]Node, 0, childCount)
		for i := uint16(0); i < childCount; i++ {
			child, err := readNode(b)
			if err != nil {
				return nil, err
			}
			items = append(items, child)
		}
		el := &Element{Name: name, Attrs: attrs, Items: items}
		if anchor != nil {
			el.Anchor = *anchor
		}
		if dataType != nil {
			el.DataType = *dataType
		}
		if merge != nil {
			el.Merge = *merge
		}
		return el, nil

	case 0x02: // Text
		v, err := b.str()
		if err != nil {
			return nil, err
		}
		return &TextNode{Value: v}, nil

	case 0x03: // Scalar
		typeStr, err := b.str()
		if err != nil {
			return nil, err
		}
		valueStr, err := b.str()
		if err != nil {
			return nil, err
		}
		return &ScalarNode{DataType: typeStr, Value: coerceAttrValue(typeStr, valueStr)}, nil

	case 0x04: // Comment
		v, err := b.str()
		if err != nil {
			return nil, err
		}
		return &CommentNode{Value: v}, nil

	case 0x05: // RawText
		v, err := b.str()
		if err != nil {
			return nil, err
		}
		return &RawTextNode{Value: v}, nil

	case 0x06: // EntityRef
		name, err := b.str()
		if err != nil {
			return nil, err
		}
		return &EntityRefNode{Name: name}, nil

	case 0x07: // Alias
		name, err := b.str()
		if err != nil {
			return nil, err
		}
		return &AliasNode{Name: name}, nil

	case 0x08: // PI
		target, err := b.str()
		if err != nil {
			return nil, err
		}
		data, err := b.optstr()
		if err != nil {
			return nil, err
		}
		pi := &PINode{Target: target}
		if data != nil {
			pi.Data = *data
		}
		return pi, nil

	case 0x09: // XMLDecl
		version, err := b.str()
		if err != nil {
			return nil, err
		}
		encoding, err := b.optstr()
		if err != nil {
			return nil, err
		}
		standalone, err := b.optstr()
		if err != nil {
			return nil, err
		}
		node := &XMLDeclNode{Version: version}
		if encoding != nil {
			node.Encoding = *encoding
		}
		if standalone != nil {
			node.Standalone = *standalone
		}
		return node, nil

	case 0x0A: // CXDirective
		count, err := b.u16()
		if err != nil {
			return nil, err
		}
		attrs := make([]Attr, 0, count)
		for i := uint16(0); i < count; i++ {
			a, err := readAttr(b)
			if err != nil {
				return nil, err
			}
			attrs = append(attrs, a)
		}
		return &CXDirectiveNode{Attrs: attrs}, nil

	case 0x0C: // BlockContent
		count, err := b.u16()
		if err != nil {
			return nil, err
		}
		items := make([]Node, 0, count)
		for i := uint16(0); i < count; i++ {
			child, err := readNode(b)
			if err != nil {
				return nil, err
			}
			items = append(items, child)
		}
		return &BlockContentNode{Items: items}, nil

	case 0xFF: // skip — no payload
		return &TextNode{Value: ""}, nil

	default:
		return &TextNode{Value: ""}, nil
	}
}

// decodeAST decodes a binary AST payload into a Document.
func decodeAST(data []byte) (*Document, error) {
	b := &binBuf{data: data}

	// version byte
	_, err := b.u8()
	if err != nil {
		return nil, err
	}

	prologCount, err := b.u16()
	if err != nil {
		return nil, err
	}
	prolog := make([]Node, 0, prologCount)
	for i := uint16(0); i < prologCount; i++ {
		node, err := readNode(b)
		if err != nil {
			return nil, err
		}
		prolog = append(prolog, node)
	}

	elemCount, err := b.u16()
	if err != nil {
		return nil, err
	}
	elements := make([]Node, 0, elemCount)
	for i := uint16(0); i < elemCount; i++ {
		node, err := readNode(b)
		if err != nil {
			return nil, err
		}
		elements = append(elements, node)
	}

	return &Document{Prolog: prolog, Elements: elements}, nil
}

// ── Events decoder ────────────────────────────────────────────────────────────

var evtTypeNames = map[uint8]string{
	0x01: "StartDoc",
	0x02: "EndDoc",
	0x03: "StartElement",
	0x04: "EndElement",
	0x05: "Text",
	0x06: "Scalar",
	0x07: "Comment",
	0x08: "PI",
	0x09: "EntityRef",
	0x0A: "RawText",
	0x0B: "Alias",
}

// decodeEvents decodes a binary events payload into a slice of StreamEvent.
func decodeEvents(data []byte) ([]StreamEvent, error) {
	b := &binBuf{data: data}

	count, err := b.u32()
	if err != nil {
		return nil, err
	}

	events := make([]StreamEvent, 0, count)
	for i := uint32(0); i < count; i++ {
		tid, err := b.u8()
		if err != nil {
			return nil, err
		}
		typeName, ok := evtTypeNames[tid]
		if !ok {
			typeName = "Unknown"
		}
		evt := StreamEvent{Type: typeName}

		switch tid {
		case 0x03: // StartElement
			name, err := b.str()
			if err != nil {
				return nil, err
			}
			anchor, err := b.optstr()
			if err != nil {
				return nil, err
			}
			dataType, err := b.optstr()
			if err != nil {
				return nil, err
			}
			merge, err := b.optstr()
			if err != nil {
				return nil, err
			}
			attrCount, err := b.u16()
			if err != nil {
				return nil, err
			}
			attrs := make([]Attr, 0, attrCount)
			for j := uint16(0); j < attrCount; j++ {
				attrName, err := b.str()
				if err != nil {
					return nil, err
				}
				valStr, err := b.str()
				if err != nil {
					return nil, err
				}
				typStr, err := b.str()
				if err != nil {
					return nil, err
				}
				dt := typStr
				if typStr == "string" {
					dt = ""
				}
				attrs = append(attrs, Attr{
					Name:     attrName,
					Value:    coerceAttrValue(typStr, valStr),
					DataType: dt,
				})
			}
			evt.Name = name
			evt.Anchor = anchor
			evt.DataType = dataType
			evt.Merge = merge
			evt.Attrs = attrs

		case 0x04: // EndElement
			name, err := b.str()
			if err != nil {
				return nil, err
			}
			evt.Name = name

		case 0x05, 0x07, 0x0A: // Text, Comment, RawText
			v, err := b.str()
			if err != nil {
				return nil, err
			}
			evt.Value = v

		case 0x06: // Scalar
			typeStr, err := b.str()
			if err != nil {
				return nil, err
			}
			valueStr, err := b.str()
			if err != nil {
				return nil, err
			}
			s := typeStr
			evt.DataType = &s
			evt.Value = coerceAttrValue(typeStr, valueStr)

		case 0x08: // PI
			target, err := b.str()
			if err != nil {
				return nil, err
			}
			data, err := b.optstr()
			if err != nil {
				return nil, err
			}
			evt.Target = target
			evt.Data = data

		case 0x09, 0x0B: // EntityRef, Alias
			v, err := b.str()
			if err != nil {
				return nil, err
			}
			evt.Value = v

		// 0x01 StartDoc, 0x02 EndDoc: no payload
		}

		events = append(events, evt)
	}
	return events, nil
}
