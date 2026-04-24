//! Binary wire protocol decoder for cx_to_ast_bin and cx_to_events_bin.
//!
//! Buffer layout: [u32 LE: payload_size][payload bytes]
//!
//! All integers little-endian.
//!   String:  u32(byte_len) + raw UTF-8 bytes
//!   OptStr:  u8(0=absent, 1=present) + str if present
//!   Attr:    str:name + str:value_str + str:inferred_type

use std::io::{Cursor, Read};
use serde_json::Value;

use crate::ast::{Attr, Document, Element, Node};
use crate::stream::{StreamEvent, StreamEventType};

// ── low-level reader ──────────────────────────────────────────────────────────

struct BufReader<'a> {
    cur: Cursor<&'a [u8]>,
}

impl<'a> BufReader<'a> {
    fn new(data: &'a [u8]) -> Self {
        BufReader { cur: Cursor::new(data) }
    }

    fn u8(&mut self) -> Result<u8, String> {
        let mut buf = [0u8; 1];
        self.cur.read_exact(&mut buf).map_err(|e| format!("binary read u8: {}", e))?;
        Ok(buf[0])
    }

    fn u16(&mut self) -> Result<u16, String> {
        let mut buf = [0u8; 2];
        self.cur.read_exact(&mut buf).map_err(|e| format!("binary read u16: {}", e))?;
        Ok(u16::from_le_bytes(buf))
    }

    fn u32(&mut self) -> Result<u32, String> {
        let mut buf = [0u8; 4];
        self.cur.read_exact(&mut buf).map_err(|e| format!("binary read u32: {}", e))?;
        Ok(u32::from_le_bytes(buf))
    }

    fn str_(&mut self) -> Result<String, String> {
        let len = self.u32()? as usize;
        let mut buf = vec![0u8; len];
        self.cur.read_exact(&mut buf).map_err(|e| format!("binary read str bytes: {}", e))?;
        String::from_utf8(buf).map_err(|e| format!("binary str utf8: {}", e))
    }

    fn optstr(&mut self) -> Result<Option<String>, String> {
        let flag = self.u8()?;
        if flag == 0 {
            Ok(None)
        } else {
            Ok(Some(self.str_()?))
        }
    }
}

// ── scalar coercion ───────────────────────────────────────────────────────────

fn coerce(type_str: &str, value_str: &str) -> Value {
    match type_str {
        "int"   => value_str.parse::<i64>()
                       .map(Value::from)
                       .unwrap_or_else(|_| Value::String(value_str.to_string())),
        "float" => value_str.parse::<f64>()
                       .ok()
                       .and_then(|f| serde_json::Number::from_f64(f))
                       .map(Value::Number)
                       .unwrap_or_else(|| Value::String(value_str.to_string())),
        "bool"  => Value::Bool(value_str == "true"),
        "null"  => Value::Null,
        _       => Value::String(value_str.to_string()),
    }
}

// ── AST decoder ───────────────────────────────────────────────────────────────

fn read_attr(b: &mut BufReader<'_>) -> Result<Attr, String> {
    let name      = b.str_()?;
    let value_str = b.str_()?;
    let type_str  = b.str_()?;
    let value     = coerce(&type_str, &value_str);
    let data_type = if type_str == "string" { None } else { Some(type_str) };
    Ok(Attr { name, value, data_type })
}

