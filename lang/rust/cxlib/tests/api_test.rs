//! Integration tests for the CX Document API (rustlang binding).
//!
//! Mirrors the Python test_api.py fixture suite.

use cxlib::ast::{parse, parse_xml, parse_json, parse_yaml, loads, loads_xml, loads_json,
                 loads_yaml, loads_toml, loads_md, dumps, Element, Node, Attr};
use cxlib::stream::StreamEventType;
use serde_json::{Value, json};

// ── fixture loader ────────────────────────────────────────────────────────────

fn fixtures_dir() -> std::path::PathBuf {
    // file!() = "lang/rust/cxlib/tests/api_test.rs" (relative to workspace root)
    // We need to go from the test source file's directory up to the repo root.
    // At test-run time the cwd is the crate root (lang/rust/cxlib), so we can
    // use a path relative to the manifest directory.
    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR")
        .expect("CARGO_MANIFEST_DIR not set");
    std::path::Path::new(&manifest_dir)
        .parent().unwrap()  // lang/rust/
        .parent().unwrap()  // lang/
        .parent().unwrap()  // repo root
        .join("fixtures")
}

fn fx(name: &str) -> String {
    let path = fixtures_dir().join(name);
    std::fs::read_to_string(&path)
        .unwrap_or_else(|e| panic!("cannot read fixture {}: {}", name, e))
}

// ── parse / root / get ────────────────────────────────────────────────────────

#[test]
fn test_parse_returns_document() {
    let doc = parse(&fx("api_config.cx")).unwrap();
    assert!(doc.root().is_some());
}

#[test]
fn test_root_returns_first_element() {
    let doc = parse(&fx("api_config.cx")).unwrap();
    assert_eq!(doc.root().unwrap().name, "config");
}

#[test]
fn test_root_none_on_empty_input() {
    let doc = parse("").unwrap();
    assert!(doc.root().is_none());
}

#[test]
fn test_get_top_level_by_name() {
    let doc = parse(&fx("api_config.cx")).unwrap();
    assert_eq!(doc.get("config").unwrap().name, "config");
    assert!(doc.get("missing").is_none());
}

#[test]
fn test_get_multi_top_level() {
    let doc = parse(&fx("api_multi.cx")).unwrap();
    let first_service = doc.get("service").unwrap();
    assert_eq!(first_service.attr("name").unwrap(), "auth");
}

#[test]
fn test_parse_multiple_top_level_elements() {
    let doc = parse(&fx("api_multi.cx")).unwrap();
    let services: Vec<_> = doc.elements.iter().filter_map(|n| {
        if let Node::Element(e) = n { if e.name == "service" { Some(e) } else { None } } else { None }
    }).collect();
    assert_eq!(services.len(), 3);
}

// ── attr ──────────────────────────────────────────────────────────────────────

#[test]
fn test_attr_string() {
    let doc = parse(&fx("api_config.cx")).unwrap();
    let srv = doc.at("config/server").unwrap();
    assert_eq!(srv.attr("host").unwrap(), "localhost");
}

#[test]
fn test_attr_int() {
    let doc = parse(&fx("api_config.cx")).unwrap();
    let srv = doc.at("config/server").unwrap();
    let port = srv.attr("port").unwrap();
    assert_eq!(port.as_i64().unwrap(), 8080);
}

#[test]
fn test_attr_bool() {
    let doc = parse(&fx("api_config.cx")).unwrap();
    let srv = doc.at("config/server").unwrap();
    assert_eq!(srv.attr("debug").unwrap(), &Value::Bool(false));
}

#[test]
fn test_attr_float() {
    let doc = parse(&fx("api_config.cx")).unwrap();
    let srv = doc.at("config/server").unwrap();
    let ratio = srv.attr("ratio").unwrap().as_f64().unwrap();
    assert!((ratio - 1.5).abs() < 1e-9);
}

#[test]
fn test_attr_missing_returns_none() {
    let doc = parse(&fx("api_config.cx")).unwrap();
    let srv = doc.at("config/server").unwrap();
    assert!(srv.attr("nonexistent").is_none());
}

// ── scalar ────────────────────────────────────────────────────────────────────

#[test]
fn test_scalar_int() {
    let doc = parse(&fx("api_scalars.cx")).unwrap();
    let el = doc.at("values/count").unwrap();
    assert_eq!(el.scalar().unwrap().as_i64().unwrap(), 42);
}

#[test]
fn test_scalar_float() {
    let doc = parse(&fx("api_scalars.cx")).unwrap();
    let el = doc.at("values/ratio").unwrap();
    let f = el.scalar().unwrap().as_f64().unwrap();
    assert!((f - 1.5).abs() < 1e-9);
}

