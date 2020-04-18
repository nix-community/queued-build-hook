package main // import "github.com/nix-community/queued-build-hook"

import (
	"flag"
	"fmt"
	"log"
	"os"
)

func main() {

	stderr := log.New(os.Stderr, "queued-build-hook: ", 0)

	daemonCommand := flag.NewFlagSet("daemon", flag.ExitOnError)
	realHook := daemonCommand.String("hook", "", "Path to the 'real' post-build-hook")
	retryInterval := daemonCommand.Int("retry-interval", 1, "Retry interval (in seconds)")
	retries := daemonCommand.Int("retries", 5, "How many retries to attempt before dropping")

	queueCommand := flag.NewFlagSet("queue", flag.ExitOnError)
	sockPath := queueCommand.String("socket", "", "Path to daemon socket")

	printDefaults := func() {
		fmt.Println(fmt.Sprintf("Usage: \"%s daemon\" or \"%s queue\"", os.Args[0], os.Args[0]))

		fmt.Println("\nUsage of daemon:")
		daemonCommand.PrintDefaults()

		fmt.Println("\nUsage of queue:")
		queueCommand.PrintDefaults()
	}

	if len(os.Args) <= 1 {
		printDefaults()
		os.Exit(1)
	}
	switch os.Args[1] {
	case "daemon":
		daemonCommand.Parse(os.Args[2:])
	case "queue":
		queueCommand.Parse(os.Args[2:])
	}

	if daemonCommand.Parsed() {
		hook := *realHook
		if hook == "" {
			panic("Missing required flag hook")
		}
		RunDaemon(stderr, hook, *retryInterval, *retries)

	} else if queueCommand.Parsed() {
		sock := *sockPath
		if sock == "" {
			panic("Missing required flag socket")
		}

		err := RunClient(sock)
		if err != nil {
			panic(err)
		}

	} else {
		panic("No supported command parsed")
	}

}
