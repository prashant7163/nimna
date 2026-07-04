// Command relay is the Nimna relay: a stateless WebSocket router that
// bridges exactly two live device connections and stores nothing.
//
// The complete at-rest inventory of a running relay is: routing tables in
// memory, TLS certificates, and push credentials supplied as deployment
// configuration (spec §4). Protocol behavior lands in Sessions 3–5; this
// is the Session 1 scaffold.
package main

import "fmt"

const version = "0.0.1-dev"

func main() {
	fmt.Printf("nimna-relay %s — scaffold, no protocol behavior yet\n", version)
}