#[test]
fn test_scalar_bool_true() {
    let doc = parse(&fx("api_scalars.cx")).unwrap();
    let el = doc.at("values/enabled").unwrap();
    assert_eq!(el.scalar().unwrap(), &Value::Bool(true));
}

#[test]
fn test_scalar_bool_false() {
    let doc = parse(&fx("api_scalars.cx")).unwrap();
    let el = doc.at("values/disabled").unwrap();
    assert_eq!(el.scalar().unwrap(), &Value::Bool(false));
}

#[test]
fn test_scalar_null() {
    let doc = parse(&fx("api_scalars.cx")).unwrap();
    let el = doc.at("values/nothing").unwrap();
    assert_eq!(el.scalar().unwrap(), &Value::Null);
}

#[test]
fn test_scalar_none_on_element_with_children() {
    let doc = parse(&fx("api_config.cx")).unwrap();
    assert!(doc.root().unwrap().scalar().is_none());
}

// ── text ──────────────────────────────────────────────────────────────────────

#[test]
fn test_text_single_token() {
    let doc = parse(&fx("api_article.cx")).unwrap();
    assert_eq!(doc.at("article/body/h1").unwrap().text(), "Introduction");
}

#[test]
fn test_text_quoted() {
    let doc = parse(&fx("api_scalars.cx")).unwrap();
    let el = doc.at("values/label").unwrap();
    assert_eq!(el.text(), "hello world");
}

#[test]
fn test_text_empty_on_element_with_children() {
    let doc = parse(&fx("api_config.cx")).unwrap();
    assert_eq!(doc.root().unwrap().text(), "");
}

// ── children / get_all ────────────────────────────────────────────────────────

#[test]
fn test_children_returns_only_elements() {
    let doc = parse(&fx("api_config.cx")).unwrap();
    let config = doc.root().unwrap();
    let kids = config.children();
    assert_eq!(kids.len(), 3);
    let names: Vec<_> = kids.iter().map(|e| e.name.as_str()).collect();
    assert_eq!(names, vec!["server", "database", "logging"]);
}

#[test]
fn test_get_all_direct_children() {
    let doc = parse("[root [item 1] [item 2] [other x] [item 3]]").unwrap();
    let items = doc.root().unwrap().get_all("item");
    assert_eq!(items.len(), 3);
}

#[test]
fn test_get_all_returns_empty_for_missing() {
    let doc = parse(&fx("api_config.cx")).unwrap();
    assert!(doc.root().unwrap().get_all("missing").is_empty());
}

// ── at ────────────────────────────────────────────────────────────────────────

#[test]
fn test_at_single_segment() {
    let doc = parse(&fx("api_config.cx")).unwrap();
    assert_eq!(doc.at("config").unwrap().name, "config");
}

#[test]
fn test_at_two_segments() {
    let doc = parse(&fx("api_config.cx")).unwrap();
    assert_eq!(doc.at("config/server").unwrap().name, "server");
    assert_eq!(doc.at("config/database").unwrap().name, "database");
}

#[test]
fn test_at_three_segments() {
    let doc = parse(&fx("api_article.cx")).unwrap();
    assert_eq!(doc.at("article/head/title").unwrap().text(), "Getting Started with CX");
    assert_eq!(doc.at("article/body/h1").unwrap().text(), "Introduction");
}

#[test]
fn test_at_missing_segment_returns_none() {
    let doc = parse(&fx("api_config.cx")).unwrap();
    assert!(doc.at("config/missing").is_none());
}

#[test]
fn test_at_missing_root_returns_none() {
    let doc = parse(&fx("api_config.cx")).unwrap();
    assert!(doc.at("missing").is_none());
}

#[test]
fn test_at_deep_missing_returns_none() {
    let doc = parse(&fx("api_config.cx")).unwrap();
    assert!(doc.at("config/server/missing/deep").is_none());
}

#[test]
fn test_element_at_relative_path() {
    let doc = parse(&fx("api_article.cx")).unwrap();
    let body = doc.at("article/body").unwrap();
    assert_eq!(body.at("section/h2").unwrap().text(), "Details");
}

// ── find_all ──────────────────────────────────────────────────────────────────

#[test]
fn test_find_all_top_level() {
    let doc = parse(&fx("api_multi.cx")).unwrap();
    assert_eq!(doc.find_all("service").len(), 3);
}