fn read_node(b: &mut BufReader<'_>) -> Result<Node, String> {
    let tid = b.u8()?;
    match tid {
        0x01 => {
            let name      = b.str_()?;
            let anchor    = b.optstr()?;
            let data_type = b.optstr()?;
            let merge     = b.optstr()?;
            let attr_count = b.u16()? as usize;
            let mut attrs = Vec::with_capacity(attr_count);
            for _ in 0..attr_count {
                attrs.push(read_attr(b)?);
            }
            let child_count = b.u16()? as usize;
            let mut items = Vec::with_capacity(child_count);
            for _ in 0..child_count {
                items.push(read_node(b)?);
            }
            Ok(Node::Element(Element { name, anchor, data_type, merge, attrs, items }))
        }
        0x02 => Ok(Node::Text(b.str_()?)),
        0x03 => {
            let data_type = b.str_()?;
            let value_str = b.str_()?;
            let value     = coerce(&data_type, &value_str);
            Ok(Node::Scalar { data_type, value })
        }
        0x04 => Ok(Node::Comment(b.str_()?)),
        0x05 => Ok(Node::RawText(b.str_()?)),
        0x06 => Ok(Node::EntityRef(b.str_()?)),
        0x07 => Ok(Node::Alias(b.str_()?)),
        0x08 => {
            let target = b.str_()?;
            let data   = b.optstr()?;
            Ok(Node::PI { target, data })
        }
        0x09 => {
            let version    = b.str_()?;
            let encoding   = b.optstr()?;
            let standalone = b.optstr()?;
            Ok(Node::XMLDecl { version, encoding, standalone })
        }
        0x0A => {
            let count = b.u16()? as usize;
            let mut attrs = Vec::with_capacity(count);
            for _ in 0..count {
                attrs.push(read_attr(b)?);
            }
            Ok(Node::CXDirective(attrs))
        }
        0x0C => {
            let count = b.u16()? as usize;
            let mut items = Vec::with_capacity(count);
            for _ in 0..count {
                items.push(read_node(b)?);
            }
            Ok(Node::BlockContent(items))
        }
        0xFF => {
            // skip node — no payload, return empty text
            Ok(Node::Text(String::new()))
        }
        other => Err(format!("unknown AST node type: 0x{:02X}", other)),
    }
}

/// Decode a binary AST payload into a `Document`.
pub fn decode_ast(data: &[u8]) -> Result<Document, String> {
    let mut b = BufReader::new(data);
    let _version     = b.u8()?;
    let prolog_count = b.u16()? as usize;
    let mut prolog   = Vec::with_capacity(prolog_count);
    for _ in 0..prolog_count {
        prolog.push(read_node(&mut b)?);
    }
    let elem_count = b.u16()? as usize;
    let mut elements = Vec::with_capacity(elem_count);
    for _ in 0..elem_count {
        elements.push(read_node(&mut b)?);
    }
    Ok(Document { prolog, elements })
}

// ── Events decoder ────────────────────────────────────────────────────────────

fn read_stream_attr(b: &mut BufReader<'_>) -> Result<Attr, String> {
    let name      = b.str_()?;
    let value_str = b.str_()?;
    let type_str  = b.str_()?;
    let value     = coerce(&type_str, &value_str);
    let data_type = if type_str == "string" { None } else { Some(type_str) };
    Ok(Attr { name, value, data_type })
}

/// Decode a binary events payload into a `Vec<StreamEvent>`.
pub fn decode_events(data: &[u8]) -> Result<Vec<StreamEvent>, String> {
    let mut b = BufReader::new(data);
    let count = b.u32()? as usize;
    let mut events = Vec::with_capacity(count);
    for _ in 0..count {
        let tid = b.u8()?;
        let event_type = match tid {
            0x01 => StreamEventType::StartDoc,
            0x02 => StreamEventType::EndDoc,
            0x03 => {
                let name      = b.str_()?;
                let anchor    = b.optstr()?;
                let data_type = b.optstr()?;
                let _merge    = b.optstr()?;
                let attr_count = b.u16()? as usize;
                let mut attrs = Vec::with_capacity(attr_count);
                for _ in 0..attr_count {
                    attrs.push(read_stream_attr(&mut b)?);
                }
                StreamEventType::StartElement { name, anchor, data_type, merge: _merge, attrs }
            }
            0x04 => StreamEventType::EndElement { name: b.str_()? },
            0x05 => StreamEventType::Text(b.str_()?),
            0x06 => {
                let data_type = b.str_()?;
                let value_str = b.str_()?;
                let value     = coerce(&data_type, &value_str);
                StreamEventType::Scalar { data_type, value }
            }
            0x07 => StreamEventType::Comment(b.str_()?),
            0x08 => {
                let target = b.str_()?;
                let data   = b.optstr()?;
                StreamEventType::PI { target, data }
            }
            0x09 => StreamEventType::EntityRef(b.str_()?),
            0x0A => StreamEventType::RawText(b.str_()?),
            0x0B => StreamEventType::Alias(b.str_()?),
            other => return Err(format!("unknown event type: 0x{:02X}", other)),
        };
        events.push(StreamEvent { event_type });
    }
    Ok(events)
}
