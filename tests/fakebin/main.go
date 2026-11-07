// Command fakebin stands in for an OT Fabric CLI in the Windows installer
// tests. Built with -ldflags "-X main.broken=1", `version` fails.
package main

import (
	"fmt"
	"os"
)

var broken = ""

func main() {
	if len(os.Args) > 1 && os.Args[1] == "version" {
		if broken != "" {
			fmt.Fprintln(os.Stderr, "cannot run")
			os.Exit(1)
		}
		fmt.Println("fakebin version: test")
		return
	}
	fmt.Println("fakebin", os.Args[1:])
}
