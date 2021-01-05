package main

import (
	"net"
	"os"
)

func runClient(sock string, m interface{}) error {
	b, err := EncodeMessage(m)
	if err != nil {
		return err
	}

	conn, err := net.Dial("unix", sock)
	if err != nil {
		return err
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
