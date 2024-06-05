package main

import (
	"testing"
	"time"
)

func TestReconnect(t *testing.T) {
	type args struct {
		sock       string
		retryDelay func([]error) time.Duration
		prevErrors []error
		hasFailed  func([]error) bool
	}
	type testCase struct {
		setup    func()
		input    args
		expect   func([]error) bool
		teardown func()
	}

	cases := []testCase{
		{
			setup: func() {
				// create UNIX domain socket
			},
			input: args{
				sock: "/tmp/enoent",
				retryDelay: func(errors []error) time.Duration {
					return 1 * time.Second
				},
				prevErrors: []error{},
				hasFailed: func(errors []error) bool {
					if len(errors) < 20 {
						return false
					}
					return true
				},
			},
			expect: func([]error) bool {
				return true
			},
			teardown: func() {
			},
		},
	}

	for _, c := range cases {
		_, got := tryConnect("unix", c.input.sock, c.input.retryDelay, c.input.prevErrors, c.input.hasFailed)

		if !c.expect(got) {
			panic("got something different than we expected")
		}

	}
}
