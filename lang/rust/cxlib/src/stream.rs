//! Streaming event types for the CX binary event decoder.

use serde_json::Value;
use crate::ast::Attr;

/// The payload of a single CX stream event.
#[derive(Debug, Clone)]
pub enum StreamEventType {
    StartDoc,
    EndDoc,
    StartElement {
        name:      String,
        anchor:    Option<String>,
        data_type: Option<String>,
        merge:     Option<String>,
        attrs:     Vec<Attr>,
    },
    EndElement { name: String },
    Text(String),
    Scalar { data_type: String, value: Value },
    Comment(String),
    PI { target: String, data: Option<String> },
    EntityRef(String),
    RawText(String),
    Alias(String),
}

/// A single CX stream event.
#[derive(Debug, Clone)]
pub struct StreamEvent {
    pub event_type: StreamEventType,
}