#[test]
fn test_find_all_deep() {
    let doc = parse(&fx("api_article.cx")).unwrap();
    let ps = doc.find_all("p");
    assert_eq!(ps.len(), 3);
    assert_eq!(ps[0].text(), "First paragraph.");
    assert_eq!(ps[1].text(), "Nested paragraph.");
    assert_eq!(ps[2].text(), "Another nested paragraph.");
}

#[test]
fn test_find_all_missing_returns_empty() {
    let doc = parse(&fx("api_config.cx")).unwrap();
    assert!(doc.find_all("missing").is_empty());
}

#[test]
fn test_find_all_on_element() {
    let doc = parse(&fx("api_article.cx")).unwrap();
    let body = doc.at("article/body").unwrap();
    assert_eq!(body.find_all("p").len(), 3);
}

// ── find_first ────────────────────────────────────────────────────────────────

#[test]
fn test_find_first_returns_first_match() {
    let doc = parse(&fx("api_article.cx")).unwrap();
    let p = doc.find_first("p").unwrap();
    assert_eq!(p.text(), "First paragraph.");
}

#[test]
fn test_find_first_missing_returns_none() {
    let doc = parse(&fx("api_config.cx")).unwrap();
    assert!(doc.find_first("missing").is_none());
}

#[test]
fn test_find_first_depth_first_order() {
    let doc = parse(&fx("api_article.cx")).unwrap();
    assert_eq!(doc.find_first("h1").unwrap().text(), "Introduction");
    assert_eq!(doc.find_first("h2").unwrap().text(), "Details");
}

#[test]
fn test_find_first_on_element() {
    let doc = parse(&fx("api_article.cx")).unwrap();
    let section = doc.at("article/body/section").unwrap();
    let p = section.find_first("p").unwrap();
    assert_eq!(p.text(), "Nested paragraph.");
}

// ── mutation — Element ────────────────────────────────────────────────────────

#[test]
fn test_append_adds_to_end() {
    let mut doc = parse(&fx("api_config.cx")).unwrap();
    // We need a mutable reference chain — rebuild with get_mut helpers via index
    // Since Document/Element are plain structs, we work with owned clones:
    let config_idx = doc.elements.iter().position(|n| matches!(n, Node::Element(e) if e.name == "config")).unwrap();
    if let Node::Element(ref mut config) = doc.elements[config_idx] {
        config.append(Node::Element(Element::new("cache")));
        let kids = config.children();
        assert_eq!(kids.last().unwrap().name, "cache");
        assert_eq!(kids.len(), 4);
    } else {
        panic!("expected Element");
    }
}

#[test]
fn test_prepend_adds_to_front() {
    let mut doc = parse(&fx("api_config.cx")).unwrap();
    let config_idx = doc.elements.iter().position(|n| matches!(n, Node::Element(e) if e.name == "config")).unwrap();
    if let Node::Element(ref mut config) = doc.elements[config_idx] {
        config.prepend(Node::Element(Element::new("meta")));
        assert_eq!(config.children()[0].name, "meta");
    }
}

#[test]
fn test_remove_named() {
    let mut doc = parse(&fx("api_config.cx")).unwrap();
    let config_idx = doc.elements.iter().position(|n| matches!(n, Node::Element(e) if e.name == "config")).unwrap();
    if let Node::Element(ref mut config) = doc.elements[config_idx] {
        config.remove_named("database");
        assert!(config.get("database").is_none());
        assert!(config.get("server").is_some());
    }
}

#[test]
fn test_remove_child_at() {
    let mut doc = parse("[root [a 1] [b 2] [c 3]]").unwrap();
    let root_idx = 0;
    if let Node::Element(ref mut root) = doc.elements[root_idx] {
        // remove index 1 ([b 2])
        root.remove_child_at(1);
        let names: Vec<_> = root.children().iter().map(|e| e.name.as_str()).collect();
        assert_eq!(names, vec!["a", "c"]);
    }
}

#[test]
fn test_set_attr_new() {
    let mut doc = parse(&fx("api_config.cx")).unwrap();
    let config_idx = doc.elements.iter().position(|n| matches!(n, Node::Element(e) if e.name == "config")).unwrap();
    if let Node::Element(ref mut config) = doc.elements[config_idx] {
        let server_idx = config.items.iter().position(|n| matches!(n, Node::Element(e) if e.name == "server")).unwrap();
        if let Node::Element(ref mut srv) = config.items[server_idx] {
            srv.set_attr("env", json!("production"), None);
            assert_eq!(srv.attr("env").unwrap(), "production");
        }
    }
}

