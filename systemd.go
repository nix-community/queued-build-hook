package main

import (
	"errors"
	"net"
	"os"
	"strconv"
	"syscall"
)

// fnctl syscall wrapper
func fcntl(fd int, cmd int, arg int) (int, int) {
	r0, _, e1 := syscall.Syscall(syscall.SYS_FCNTL, uintptr(fd), uintptr(cmd), uintptr(arg))
	return int(r0), int(e1)
}

// ListenSystemdFds - Listen to FDs provided by systemd
func ListenSystemdFds() ([]net.Listener, error) {
	const listenFdsStart = 3

	pid, err := strconv.Atoi(os.Getenv("LISTEN_PID"))
	if err != nil || pid != os.Getpid() {
		if err == nil {
			return nil, err
		} else if pid != os.Getpid() {
			return nil, errors.New("Systemd pid mismatch")
		}
	}

	nfds, err := strconv.Atoi(os.Getenv("LISTEN_FDS"))
	if err != nil || nfds == 0 {
		if err == nil {
			return nil, err
		} else if nfds == 0 {
			return nil, errors.New("nfds is zero (could not listen to any provided fds)")
		}
	}

	listeners := []net.Listener(nil)
	for fd := listenFdsStart; fd < listenFdsStart+nfds; fd++ {
		flags, errno := fcntl(fd, syscall.F_GETFD, 0)
		if errno != 0 {
			if errno != 0 {
				return nil, syscall.Errno(errno)
			}
		}
		if flags&syscall.FD_CLOEXEC != 0 {
			continue
		}
		syscall.CloseOnExec(fd)

		file := os.NewFile(uintptr(fd), "")
		listener, err := net.FileListener(file)
		if err != nil {
			return nil, err
		}

		listeners = append(listeners, listener)
	}

	return listeners, nil
}
