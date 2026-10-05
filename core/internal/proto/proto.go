// Package proto is the wire format between the haseen shell and the sidecar:
// one JSON object per line over a unix socket.
//
// Shape adapted from DankMaterialShell core/internal/proto and its
// Services/DMSService.qml client (MIT, Copyright (c) 2025 Avenge Media LLC):
// the daemon announces its capabilities on connect and the shell gates every
// feature on them, so an old, missing or killed daemon degrades the UI instead
// of breaking it. haseen keeps its own Quickshell IPC for everything else; this
// socket carries sampling only.
package proto

// Version is bumped when the wire format changes in a way a client can see.
const Version = 1

// Frame types.
const (
	TypeHello = "hello" // daemon -> client, once, immediately on connect
	TypeReply = "reply" // daemon -> client, answers one Request.ID
	TypeEvent = "event" // daemon -> client, a sample on a subscribed stream
)

// Methods a client may call.
const (
	MethodSubscribe    = "subscribe"
	MethodUnsubscribe  = "unsubscribe"
	MethodCapabilities = "capabilities"
	MethodShutdown     = "shutdown"
)

// StreamSysusage is the only stream today: CPU, memory, GPU and the process
// list that haseen.sysusage used to poll from QML.
const StreamSysusage = "sysusage"

// Hello is the first line the daemon writes. `capabilities` is the contract:
// a client that does not find its stream there must not use it.
type Hello struct {
	Type         string   `json:"type"`
	Protocol     int      `json:"protocol"`
	Version      string   `json:"version"`
	PID          int      `json:"pid"`
	Capabilities []string `json:"capabilities"`
}

// Request is one client call. ID is echoed in the reply; 0 means "no reply
// wanted".
type Request struct {
	ID     int            `json:"id"`
	Method string         `json:"method"`
	Stream string         `json:"stream,omitempty"`
	Params map[string]any `json:"params,omitempty"`
}

type Reply struct {
	Type         string   `json:"type"`
	ID           int      `json:"id"`
	OK           bool     `json:"ok"`
	Error        string   `json:"error,omitempty"`
	Capabilities []string `json:"capabilities,omitempty"`
}

// Event carries one sample. Data is the stream's own payload.
type Event struct {
	Type   string `json:"type"`
	Stream string `json:"stream"`
	Data   any    `json:"data"`
}
