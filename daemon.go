package main

import (
	"fmt"
	"io/ioutil"
	"log"
	"net"
	"os"
	"os/exec"
	"time"
)

type Waiter struct {
	Reply chan struct{}
	Tag   string
}

type DaemonConfig struct {
	RetryInterval int
	Retries       int
	Concurrency   int
}

func RunDaemon(stderr *log.Logger, realHook string, config *DaemonConfig) {
	listeners, err := ListenSystemdFds()
	if err != nil {
		panic(err)
	}

	if len(listeners) < 1 {
		panic("Unexpected number of socket activation fds")
	}

	// State variables, accessed only from the main goroutine.
	waiters := []*Waiter{}
	inProgress := 0
	inProgressTags := make(map[string]int)

	// Channels for communicating with the main goroutine.
	connections := make(chan net.Conn)
	queueRequests := make(chan *QueueMessage)
	queueCompleted := make(chan *QueueMessage)
	waitRequests := make(chan *Waiter)

	// Channel for communicating with workers.
	workerRequests := make(chan *QueueMessage, 256)

	// Execute hook for one request.
	execOne := func(m *QueueMessage) {
		defer func() {
			// Note: the main goroutine may be blocking trying to submit a job to us.
			// Send the completion in a new goroutine to prevent blocking here as
			// well, which would create a deadlock.
			go func() {
				queueCompleted <- m
			}()
		}()

		env := os.Environ()
		if m.DrvPath != "" {
			env = append(env, fmt.Sprintf("DRV_PATH=%s", m.DrvPath))
		}
		if m.OutPaths != "" {
			env = append(env, fmt.Sprintf("OUT_PATHS=%s", m.OutPaths))
		}

		msgRetries := config.Retries
		for msgRetries != 0 {
			cmd := exec.Command(realHook)
			cmd.Stdout = os.Stdout
			cmd.Stderr = os.Stderr
			cmd.Env = env
			err := cmd.Run()
			if err != nil {
				msgRetries -= 1
				time.Sleep(time.Duration(config.RetryInterval) * time.Second)
				continue
			}
			return
		}

		errorMessage := "Dropped message"
		if m.DrvPath != "" {
			errorMessage = fmt.Sprintf("%s with DRV_PATH '%s'", errorMessage, m.DrvPath)
		}
		if m.OutPaths != "" {
			errorMessage = fmt.Sprintf("%s with OUT_PATHS '%s'", errorMessage, m.OutPaths)
		}
		errorMessage = fmt.Sprintf("%s after %d retries", errorMessage, config.Retries)
		stderr.Print(errorMessage)
	}

	// Worker goroutines.
	if config.Concurrency > 0 {
		worker := func() {
			for {
				m := <-workerRequests
				execOne(m)
			}
		}
		for i := 0; i < config.Concurrency; i++ {
			go worker()
		}
	} else {
		// Infinite concurrency.
		go func() {
			for {
				m := <-workerRequests
				go execOne(m)
			}
		}()
	}

	// Launch a goroutine for each listener.
	for _, listener := range listeners {
		go func(l net.Listener) {
			for {
				c, err := l.Accept()
				if err != nil {
					stderr.Print(err)
					return
				}
				connections <- c
			}
		}(listener)
	}

	for {
		select {
		case c := <-connections:
			// Launch a goroutine for each connection.
			go func() {
				defer c.Close()

				b, err := ioutil.ReadAll(c)
				if err != nil {
					stderr.Print(err)
					return
				}

				m, err := DecodeMessage(b)
				if err != nil {
					stderr.Print(err)
					return
				}

				switch m := m.(type) {
				case *QueueMessage:
					queueRequests <- m
				case *WaitMessage:
					reply := make(chan struct{})
					waitRequests <- &Waiter{
						Reply: reply,
						Tag:   m.Tag,
					}
					<-reply
				}
			}()

		case m := <-queueRequests:
			// Forward requests to workers, and track progress.
			inProgress += 1
			if m.Tag != "" {
				n, _ := inProgressTags[m.Tag]
				inProgressTags[m.Tag] = n + 1
			}

			workerRequests <- m

		case m := <-queueCompleted:
			// Scheduler sends us completion.
			inProgress -= 1
			if inProgress == 0 {
				// No jobs at all means there are also no tagged jobs.
				for _, waiter := range waiters {
					waiter.Reply <- struct{}{}
				}
				waiters = []*Waiter{}
				inProgressTags = make(map[string]int)

			} else if m.Tag != "" {
				n := inProgressTags[m.Tag] - 1
				if n > 0 {
					inProgressTags[m.Tag] = n
				} else {
					// Reply and remove just waiters for this tag.
					delete(inProgressTags, m.Tag)
					newWaiters := []*Waiter{}
					for _, w := range waiters {
						if w.Tag == m.Tag {
							w.Reply <- struct{}{}
						} else {
							newWaiters = append(newWaiters, w)
						}
					}
					waiters = newWaiters
				}
			}

		case w := <-waitRequests:
			// A connection wants to wait on the queue.
			if inProgress == 0 {
				w.Reply <- struct{}{}
				break
			}
			if w.Tag != "" {
				n, _ := inProgressTags[w.Tag]
				if n == 0 {
					w.Reply <- struct{}{}
					break
				}
			}
			waiters = append(waiters, w)
		}
	}

}
