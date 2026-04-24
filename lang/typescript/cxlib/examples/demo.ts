#!/usr/bin/env tsx
/**
 * CX Document API demo — TypeScript binding.
 *
 * Run from the cxlib directory:
 *   cd lang/typescript/cxlib && tsx examples/demo.ts
 */
import { parse, Element, ScalarNode, stream } from '../src/index';

const CONFIG_SRC = `[config version='1.0' debug=false
  [server host=localhost port=8080]
  [database url='postgres://localhost/mydb' pool=10]
  [cache enabled=true ttl=300]
]`;

const SERVICES_SRC = `[services
  [service name=auth  port=8080 active=true]
  [service name=api   port=9000 active=false]
  [service name=web   port=80   active=true]
]`;

// ── 1. Document Model ─────────────────────────────────────────────────────────

function documentModelDemo() {
  console.log('=== Document Model ===');

  const doc = parse(CONFIG_SRC);

  // Read server attrs via path navigation
  const server = doc.at('config/server')!;
  console.log(`host: ${server.attr('host')}`);
  console.log(`port: ${server.attr('port')}`);

  // Update host to production value
  server.setAttr('host', 'prod.example.com');

  // Append a timeout child element
  server.append(new Element({
    name: 'timeout',
    items: [new ScalarNode('int', 30)],
  }));

  // Remove the cache element
  const config = doc.root()!;
  const cache = config.get('cache')!;
  config.remove(cache);

  console.log('\n--- Result CX ---');
  console.log(doc.to_cx());
}

// ── 2. Streaming ──────────────────────────────────────────────────────────────

function streamingDemo() {
  console.log('\n=== Streaming ===');

  const events = stream(CONFIG_SRC);

  for (const ev of events) {
    if (ev.type === 'StartElement') {
      const attrs = (ev.attrs ?? [])
        .map((a: { name: string; value: unknown }) => `${a.name}=${a.value}`)
        .join('  ');
      console.log(`element: ${ev.name}${attrs ? '  ' + attrs : ''}`);
    }
  }
}

// ── 3. CXPath Select ─────────────────────────────────────────────────────────

function cxpathDemo() {
  console.log('\n=== CXPath Select ===');

  const doc = parse(SERVICES_SRC);

  // First match
  const first = doc.select('//service');
  console.log(`first service: ${first?.attr('name')}`);

  // Filtered by attribute predicate
  const active = doc.selectAll('//service[@active=true]');
  for (const svc of active) {
    console.log(`active: ${svc.attr('name')}`);
  }
}

// ── 4. Transform ──────────────────────────────────────────────────────────────

function transformDemo() {
  console.log('\n=== Transform ===');

  const doc = parse(SERVICES_SRC);

  // Immutable path-targeted update: rename first service
  const updated = doc.transform('services/service', (el) => {
    el.setAttr('name', 'renamed-auth');
    return el;
  });
  console.log('After transform (rename auth):');
  console.log(updated.to_cx());

  // Apply function to every matching element
  const allActive = doc.transformAll('//service', (el) => {
    el.setAttr('active', true, 'bool');
    return el;
  });
  const results = allActive.selectAll('//service[@active=true]');
  console.log(`Active services after transformAll: ${results.length}`);
}

// ── run ───────────────────────────────────────────────────────────────────────

documentModelDemo();
streamingDemo();
cxpathDemo();
transformDemo();