#[test]
fn test_set_attr_update_value() {
    let mut doc = parse(&fx("api_config.cx")).unwrap();
    let config_idx = doc.elements.iter().position(|n| matches!(n, Node::Element(e) if e.name == "config")).unwrap();
    if let Node::Element(ref mut config) = doc.elements[config_idx] {
        let server_idx = config.items.iter().position(|n| matches!(n, Node::Element(e) if e.name == "server")).unwrap();
        if let Node::Element(ref mut srv) = config.items[server_idx] {
            let orig_count = srv.attrs.len();
            srv.set_attr("port", json!(9090), Some("int".to_string()));
            assert_eq!(srv.attr("port").unwrap().as_i64().unwrap(), 9090);
            assert_eq!(srv.attrs.len(), orig_count); // no duplicate
        }
    }
}

#[test]
fn test_remove_attr() {
    let mut doc = parse(&fx("api_config.cx")).unwrap();
    let config_idx = doc.elements.iter().position(|n| matches!(n, Node::Element(e) if e.name == "config")).unwrap();
    if let Node::Element(ref mut config) = doc.elements[config_idx] {
        let server_idx = config.items.iter().position(|n| matches!(n, Node::Element(e) if e.name == "server")).unwrap();
        if let Node::Element(ref mut srv) = config.items[server_idx] {
            let orig_count = srv.attrs.len();
            srv.remove_attr("debug");
            assert!(srv.attr("debug").is_none());
            assert_eq!(srv.attrs.len(), orig_count - 1);
        }
    }
}

#[test]
fn test_remove_attr_nonexistent_is_noop() {
    let mut doc = parse(&fx("api_config.cx")).unwrap();
    let config_idx = doc.elements.iter().position(|n| matches!(n, Node::Element(e) if e.name == "config")).unwrap();
    if let Node::Element(ref mut config) = doc.elements[config_idx] {
        let server_idx = config.items.iter().position(|n| matches!(n, Node::Element(e) if e.name == "server")).unwrap();
        if let Node::Element(ref mut srv) = config.items[server_idx] {
            let orig_count = srv.attrs.len();
            srv.remove_attr("nonexistent");
            assert_eq!(srv.attrs.len(), orig_count);
        }
    }
}

// ── mutation — Document ───────────────────────────────────────────────────────

#[test]
fn test_doc_append_element() {
    let mut doc = parse(&fx("api_config.cx")).unwrap();
    let mut cache = Element::new("cache");
    cache.attrs.push(Attr { name: "host".to_string(), value: json!("redis"), data_type: None });
    doc.append(Node::Element(cache));
    assert_eq!(doc.get("cache").unwrap().attr("host").unwrap(), "redis");
}

#[test]
fn test_doc_prepend_makes_new_root() {
    let mut doc = parse(&fx("api_config.cx")).unwrap();
    doc.prepend(Node::Element(Element::new("preamble")));
    assert_eq!(doc.root().unwrap().name, "preamble");
    assert!(doc.get("config").is_some());
}

// ── round-trips ───────────────────────────────────────────────────────────────

#[test]
fn test_to_cx_round_trip() {
    let original = parse(&fx("api_config.cx")).unwrap();
    let cx_str = original.to_cx();
    let reparsed = parse(&cx_str).unwrap();
    assert_eq!(reparsed.at("config/server").unwrap().attr("host").unwrap(), "localhost");
    assert_eq!(reparsed.at("config/server").unwrap().attr("port").unwrap().as_i64().unwrap(), 8080);
    assert_eq!(reparsed.at("config/database").unwrap().attr("name").unwrap(), "myapp");
}

#[test]
fn test_to_cx_preserves_article_structure() {
    let original = parse(&fx("api_article.cx")).unwrap();
    let cx_str = original.to_cx();
    let reparsed = parse(&cx_str).unwrap();
    assert_eq!(reparsed.at("article/head/title").unwrap().text(), "Getting Started with CX");
    assert_eq!(reparsed.find_all("p").len(), 3);
}

#[test]
fn test_to_cx_round_trip_after_mutation() {
    let mut doc = parse(&fx("api_config.cx")).unwrap();
    // Navigate to server via index to get mutable access
    let config_idx = doc.elements.iter().position(|n| matches!(n, Node::Element(e) if e.name == "config")).unwrap();
    if let Node::Element(ref mut config) = doc.elements[config_idx] {
        let server_idx = config.items.iter().position(|n| matches!(n, Node::Element(e) if e.name == "server")).unwrap();
        if let Node::Element(ref mut srv) = config.items[server_idx] {
            srv.set_attr("env", json!("production"), None);
            let mut timeout = Element::new("timeout");
            timeout.items.push(Node::Scalar { data_type: "int".to_string(), value: json!(30) });
            srv.append(Node::Element(timeout));
        }
    }
    let cx_str = doc.to_cx();
    let reparsed = parse(&cx_str).unwrap();
    assert_eq!(reparsed.at("config/server").unwrap().attr("env").unwrap(), "production");
    assert_eq!(reparsed.at("config/server").unwrap().find_first("timeout").unwrap().scalar().unwrap().as_i64().unwrap(), 30);
}

