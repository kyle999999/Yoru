// SPDX-License-Identifier: GPL-3.0-only
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/ohaiibuzzle/aidokurunner-go/runtime/host"
	"github.com/tetratelabs/wazero"
	"github.com/tetratelabs/wazero/api"
)

type nativeView struct{ id string }

func (v nativeView) Close() error {
	native(map[string]any{"op": "webview", "action": "close", "id": v.id})
	return nil
}
func viewString(m api.Module, p, n int32) string {
	b, ok := m.Memory().Read(uint32(p), uint32(n))
	if !ok {
		return ""
	}
	return string(b)
}
func linkNativeViews(builder wazero.HostModuleBuilder, store *host.Store) wazero.HostModuleBuilder {
	invoke := func(d int32, op string, args map[string]any) (map[string]any, bool) {
		v, ok := store.Fetch(d).(nativeView)
		if !ok {
			return nil, false
		}
		args["op"] = "webview"
		args["action"] = op
		args["id"] = v.id
		r, ok := native(args)
		if !ok {
			return nil, false
		}
		if e, _ := r["error"].(string); e != "" {
			return nil, false
		}
		return r, true
	}
	builder.NewFunctionBuilder().WithFunc(func() int32 {
		r, ok := native(map[string]any{"op": "webview", "action": "create"})
		if !ok {
			return -2
		}
		id, _ := r["id"].(string)
		return store.Store(nativeView{id: id})
	}).Export("webview_create")
	builder.NewFunctionBuilder().WithFunc(func(ctx context.Context, d, r int32) int32 {
		request, ok := store.Fetch(r).(*host.NetRequest)
		if !ok {
			return -5
		}
		req, e := request.ToHTTPRequest(ctx)
		if e != nil {
			return -5
		}
		_, ok = invoke(d, "load", map[string]any{"url": req.URL.String(), "method": req.Method, "headers": req.Header, "body": request.Body})
		if !ok {
			return -1
		}
		return 0
	}).Export("webview_load")
	builder.NewFunctionBuilder().WithFunc(func(ctx context.Context, m api.Module, d, p, n, u, l int32) int32 {
		_, ok := invoke(d, "html", map[string]any{"html": viewString(m, p, n), "url": viewString(m, u, l)})
		if !ok {
			return -1
		}
		return 0
	}).Export("webview_load_html")
	builder.NewFunctionBuilder().WithFunc(func(d int32) int32 {
		_, ok := invoke(d, "wait", map[string]any{})
		if !ok {
			return -1
		}
		return 0
	}).Export("webview_wait_for_load")
	for _, name := range []string{"webview_eval", "webview_eval_async"} {
		async := name == "webview_eval_async"
		builder.NewFunctionBuilder().WithFunc(func(ctx context.Context, m api.Module, d, p, n int32) int32 {
			r, ok := invoke(d, "eval", map[string]any{"script": viewString(m, p, n), "async": async})
			if !ok {
				return -1
			}
			v, ok := r["value"]
			if !ok {
				return -1
			}
			if s, ok := v.(string); ok {
				return store.Store([]byte(s))
			}
			b, e := json.Marshal(v)
			if e != nil {
				return -1
			}
			return store.Store(b)
		}).Export(name)
	}
	builder.NewFunctionBuilder().WithFunc(func(ctx context.Context, m api.Module, d, p, n int32) int32 {
		_, ok := invoke(d, "rules", map[string]any{"rules": viewString(m, p, n)})
		if !ok {
			return -6
		}
		return 0
	}).Export("webview_set_rule_list")
	builder.NewFunctionBuilder().WithFunc(func(ctx context.Context, m api.Module, d, p, n, end, main int32) int32 {
		_, ok := invoke(d, "script", map[string]any{"script": viewString(m, p, n), "end": end != 0, "main": main != 0})
		if !ok {
			return -1
		}
		return 0
	}).Export("webview_add_user_script")
	builder.NewFunctionBuilder().WithFunc(func(d int32) int32 {
		r, ok := invoke(d, "cookies", map[string]any{})
		if !ok {
			return -1
		}
		b, e := json.Marshal(r["value"])
		if e != nil {
			return -1
		}
		return store.Store(b)
	}).Export("webview_get_cookies")
	builder.NewFunctionBuilder().WithFunc(func(ctx context.Context, m api.Module, d, np, nl, vp, vl, dp, dl int32) int32 {
		_, ok := invoke(d, "deleteCookie", map[string]any{"name": viewString(m, np, nl), "value": viewString(m, vp, vl), "domain": viewString(m, dp, dl)})
		if !ok {
			return -1
		}
		return 0
	}).Export("webview_delete_cookie")
	_ = fmt.Sprint
	return builder
}
