package database

import (
	"errors"
	"fmt"
)

// ErrNotFound reports that the requested record does not exist (or is not
// visible to the given user). Match with errors.Is; implementations wrap it
// with call-site context.
var ErrNotFound = errors.New("record not found")

// A claimed revision is unavailable to new instances until cleanup finishes.
var ErrRuntimeRevisionDeleting = fmt.Errorf("runtime revision is being deleted: %w", ErrNotFound)

var ErrIdempotencyConflict = errors.New("request id was already used with different parameters")

var ErrAgentInstanceConflict = errors.New("AgentInstance lifecycle operation conflicts with its current state")

var ErrAgentInstanceTaskConflict = errors.New("AgentInstance already has an active task")

var ErrAgentInstanceNotQuiescent = errors.New("AgentInstance has no quiescent turn boundary")
