package main

import (
	"math"
	"net"
	"os"
	"time"
)

func runClient(sock string, m interface{}) error {
	b, err := EncodeMessage(m)
	if err != nil {
		return err
	}

	didFail := func(l []error) bool {
		if len(l) > 10 {
			return true
		} else {
			return false
		}
	}
	conn, errs := tryConnect("unix", sock, expBackoff(2, 100*time.Millisecond), []error{}, didFail)

	if errs != nil {
		return errs[0]
	}

	unixConn := conn.(*net.UnixConn)
	defer unixConn.Close()

	// Write the message and send EOF.
	_, err = unixConn.Write(b)
	if err != nil {
		return err
	}
	if err := unixConn.CloseWrite(); err != nil {
		return err
	}

	// Wait for remote to close the connection.
	_, err = unixConn.Read([]byte{0})
	if err != nil && err.Error() != "EOF" {
		return err
	}

	return nil
}

func tryConnect(network, addr string, retryDelay func([]error) time.Duration, prevErrors []error, hasFailed func([]error) bool) (net.Conn, []error) {
	if hasFailed(prevErrors) {
		return nil, prevErrors
	} else {
		conn, conn_err := net.Dial("unix", addr)
		if conn != nil {
			return conn, nil
		}
		errors := append(prevErrors, conn_err)
		dur := retryDelay(errors)
		time.Sleep(dur)
		return tryConnect(network, addr, retryDelay, errors, hasFailed)
	}
	return nil, nil
}

func RunQueueClient(sock string, tag string) error {
	return runClient(sock, &QueueMessage{
		DrvPath:  os.Getenv("DRV_PATH"),
		OutPaths: os.Getenv("OUT_PATHS"),
		Tag:      tag,
	})
}

func RunWaitClient(sock string, tag string) error {
	return runClient(sock, &WaitMessage{
		Tag: tag,
	})
}

func expBackoff(factor uint, start time.Duration) func(l []error) time.Duration {
	return func(l []error) time.Duration {
		n := len(l)
		return time.Duration(int(math.Pow(float64(factor), float64(n)))) * start
	}
}