// ── loads / dumps ─────────────────────────────────────────────────────────────

#[test]
fn test_loads_returns_value() {
    let data = loads(&fx("api_config.cx")).unwrap();
    assert!(data.is_object());
    assert_eq!(data["config"]["server"]["host"], "localhost");
    assert_eq!(data["config"]["server"]["port"].as_i64().unwrap(), 8080);
}

#[test]
fn test_loads_bool_types() {
    let data = loads(&fx("api_config.cx")).unwrap();
    assert_eq!(data["config"]["server"]["debug"], Value::Bool(false));
}

#[test]
fn test_loads_scalars() {
    let data = loads(&fx("api_scalars.cx")).unwrap();
    assert_eq!(data["values"]["count"].as_i64().unwrap(), 42);
    assert_eq!(data["values"]["enabled"], Value::Bool(true));
    assert_eq!(data["values"]["disabled"], Value::Bool(false));
    assert_eq!(data["values"]["nothing"], Value::Null);
}

#[test]
fn test_loads_xml() {
    let data = loads_xml("<server host=\"localhost\" port=\"8080\"/>").unwrap();
    assert!(data.get("server").is_some());
}

#[test]
fn test_loads_json_passthrough() {
    let data = loads_json("{\"port\": 8080, \"debug\": false}").unwrap();
    assert_eq!(data["port"].as_i64().unwrap(), 8080);
    assert_eq!(data["debug"], Value::Bool(false));
}

#[test]
fn test_loads_yaml() {
    let data = loads_yaml("server:\n  host: localhost\n  port: 8080\n").unwrap();
    assert!(data.get("server").is_some());
}

#[test]
fn test_loads_toml() {
    let result = loads_toml("[server]\nhost = \"localhost\"\n").expect("loads_toml failed");
    assert!(result.is_object());
    assert!(result["server"].is_object());
}

#[test]
fn test_loads_md() {
    let result = loads_md("# hello\n\nworld\n").expect("loads_md failed");
    assert!(!result.is_null());
}

#[test]
fn test_dumps_produces_parseable_cx() {
    let data = json!({"app": {"name": "myapp", "version": "1.0", "port": 8080}});
    let cx_str = dumps(&data).unwrap();
    let reparsed = parse(&cx_str).unwrap();
    assert!(reparsed.find_first("app").is_some());
}

#[test]
fn test_loads_dumps_data_preserved() {
    let original = json!({"server": {"host": "localhost", "port": 8080, "debug": false}});
    let cx_str = dumps(&original).unwrap();
    let restored = loads(&cx_str).unwrap();
    assert_eq!(restored["server"]["port"].as_i64().unwrap(), 8080);
    assert_eq!(restored["server"]["host"], "localhost");
    assert_eq!(restored["server"]["debug"], Value::Bool(false));
}

// ── error / failure cases ─────────────────────────────────────────────────────

#[test]
fn test_parse_error_unclosed_bracket() {
    assert!(parse(&fx("errors/unclosed.cx")).is_err());
}

#[test]
fn test_parse_error_empty_element_name() {
    assert!(parse(&fx("errors/empty_name.cx")).is_err());
}

#[test]
fn test_parse_error_nested_unclosed() {
    assert!(parse(&fx("errors/nested_unclosed.cx")).is_err());
}

#[test]
fn test_at_missing_path_returns_none_not_error() {
    let doc = parse(&fx("api_config.cx")).unwrap();
    assert!(doc.at("config/server/missing/deep/path").is_none());
}

#[test]
fn test_find_all_on_empty_doc_returns_empty() {
    let doc = parse("").unwrap();
    assert!(doc.find_all("anything").is_empty());
}

#[test]
fn test_find_first_on_empty_doc_returns_none() {
    let doc = parse("").unwrap();
    assert!(doc.find_first("anything").is_none());
}

#[test]
fn test_scalar_none_when_element_has_child_elements() {
    let doc = parse(&fx("api_config.cx")).unwrap();
    assert!(doc.root().unwrap().scalar().is_none());
}

