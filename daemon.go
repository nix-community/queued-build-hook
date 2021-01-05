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

func RunDaemon(stderr *log.Logger, realHook string, retryInterval int, retries int) {

	listeners, err := ListenSystemdFds()
	if err != nil {
		panic(err)
	}

	if len(listeners) < 1 {
		panic("Unexpected number of socket activation fds")
	}

	connections := make(chan net.Conn)
	queueRequests := make(chan *QueueMessage)
	queueCompleted := make(chan *QueueMessage)
	waitRequests := make(chan chan struct{})
	waiters := []chan struct{}{}
	inProgress := 0

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
					waiter := make(chan struct{})
					waitRequests <- waiter
					<-waiter
				}
			}()

		case m := <-queueRequests:
			inProgress += 1
			go func() {
				defer func() {
					queueCompleted <- m
				}()

				env := os.Environ()
				if m.DrvPath != "" {
					env = append(env, fmt.Sprintf("DRV_PATH=%s", m.DrvPath))
				}
				if m.OutPaths != "" {
					env = append(env, fmt.Sprintf("OUT_PATHS=%s", m.OutPaths))
				}

				msgRetries := retries
				for msgRetries != 0 {
					cmd := exec.Command(realHook)
					cmd.Stdout = os.Stdout
					cmd.Stderr = os.Stderr
					cmd.Env = env
					err := cmd.Run()
					if err != nil {
						msgRetries -= 1
						time.Sleep(time.Duration(retryInterval) * time.Second)
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
				errorMessage = fmt.Sprintf("%s after %d retries", errorMessage, retries)
				stderr.Print(errorMessage)
			}()

		case <-queueCompleted:
			inProgress -= 1
			if inProgress == 0 {
				for _, waiter := range waiters {
					waiter <- struct{}{}
				}
				waiters = []chan struct{}{}
			}

		case waiter := <-waitRequests:
			if inProgress == 0 {
				waiter <- struct{}{}
			} else {
				waiters = append(waiters, waiter)
			}
		}
	}

}
