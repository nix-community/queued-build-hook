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
	queueSockPath := queueCommand.String("socket", "", "Path to daemon socket")
	queueTag := queueCommand.String("tag", "", "Optional tag, for use with wait")

	waitCommand := flag.NewFlagSet("wait", flag.ExitOnError)
	waitSockPath := waitCommand.String("socket", "", "Path to daemon socket")
	waitTag := waitCommand.String("tag", "", "Optional tag to filter on")

	printDefaults := func() {
		fmt.Println(fmt.Sprintf("Usage: \"%s daemon\", \"%s queue\" \"%s wait\"", os.Args[0], os.Args[0], os.Args[0]))

		fmt.Println("\nUsage of daemon:")
		daemonCommand.PrintDefaults()

		fmt.Println("\nUsage of queue:")
		queueCommand.PrintDefaults()

		fmt.Println("\nUsage of wait:")
		waitCommand.PrintDefaults()
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
	case "wait":
		waitCommand.Parse(os.Args[2:])
	}

	if daemonCommand.Parsed() {
		hook := *realHook
		if hook == "" {
			panic("Missing required flag hook")
		}
		RunDaemon(stderr, hook, *retryInterval, *retries)

	} else if queueCommand.Parsed() {
		sock := *queueSockPath
		if sock == "" {
			panic("Missing required flag socket")
		}

		err := RunQueueClient(sock, *queueTag)
		if err != nil {
			panic(err)
		}

	} else if waitCommand.Parsed() {
		sock := *waitSockPath
		if sock == "" {
			panic("Missing required flag socket")
		}

		err := RunWaitClient(sock, *waitTag)
		if err != nil {
			panic(err)
		}

	} else {
		panic("No supported command parsed")
	}

}
