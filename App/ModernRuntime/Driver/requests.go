// SPDX-License-Identifier: GPL-3.0-only
package main

import (
	"context"
	"fmt"
	"sync"
	"time"
)

type searchRequest struct {
	ctx    context.Context
	cancel context.CancelFunc
}

var searchRequests = struct {
	sync.Mutex
	items map[string]searchRequest
}{items: make(map[string]searchRequest)}

func requestControl(op, id string) error {
	if id == "" {
		return fmt.Errorf("missing search request ID")
	}
	searchRequests.Lock()
	defer searchRequests.Unlock()
	switch op {
	case "beginSearch":
		if _, exists := searchRequests.items[id]; exists {
			return fmt.Errorf("duplicate search request ID")
		}
		ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
		searchRequests.items[id] = searchRequest{ctx: ctx, cancel: cancel}
	case "cancelSearch":
		if r, exists := searchRequests.items[id]; exists {
			r.cancel()
		}
	case "endSearch":
		if r, exists := searchRequests.items[id]; exists {
			r.cancel()
			delete(searchRequests.items, id)
		}
	}
	return nil
}

func searchContext(id string) (context.Context, error) {
	searchRequests.Lock()
	defer searchRequests.Unlock()
	if r, exists := searchRequests.items[id]; exists {
		return r.ctx, nil
	}
	return nil, fmt.Errorf("search request has ended")
}
