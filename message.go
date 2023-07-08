package main

import (
	"encoding/json"
	"errors"
)

type envelope struct {
	Action  string
	Payload json.RawMessage
}

type QueueMessage struct {
	DrvPath  string `json:"DRV_PATH"`
	OutPaths string `json:"OUT_PATHS"`
	Tag      string `json:"TAG"`
}

type WaitMessage struct {
	Tag string `json:"TAG"`
}

func EncodeMessage(m interface{}) ([]byte, error) {
	switch m := m.(type) {
	case *QueueMessage:
		b, err := json.Marshal(m)
		if err != nil {
			return nil, err
		}
		return json.Marshal(envelope{
			Action:  "queue",
			Payload: b,
		})
	case *WaitMessage:
		b, err := json.Marshal(m)
		if err != nil {
			return nil, err
		}
		return json.Marshal(envelope{
			Action:  "wait",
			Payload: b,
		})
	default:
		return nil, errors.New("invalid message")
	}
}

func DecodeMessage(b []byte) (interface{}, error) {
	env := envelope{}
	err := json.Unmarshal(b, &env)
	if err != nil {
		return nil, err
	}

	switch env.Action {
	case "queue":
		m := &QueueMessage{}
		err := json.Unmarshal(env.Payload, m)
		return m, err
	case "wait":
		m := &WaitMessage{}
		err := json.Unmarshal(env.Payload, m)
		return m, err
	default:
		return nil, errors.New("invalid action")
	}
}
