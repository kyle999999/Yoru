// SPDX-License-Identifier: GPL-3.0-only
package main

import (
	"context"
	"sync"
	"time"
)

// Serialize a source's interpreter, not all sources. Only brief bookkeeping
// uses mu; loading, guest execution, network requests and Close run without it.
type sourcePool[T any] struct {
	mu      sync.Mutex
	entries map[string]*poolEntry[T]
	workers chan struct{}
	close   func(T)
}

type poolEntry[T any] struct {
	gate          chan struct{}
	value         T
	path          string
	ready, active bool
	users         int
	used          time.Time
}

func newSourcePool[T any](limit int, close func(T)) *sourcePool[T] {
	return &sourcePool[T]{entries: make(map[string]*poolEntry[T]), workers: make(chan struct{}, limit), close: close}
}

func waitSlot(ctx context.Context, slot chan struct{}) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	select {
	case slot <- struct{}{}:
		if err := ctx.Err(); err != nil {
			<-slot
			return err
		}
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}

func (p *sourcePool[T]) acquire(ctx context.Context, id, path string, load func(context.Context) (T, error)) (T, func(), error) {
	var zero T
	p.mu.Lock()
	e := p.entries[id]
	if e == nil {
		e = &poolEntry[T]{gate: make(chan struct{}, 1)}
		p.entries[id] = e
	}
	e.users++
	p.mu.Unlock()
	unref := func() {
		p.mu.Lock()
		e.users--
		if e.users == 0 && !e.ready {
			delete(p.entries, id)
		}
		p.mu.Unlock()
	}
	if err := waitSlot(ctx, e.gate); err != nil {
		unref()
		return zero, nil, err
	}
	if err := waitSlot(ctx, p.workers); err != nil {
		<-e.gate
		unref()
		return zero, nil, err
	}
	p.mu.Lock()
	e.active = true
	e.used = time.Now()
	var evicted []T
	if e.ready && (load == nil || e.path != path) {
		evicted = append(evicted, e.value)
		e.value = zero
		e.ready = false
	}
	// Reserve a cache slot for loading too. Never evict a running interpreter.
	for {
		occupied := 0
		var oldest *poolEntry[T]
		for _, other := range p.entries {
			if other.ready || other.active {
				occupied++
			}
			if other.ready && !other.active && (oldest == nil || other.used.Before(oldest.used)) {
				oldest = other
			}
		}
		if occupied <= cap(p.workers) || oldest == nil {
			break
		}
		evicted = append(evicted, oldest.value)
		oldest.value = zero
		oldest.ready = false
		for key, other := range p.entries {
			if other == oldest && other.users == 0 {
				delete(p.entries, key)
			}
		}
	}
	p.mu.Unlock()
	var released sync.Once
	release := func() {
		released.Do(func() {
			p.mu.Lock()
			e.active = false
			e.used = time.Now()
			p.mu.Unlock()
			<-p.workers
			<-e.gate
			unref()
		})
	}
	leased := false
	defer func() {
		if !leased {
			release()
		}
	}()
	for _, value := range evicted {
		p.close(value)
	}
	if load != nil && !e.ready {
		value, err := load(ctx)
		if err != nil {
			release()
			return zero, nil, err
		}
		p.mu.Lock()
		e.value = value
		e.path = path
		e.ready = true
		p.mu.Unlock()
	}
	leased = true
	return e.value, release, nil
}

// Caller holds this entry's lease. A cancelled wazero call can close its VM;
// discard it so the next request creates a fresh interpreter.
func (p *sourcePool[T]) discard(id string) {
	p.mu.Lock()
	e := p.entries[id]
	var value T
	ready := e != nil && e.ready
	if ready {
		value = e.value
		var zero T
		e.value = zero
		e.ready = false
	}
	p.mu.Unlock()
	if ready {
		p.close(value)
	}
}
