// SPDX-License-Identifier: GPL-3.0-only
package main

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

func testContext(t *testing.T) context.Context {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	t.Cleanup(cancel)
	return ctx
}

func TestIndependentSourcesDoNotWaitForSlowSource(t *testing.T) {
	p := newSourcePool[int](3, func(int) {})
	ctx := testContext(t)
	_, release, err := p.acquire(ctx, "slow", "", func(context.Context) (int, error) { return 1, nil })
	if err != nil {
		t.Fatal(err)
	}
	defer release()
	done := make(chan error, 1)
	go func() {
		_, release, err := p.acquire(ctx, "fast", "", func(context.Context) (int, error) { return 2, nil })
		if err == nil {
			release()
		}
		done <- err
	}()
	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-ctx.Done():
		t.Fatal("fast source blocked behind slow source")
	}
}

func TestSameSourceWaitCanBeCancelled(t *testing.T) {
	p := newSourcePool[int](3, func(int) {})
	ctx := testContext(t)
	_, release, err := p.acquire(ctx, "same", "", func(context.Context) (int, error) { return 1, nil })
	if err != nil {
		t.Fatal(err)
	}
	defer release()
	waitCtx, cancel := context.WithCancel(ctx)
	done := make(chan error, 1)
	go func() {
		_, _, err := p.acquire(waitCtx, "same", "", func(context.Context) (int, error) { t.Error("overlapping source execution"); return 2, nil })
		done <- err
	}()
	cancel()
	select {
	case err := <-done:
		if !errors.Is(err, context.Canceled) {
			t.Fatal(err)
		}
	case <-ctx.Done():
		t.Fatal("cancel did not unblock wait")
	}
}

func TestEvictionNeverClosesRunningSource(t *testing.T) {
	var closedMu sync.Mutex
	closed := map[int]bool{}
	p := newSourcePool[int](2, func(value int) { closedMu.Lock(); closed[value] = true; closedMu.Unlock() })
	ctx := testContext(t)
	_, hold, err := p.acquire(ctx, "active", "", func(context.Context) (int, error) { return 1, nil })
	if err != nil {
		t.Fatal(err)
	}
	defer hold()
	for i := 2; i < 10; i++ {
		value := i
		_, release, err := p.acquire(ctx, fmt.Sprint(i), "", func(context.Context) (int, error) { return value, nil })
		if err != nil {
			t.Fatal(err)
		}
		release()
	}
	closedMu.Lock()
	defer closedMu.Unlock()
	if closed[1] {
		t.Fatal("active interpreter was evicted")
	}
	if len(closed) != 7 {
		t.Fatalf("expected bounded cache eviction, got %v", closed)
	}
}

func TestSourceReplacementAndClose(t *testing.T) {
	var closed []int
	p := newSourcePool[int](3, func(value int) { closed = append(closed, value) })
	ctx := testContext(t)
	for i, path := range []string{"old", "new"} {
		value := i + 1
		_, release, err := p.acquire(ctx, "source", path, func(context.Context) (int, error) { return value, nil })
		if err != nil {
			t.Fatal(err)
		}
		release()
	}
	_, release, err := p.acquire(ctx, "source", "", nil)
	if err != nil {
		t.Fatal(err)
	}
	release()
	if len(closed) != 2 || closed[0] != 1 || closed[1] != 2 {
		t.Fatal(closed)
	}
}

func TestWorkersBoundedAndSameSourceSerialized(t *testing.T) {
	p := newSourcePool[int](3, func(int) {})
	ctx := testContext(t)
	var workers, peak atomic.Int32
	var active [6]atomic.Int32
	var wg sync.WaitGroup
	for n := 0; n < 60; n++ {
		wg.Add(1)
		go func(id int) {
			defer wg.Done()
			_, release, err := p.acquire(ctx, fmt.Sprint(id), "", func(context.Context) (int, error) { return id, nil })
			if err != nil {
				t.Error(err)
				return
			}
			defer release()
			if active[id].Add(1) != 1 {
				t.Error("same interpreter overlapped")
			}
			n := workers.Add(1)
			for old := peak.Load(); n > old && !peak.CompareAndSwap(old, n); old = peak.Load() {
			}
			time.Sleep(time.Millisecond)
			workers.Add(-1)
			active[id].Add(-1)
		}(n % 6)
	}
	wg.Wait()
	if peak.Load() > 3 {
		t.Fatal("worker limit exceeded", peak.Load())
	}
}

func TestFailureAndPanicReleaseWorkers(t *testing.T) {
	p := newSourcePool[int](1, func(int) {})
	ctx := testContext(t)
	_, _, err := p.acquire(ctx, "failure", "", func(context.Context) (int, error) { return 0, errors.New("load failed") })
	if err == nil {
		t.Fatal("expected load failure")
	}
	func() {
		defer func() {
			if recover() == nil {
				t.Error("expected panic")
			}
		}()
		p.acquire(ctx, "panic", "", func(context.Context) (int, error) { panic("load panic") })
	}()
	_, release, err := p.acquire(ctx, "works", "", func(context.Context) (int, error) { return 1, nil })
	if err != nil {
		t.Fatal(err)
	}
	release()
}

func TestSearchCancellationLifecycle(t *testing.T) {
	id := "test-search"
	if err := requestControl("beginSearch", id); err != nil {
		t.Fatal(err)
	}
	defer requestControl("endSearch", id)
	ctx, err := searchContext(id)
	if err != nil {
		t.Fatal(err)
	}
	requestControl("cancelSearch", id)
	if !errors.Is(ctx.Err(), context.Canceled) {
		t.Fatal(ctx.Err())
	}
	requestControl("endSearch", id)
	if _, err := searchContext(id); err == nil {
		t.Fatal("finished request retained")
	}
}