#[test]
fn test_text_empty_when_no_text_children() {
    let doc = parse(&fx("api_config.cx")).unwrap();
    assert_eq!(doc.root().unwrap().text(), "");
}

#[test]
fn test_remove_attr_nonexistent_does_not_panic() {
    let mut doc = parse(&fx("api_config.cx")).unwrap();
    let config_idx = doc.elements.iter().position(|n| matches!(n, Node::Element(e) if e.name == "config")).unwrap();
    if let Node::Element(ref mut config) = doc.elements[config_idx] {
        let server_idx = config.items.iter().position(|n| matches!(n, Node::Element(e) if e.name == "server")).unwrap();
        if let Node::Element(ref mut srv) = config.items[server_idx] {
            srv.remove_attr("totally_missing"); // must not panic
        }
    }
}

#[test]
fn test_parse_xml_invalid() {
    assert!(parse_xml("<unclosed").is_err());
}

// ── parse other formats ───────────────────────────────────────────────────────

#[test]
fn test_parse_xml_valid() {
    let doc = parse_xml("<root><child key=\"val\"/></root>").unwrap();
    assert_eq!(doc.root().unwrap().name, "root");
    assert!(doc.find_first("child").is_some());
}

#[test]
fn test_parse_json_to_document() {
    let doc = parse_json("{\"server\": {\"port\": 8080}}").unwrap();
    assert!(doc.find_first("server").is_some());
}

#[test]
fn test_parse_yaml_to_document() {
    let doc = parse_yaml("server:\n  port: 8080\n").unwrap();
    assert!(doc.find_first("server").is_some());
}

// ── stream / binary events ────────────────────────────────────────────────────

#[test]
fn test_stream_start_end_doc() {
    let events = cxlib::stream("[root hello]").unwrap();
    assert!(matches!(events.first().unwrap().event_type, StreamEventType::StartDoc));
    assert!(matches!(events.last().unwrap().event_type, StreamEventType::EndDoc));
}

#[test]
fn test_stream_start_element_name() {
    let events = cxlib::stream("[config version=2]").unwrap();
    let start_el = events.iter().find(|e| {
        matches!(&e.event_type, StreamEventType::StartElement { name, .. } if name == "config")
    });
    assert!(start_el.is_some(), "expected StartElement(config)");
}

#[test]
fn test_stream_start_element_attrs() {
    let events = cxlib::stream("[server host=localhost port=8080 debug=false]").unwrap();
    let start = events.iter().find_map(|e| {
        if let StreamEventType::StartElement { name, attrs, .. } = &e.event_type {
            if name == "server" { Some(attrs) } else { None }
        } else {
            None
        }
    }).expect("StartElement(server) not found");

    let host = start.iter().find(|a| a.name == "host").expect("host attr missing");
    assert_eq!(host.value, Value::String("localhost".to_string()));

    let port = start.iter().find(|a| a.name == "port").expect("port attr missing");
    assert_eq!(port.value.as_i64().unwrap(), 8080);

    let debug = start.iter().find(|a| a.name == "debug").expect("debug attr missing");
    assert_eq!(debug.value, Value::Bool(false));
}

#[test]
fn test_stream_text_event() {
    let events = cxlib::stream("[title Hello World]").unwrap();
    let text_val = events.iter().find_map(|e| {
        if let StreamEventType::Text(s) = &e.event_type { Some(s.as_str()) } else { None }
    });
    assert_eq!(text_val, Some("Hello World"));
}

#[test]
fn test_stream_end_element_name() {
    let events = cxlib::stream("[article [p text]]").unwrap();
    let end_el = events.iter().find(|e| {
        matches!(&e.event_type, StreamEventType::EndElement { name } if name == "article")
    });
    assert!(end_el.is_some(), "expected EndElement(article)");
}

// ── remove_child / remove_at ──────────────────────────────────────────────────

#[test]
fn test_remove_child_removes_all_matching() {
    let mut doc = parse("[parent [a 1] [b 2] [a 3]]").unwrap();
    if let Node::Element(ref mut parent) = doc.elements[0] {
        parent.remove_child("a");
        let kids = parent.children();
        assert_eq!(kids.len(), 1);
        assert_eq!(kids[0].name, "b");
    }
}

#[test]
fn test_remove_child_nonexistent_is_noop() {
    let mut doc = parse("[parent [a 1] [b 2]]").unwrap();
    if let Node::Element(ref mut parent) = doc.elements[0] {
        let orig_len = parent.children().len();
        parent.remove_child("z");
        assert_eq!(parent.children().len(), orig_len);
    }
}

