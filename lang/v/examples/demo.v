import cxlib

fn main() {
	src := "[config version='1.0' debug=false
  [server host=localhost port=8080]
  [database url='postgres://localhost/mydb' pool=10]
  [cache enabled=true ttl=300]
]"

	println('=== CX Document Model Demo ===\n')

	// 1. Parse
	mut doc := cxlib.parse(src) or { panic(err) }

	// 2. Read: navigate to server and print attrs
	server := doc.at('config/server') or { panic('no config/server') }
	host := server.attr('host') or { panic('no host attr') }
	port := server.attr('port') or { panic('no port attr') }
	println('server.host = ${host.str()}')
	println('server.port = ${port.str()}')

	// 3. Update: change host to prod.example.com
	// 4. Create: append a timeout element with text child to server
	// 5. Delete: remove cache child from config
	//
	// V uses value semantics: doc.at() returns a copy.
	// To mutate the tree, clone each level, modify, then write back.
	mut new_top := doc.elements.clone()
	for i, top in new_top {
		if top is cxlib.Element && top.name == 'config' {
			mut config := top
			mut new_items := config.items.clone()
			for j, child in new_items {
				if child is cxlib.Element && child.name == 'server' {
					mut srv := child
					// 3. update host
					srv.set_attr('host', cxlib.ScalarVal('prod.example.com'))
					// 4. append timeout with text child
					srv.append(cxlib.Node(cxlib.Element{
						name:  'timeout'
						items: [cxlib.Node(cxlib.TextNode{ value: '30' })]
					}))
					new_items[j] = cxlib.Node(srv)
				}
			}
			config.items = new_items
			// 5. remove cache child
			config.remove_child('cache')
			new_top[i] = cxlib.Node(config)
		}
	}
	doc.elements = new_top

	println('\nAfter mutations:')
	println(doc.to_cx())

	println('\n=== CX Streaming Demo ===\n')

	events := cxlib.stream(src) or { panic(err) }
	for ev in events {
		print('event: ${ev.typ}')
		if ev.typ == .start_element {
			print('  name=${ev.name}')
			for a in ev.attrs {
				print('  ${a.name}=${a.value.str()}')
			}
		}
		println('')
	}

	println('\n=== CXPath Select Demo ===\n')

	services_src := "[services\n  [service name=auth  port=8080 active=true]\n  [service name=api   port=9000 active=false]\n  [service name=web   port=80   active=true]\n]"
	sdoc := cxlib.parse(services_src) or { panic(err) }

	first_svc := sdoc.select('//service') or { panic(err) }
	first_name := first_svc.attr('name') or { panic(err) }
	println('first service: ${first_name.str()}')

	active_svcs := sdoc.select_all('//service[@active=true]') or { panic(err) }
	for svc in active_svcs {
		n := svc.attr('name') or { continue }
		println('active: ${n.str()}')
	}

	println('\n=== Transform Demo ===\n')

	updated_doc := sdoc.transform('services/service', fn(mut el cxlib.Element) cxlib.Element {
		el.set_attr('name', cxlib.ScalarVal('renamed-auth'))
		return el
	}) or { panic(err) }
	println('After transform:')
	println(updated_doc.to_cx())

	all_active_doc := sdoc.transform_all('//service', fn(mut el cxlib.Element) cxlib.Element {
		el.set_attr('active', cxlib.ScalarVal(true))
		return el
	}) or { panic(err) }
	after_all := all_active_doc.select_all('//service[@active=true]') or { panic(err) }
	println('Active services after transform_all: ${after_all.len}')
}
