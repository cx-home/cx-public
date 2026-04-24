//! CX Document API demo — Rust binding.
//!
//! Run from the cxlib directory:
//!   cd lang/rust/cxlib && cargo run --example demo

use cxlib::ast::parse;
use cxlib::stream::StreamEventType;
use serde_json::{json, Value};

const CONFIG_SRC: &str = "[config version='1.0' debug=false
  [server host=localhost port=8080]
  [database url='postgres://localhost/mydb' pool=10]
  [cache enabled=true ttl=300]
]";

const SERVICES_SRC: &str = "[services
  [service name=auth  port=8080 active=true]
  [service name=api   port=9000 active=false]
  [service name=web   port=80   active=true]
]";

fn main() -> Result<(), String> {
    document_model_demo()?;
    streaming_demo()?;
    cxpath_demo()?;
    transform_demo()?;
    Ok(())
}

// ── 1. Document Model ─────────────────────────────────────────────────────────

fn document_model_demo() -> Result<(), String> {
    println!("=== Document Model ===");

    let mut doc = parse(CONFIG_SRC)?;

    // Read server attrs via path navigation
    {
        let server = doc.at("config/server").ok_or("config/server not found")?;
        println!("host: {:?}", server.attr("host"));
        println!("port: {:?}", server.attr("port"));
    }

    // Update host to production value (mutation requires owned copy via transform)
    doc = doc.transform("config/server", |mut el| {
        el.set_attr("host", Value::String("prod.example.com".to_string()), None);

        // Append a timeout child element
        let timeout = cxlib::ast::Element {
            name: "timeout".to_string(),
            anchor: None,
            merge: None,
            data_type: Some("int".to_string()),
            attrs: vec![],
            items: vec![cxlib::ast::Node::Scalar {
                data_type: "int".to_string(),
                value: json!(30),
            }],
        };
        el.append(cxlib::ast::Node::Element(timeout));
        el
    });

    // Remove the cache element from config
    doc = doc.transform("config", |mut el| {
        el.remove_named("cache");
        el
    });

    println!("\n--- Result CX ---");
    println!("{}", doc.to_cx());

    Ok(())
}

// ── 2. Streaming ──────────────────────────────────────────────────────────────

fn streaming_demo() -> Result<(), String> {
    println!("\n=== Streaming ===");

    let events = cxlib::stream(CONFIG_SRC)?;

    for ev in &events {
        if let StreamEventType::StartElement { name, attrs, .. } = &ev.event_type {
            print!("element: {name}");
            for a in attrs {
                print!("  {}={}", a.name, a.value);
            }
            println!();
        }
    }

    Ok(())
}

// ── 3. CXPath Select ─────────────────────────────────────────────────────────

fn cxpath_demo() -> Result<(), String> {
    println!("\n=== CXPath Select ===");

    let doc = parse(SERVICES_SRC)?;

    // First match
    let first = doc.select("//service")?.ok_or("no service found")?;
    println!("first service: {:?}", first.attr("name"));

    // Filtered by attribute predicate
    let active = doc.select_all("//service[@active=true]")?;
    for svc in &active {
        println!("active: {:?}", svc.attr("name"));
    }

    Ok(())
}

// ── 4. Transform ──────────────────────────────────────────────────────────────

fn transform_demo() -> Result<(), String> {
    println!("\n=== Transform ===");

    let doc = parse(SERVICES_SRC)?;

    // Immutable path-targeted update: rename first service
    let updated = doc.transform("services/service", |mut el| {
        el.set_attr("name", Value::String("renamed-auth".to_string()), None);
        el
    });
    println!("After transform (rename auth):");
    println!("{}", updated.to_cx());

    // Apply function to every matching element
    let all_active = doc.transform_all("//service", |mut el| {
        el.set_attr("active", Value::Bool(true), Some("bool".to_string()));
        el
    })?;
    let results = all_active.select_all("//service[@active=true]")?;
    println!("Active services after transform_all: {}", results.len());

    Ok(())
}