#[test]
fn test_remove_at_removes_by_index() {
    let mut doc = parse("[root [a 1] [b 2] [c 3]]").unwrap();
    if let Node::Element(ref mut root) = doc.elements[0] {
        root.remove_at(1);
        let names: Vec<_> = root.children().iter().map(|e| e.name.as_str()).collect();
        assert_eq!(names, vec!["a", "c"]);
    }
}

#[test]
fn test_remove_at_out_of_bounds_is_noop() {
    let mut doc = parse("[root [a 1] [b 2]]").unwrap();
    if let Node::Element(ref mut root) = doc.elements[0] {
        let orig_len = root.items.len();
        root.remove_at(99);
        assert_eq!(root.items.len(), orig_len);
    }
}

// ── select_all / select ───────────────────────────────────────────────────────

#[test]
fn test_select_all_descendant() {
    let doc = parse(&fx("api_multi.cx")).unwrap();
    let results = doc.select_all("//service").unwrap();
    assert_eq!(results.len(), 3);
}

#[test]
fn test_select_all_attr_predicate() {
    // api_multi.cx has services with port: 8001, 8080, 9000
    // select services with port >= 8080
    let doc = parse(&fx("api_multi.cx")).unwrap();
    let results = doc.select_all("//service[@port>=8080]").unwrap();
    assert_eq!(results.len(), 2);
}

#[test]
fn test_select_first() {
    let doc = parse(&fx("api_multi.cx")).unwrap();
    let first = doc.select("//service").unwrap();
    assert!(first.is_some());
    assert_eq!(first.unwrap().attr("name").unwrap(), "auth");
}

#[test]
fn test_select_child_path() {
    let doc = parse(&fx("api_config.cx")).unwrap();
    let results = doc.select_all("config/server").unwrap();
    assert_eq!(results.len(), 1);
    assert_eq!(results[0].attr("host").unwrap(), "localhost");
}

#[test]
fn test_select_wildcard() {
    // Wildcard matches all direct children of config
    let doc = parse(&fx("api_config.cx")).unwrap();
    let results = doc.select_all("config/*").unwrap();
    assert_eq!(results.len(), 3);
}

#[test]
fn test_select_numeric_comparison() {
    // api_multi.cx: auth=8001, api=8080, worker=9000 — port >= 8000 → all 3
    let doc = parse(&fx("api_multi.cx")).unwrap();
    let results = doc.select_all("//service[@port>=8000]").unwrap();
    assert_eq!(results.len(), 3);
}

#[test]
fn test_select_position() {
    let doc = parse(&fx("api_multi.cx")).unwrap();
    // Position 2 among top-level service elements: "api" (port=8080)
    let results = doc.select_all("service[2]").unwrap();
    assert_eq!(results.len(), 1);
    assert_eq!(results[0].attr("name").unwrap(), "api");
}

#[test]
fn test_select_last_position() {
    let doc = parse(&fx("api_multi.cx")).unwrap();
    let results = doc.select_all("service[last()]").unwrap();
    assert_eq!(results.len(), 1);
    assert_eq!(results[0].attr("name").unwrap(), "worker");
}

#[test]
fn test_select_contains() {
    // api_multi.cx: service names = auth, api, worker
    let doc = parse(&fx("api_multi.cx")).unwrap();
    let results = doc.select_all("//service[contains(@name, 'a')]").unwrap();
    // "auth" and "api" contain 'a'
    assert_eq!(results.len(), 2);
}

#[test]
fn test_select_starts_with() {
    let doc = parse(&fx("api_multi.cx")).unwrap();
    let results = doc.select_all("//service[starts-with(@name, 'a')]").unwrap();
    // "auth" and "api" start with 'a'
    assert_eq!(results.len(), 2);
}

#[test]
fn test_select_bool_and() {
    // Select services where port >= 8000 AND port <= 9000 (all 3: 8001, 8080, 9000)
    // Then narrow: port >= 8080 AND port <= 9000 (2: 8080, 9000)
    let doc = parse(&fx("api_multi.cx")).unwrap();
    let results = doc.select_all("//service[@port>=8080 and @port<=9000]").unwrap();
    assert_eq!(results.len(), 2);
}

#[test]
fn test_select_on_element_subtree() {
    let doc = parse(&fx("api_article.cx")).unwrap();
    let body = doc.at("article/body").unwrap();
    let results = body.select_all("//p").unwrap();
    assert_eq!(results.len(), 3);
}

