// CX Document API demo — Go binding.
//
// Run from the cxlib directory:
//
//	cd lang/go/cxlib && go run ./examples/demo/
package main

import (
	"fmt"

	cxlib "github.com/ardec/cx/lang/go"
)

const configSrc = `[config version='1.0' debug=false
  [server host=localhost port=8080]
  [database url='postgres://localhost/mydb' pool=10]
  [cache enabled=true ttl=300]
]`

const servicesSrc = `[services
  [service name=auth  port=8080 active=true]
  [service name=api   port=9000 active=false]
  [service name=web   port=80   active=true]
]`

func main() {
	documentModelDemo()
	streamingDemo()
	cxpathDemo()
	transformDemo()
}

// ── 1. Document Model ─────────────────────────────────────────────────────────

func documentModelDemo() {
	fmt.Println("=== Document Model ===")

	doc, err := cxlib.Parse(configSrc)
	if err != nil {
		panic(err)
	}

	// Read server attrs via path navigation
	server := doc.At("config/server")
	fmt.Printf("host: %v\n", server.Attr("host"))
	fmt.Printf("port: %v\n", server.Attr("port"))

	// Update host to production value
	server.SetAttr("host", "prod.example.com", "")

	// Append a timeout child element
	server.Append(&cxlib.Element{
		Name:  "timeout",
		Items: []cxlib.Node{&cxlib.ScalarNode{DataType: "int", Value: int64(30)}},
	})

	// Remove the cache element
	config := doc.Root()
	cache := config.Get("cache")
	config.Remove(cache)

	fmt.Println("\n--- Result CX ---")
	fmt.Println(doc.ToCx())
}

// ── 2. Streaming ──────────────────────────────────────────────────────────────

func streamingDemo() {
	fmt.Println("\n=== Streaming ===")

	events, err := cxlib.Stream(configSrc)
	if err != nil {
		panic(err)
	}

	for _, ev := range events {
		if ev.Type == "StartElement" {
			fmt.Printf("element: %s", ev.Name)
			for _, a := range ev.Attrs {
				fmt.Printf("  %s=%v", a.Name, a.Value)
			}
			fmt.Println()
		}
	}
}

// ── 3. CXPath Select ─────────────────────────────────────────────────────────

func cxpathDemo() {
	fmt.Println("\n=== CXPath Select ===")

	doc, err := cxlib.Parse(servicesSrc)
	if err != nil {
		panic(err)
	}

	// First match
	first, err := doc.Select("//service")
	if err != nil {
		panic(err)
	}
	fmt.Printf("first service: %v\n", first.Attr("name"))

	// Filtered by attribute predicate
	active, err := doc.SelectAll("//service[@active=true]")
	if err != nil {
		panic(err)
	}
	for _, svc := range active {
		fmt.Printf("active: %v\n", svc.Attr("name"))
	}
}

// ── 4. Transform ──────────────────────────────────────────────────────────────

func transformDemo() {
	fmt.Println("\n=== Transform ===")

	doc, err := cxlib.Parse(servicesSrc)
	if err != nil {
		panic(err)
	}

	// Immutable path-targeted update: rename first service
	updated := doc.Transform("services/service", func(el *cxlib.Element) *cxlib.Element {
		el.SetAttr("name", "renamed-auth", "")
		return el
	})
	fmt.Println("After transform (rename auth):")
	fmt.Println(updated.ToCx())

	// Apply function to every matching element
	allActive, err := doc.TransformAll("//service", func(el *cxlib.Element) *cxlib.Element {
		el.SetAttr("active", true, "bool")
		return el
	})
	if err != nil {
		panic(err)
	}
	results, err := allActive.SelectAll("//service[@active=true]")
	if err != nil {
		panic(err)
	}
	fmt.Printf("Active services after transformAll: %d\n", len(results))
}
