package main

import (
	"encoding/json"
	"time"
)

type message struct {
	DrvPath  string `json:"DRV_PATH"`
	OutPaths string `json:"OUT_PATHS"`
}

type QueuedMessage struct {
	IncomingTime int64
	Retries      int
	DrvPath      string
	OutPaths     string
}

func DecodeMessage(b []byte, retries int) (*QueuedMessage, error) {

	m := message{}
	err := json.Unmarshal(b, &m)
	if err != nil {
		return nil, err
	}

	q := &QueuedMessage{
		IncomingTime: time.Now().Unix(),
		Retries:      retries,
		DrvPath:      m.DrvPath,
		OutPaths:     m.OutPaths,
	}
	return q, nil

}