#[test]
fn test_select_invalid_expr_returns_err() {
    let doc = parse(&fx("api_config.cx")).unwrap();
    let result = doc.select_all("[@@@invalid");
    assert!(result.is_err());
}

// ── transform ─────────────────────────────────────────────────────────────────

#[test]
fn test_transform_applies_function() {
    let doc = parse(&fx("api_config.cx")).unwrap();
    let updated = doc.transform("config/server", |mut el| {
        el.set_attr("host", json!("prod.example.com"), None);
        el
    });
    assert_eq!(
        updated.at("config/server").unwrap().attr("host").unwrap(),
        "prod.example.com"
    );
}

#[test]
fn test_transform_original_unchanged() {
    let doc = parse(&fx("api_config.cx")).unwrap();
    let _updated = doc.transform("config/server", |mut el| {
        el.set_attr("host", json!("other.example.com"), None);
        el
    });
    // Original doc is unchanged
    assert_eq!(
        doc.at("config/server").unwrap().attr("host").unwrap(),
        "localhost"
    );
}

#[test]
fn test_transform_returns_new_document() {
    let doc = parse(&fx("api_config.cx")).unwrap();
    let updated = doc.transform("config/server", |mut el| {
        el.set_attr("port", json!(9999), Some("int".to_string()));
        el
    });
    // Verify it's actually a different document (different content)
    assert_eq!(
        updated.at("config/server").unwrap().attr("port").unwrap().as_i64().unwrap(),
        9999
    );
    assert_eq!(
        doc.at("config/server").unwrap().attr("port").unwrap().as_i64().unwrap(),
        8080
    );
}

#[test]
fn test_transform_missing_path() {
    let doc = parse(&fx("api_config.cx")).unwrap();
    // Transform on a nonexistent path returns a clone of the original
    let result = doc.transform("config/nonexistent", |el| el);
    assert_eq!(
        result.at("config/server").unwrap().attr("host").unwrap(),
        "localhost"
    );
}

#[test]
fn test_transform_chained() {
    let doc = parse(&fx("api_config.cx")).unwrap();
    let result = doc
        .transform("config/server", |mut el| {
            el.set_attr("host", json!("web.example.com"), None);
            el
        })
        .transform("config/database", |mut el| {
            el.set_attr("host", json!("db.example.com"), None);
            el
        });
    assert_eq!(
        result.at("config/server").unwrap().attr("host").unwrap(),
        "web.example.com"
    );
    assert_eq!(
        result.at("config/database").unwrap().attr("host").unwrap(),
        "db.example.com"
    );
    // Original still unchanged
    assert_eq!(
        doc.at("config/server").unwrap().attr("host").unwrap(),
        "localhost"
    );
}

// ── transform_all ─────────────────────────────────────────────────────────────

#[test]
fn test_transform_all_applies_to_all() {
    let doc = parse(&fx("api_multi.cx")).unwrap();
    let updated = doc.transform_all("//service", |mut el| {
        el.set_attr("active", json!(true), Some("bool".to_string()));
        el
    }).unwrap();
    let services = updated.find_all("service");
    assert_eq!(services.len(), 3);
    for svc in services {
        assert_eq!(svc.attr("active").unwrap(), &Value::Bool(true));
    }
}

#[test]
fn test_transform_all_returns_new() {
    let doc = parse(&fx("api_multi.cx")).unwrap();
    let updated = doc.transform_all("//service", |mut el| {
        el.set_attr("visited", json!(true), Some("bool".to_string()));
        el
    }).unwrap();
    // Original has no "visited" attr
    assert!(doc.find_first("service").unwrap().attr("visited").is_none());
    assert!(updated.find_first("service").unwrap().attr("visited").is_some());
}

#[test]
fn test_transform_all_no_matches() {
    let doc = parse(&fx("api_config.cx")).unwrap();
    let updated = doc.transform_all("//nonexistent", |el| el).unwrap();
    // Document structure preserved
    assert_eq!(
        updated.at("config/server").unwrap().attr("host").unwrap(),
        "localhost"
    );
}

#[test]
fn test_transform_all_deeply_nested() {
    let doc = parse(&fx("api_article.cx")).unwrap();
    let updated = doc.transform_all("//p", |mut el| {
        el.set_attr("styled", json!(true), Some("bool".to_string()));
        el
    }).unwrap();
    let ps = updated.find_all("p");
    assert_eq!(ps.len(), 3);
    for p in ps {
        assert_eq!(p.attr("styled").unwrap(), &Value::Bool(true));
    }
    // Original unchanged
    assert!(doc.find_first("p").unwrap().attr("styled").is_none());
}
