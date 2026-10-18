package main

import (
	"fmt"
	"os"
	"runtime"
)

var (
	version = "dev"
	commit  = "none"
	date    = "unknown"
)

func main() {
	if len(os.Args) > 1 && (os.Args[1] == "version" || os.Args[1] == "--version" || os.Args[1] == "-v") {
		fmt.Printf("zeroconflict version %s (commit: %s, built: %s, os/arch: %s/%s)\n", version, commit, date, runtime.GOOS, runtime.GOARCH)
		return
	}

	fmt.Printf("ZeroConflict CLI (%s)\n", version)
	fmt.Println("Run 'zeroconflict --help' for usage.")
}
