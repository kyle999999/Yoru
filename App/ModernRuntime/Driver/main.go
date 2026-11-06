// Yoru native bridge. SPDX-License-Identifier: GPL-3.0-only
package main

/*
#include <stdlib.h>
#include <stdint.h>
typedef char* (*YoruHostCallback)(const char*);
static YoruHostCallback nativeHost;
static void setNativeHost(uintptr_t p) { nativeHost = (YoruHostCallback)p; }
static char* callNativeHost(const char* p) { return nativeHost ? nativeHost(p) : NULL; }
*/
import "C"
import (
	"archive/zip"
	"bufio"
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/ohaiibuzzle/aidokurunner-go/models"
	engine "github.com/ohaiibuzzle/aidokurunner-go/runtime"
	"github.com/ohaiibuzzle/aidokurunner-go/runtime/host"
	"github.com/ohaiibuzzle/aidokurunner-go/source"
	"github.com/tetratelabs/wazero"
	"image"
	"image/png"
	"io"
	"net/http"
	"os"
	"sync"
	"time"
	"unsafe"
)

type command struct {
	Op, ID, Path, Query, URL, Key, Notification, Username, Password string
	Page                                                            int
	Manga                                                           models.Manga
	Chapter                                                         models.Chapter
	Listing                                                         models.Listing
	Filters                                                         []models.FilterValue
	Context                                                         *models.PageContext
	Cookies                                                         map[string]string
	Cover                                                           bool
}
type answer struct {
	Value any    `json:"value,omitempty"`
	Error string `json:"error,omitempty"`
}

var mu sync.Mutex
var loaded = map[string]*source.Source{}
var paths = map[string]string{}
var used = map[string]time.Time{}

func ptrString(s string) *string { return &s }
func native(v any) (map[string]any, bool) {
	b, _ := json.Marshal(v)
	p := C.CString(string(b))
	defer C.free(unsafe.Pointer(p))
	out := C.callNativeHost(p)
	if out == nil {
		return nil, false
	}
	defer C.free(unsafe.Pointer(out))
	var r map[string]any
	json.Unmarshal([]byte(C.GoString(out)), &r)
	return r, true
}

type settings struct{ values map[string]any }

func settingValue(v any, kind string) any {
	switch kind {
	case "data":
		if s, ok := v.(string); ok {
			b, _ := base64.StdEncoding.DecodeString(s)
			return b
		}
	case "float":
		if n, ok := v.(float64); ok {
			return float32(n)
		}
	case "int":
		if n, ok := v.(float64); ok {
			return int32(n)
		}
	}
	if a, ok := v.([]any); ok {
		r := make([]string, 0, len(a))
		for _, x := range a {
			if t, ok := x.(string); ok {
				r = append(r, t)
			}
		}
		return r
	}
	return v
}
func settingMessage(op, k string, v any) map[string]any {
	r := map[string]any{"op": op, "key": k, "value": v}
	switch v.(type) {
	case []byte:
		r["type"] = "data"
	case float32, float64:
		r["type"] = "float"
	case int, int32, int64:
		r["type"] = "int"
	}
	return r
}
func (s *settings) Object(k string) any {
	if r, ok := native(map[string]any{"op": "getSetting", "key": k}); ok {
		if v, exists := r["value"]; exists {
			kind, _ := r["type"].(string)
			return settingValue(v, kind)
		}
	}
	return s.values[k]
}
func (s *settings) SetValue(k string, v any) error {
	s.values[k] = v
	native(settingMessage("setSetting", k, v))
	return nil
}
func (s *settings) RegisterDefault(k string, v any) {
	if s.Object(k) == nil {
		s.values[k] = v
		native(settingMessage("registerSetting", k, v))
	}
}

var prefs = &settings{values: map[string]any{}}

type transport struct{}

func (transport) RoundTrip(req *http.Request) (*http.Response, error) {
	var body []byte
	if req.Body != nil {
		body, _ = io.ReadAll(io.LimitReader(req.Body, 64<<20))
	}
	r, ok := native(map[string]any{"op": "http", "url": req.URL.String(), "method": req.Method, "headers": req.Header, "body": body})
	if !ok {
		if body != nil {
			req.Body = io.NopCloser(bytes.NewReader(body))
		}
		return http.DefaultTransport.RoundTrip(req)
	}
	if e, _ := r["error"].(string); e != "" {
		return nil, fmt.Errorf("%s", e)
	}
	raw, _ := json.Marshal(r)
	var out struct {
		Status  int
		Headers http.Header
		Body    []byte
		URL     string
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil, err
	}
	if out.URL != "" {
		u, e := req.URL.Parse(out.URL)
		if e == nil {
			copy := req.Clone(req.Context())
			copy.URL = u
			req = copy
		}
	}
	return &http.Response{StatusCode: out.Status, Header: out.Headers, Body: io.NopCloser(bytes.NewReader(out.Body)), Request: req}, nil
}
func nativeViewLink() func(wazero.HostModuleBuilder, *host.Store) wazero.HostModuleBuilder {
	if _, ok := native(map[string]any{"op": "available"}); ok {
		return linkNativeViews
	}
	return nil
}
func acquire(ctx context.Context, c command) (*source.Source, error) {
	if s := loaded[c.ID]; s != nil && paths[c.ID] == c.Path {
		used[c.ID] = time.Now()
		return s, nil
	}
	if s := loaded[c.ID]; s != nil {
		s.Runner.Close(context.Background())
		delete(loaded, c.ID)
	}
	if len(loaded) >= 3 {
		var oldest string
		for k := range loaded {
			if oldest == "" || used[k].Before(used[oldest]) {
				oldest = k
			}
		}
		loaded[oldest].Runner.Close(context.Background())
		delete(loaded, oldest)
	}
	s, e := source.LoadPath(ctx, c.Path, engine.Config{NativeWebView: nativeViewLink(), Settings: prefs, HTTPClient: &http.Client{Transport: transport{}, Timeout: 45 * time.Second}, NetworkConcurrency: 4, PrintHandler: func(m string) { native(map[string]any{"op": "log", "id": c.ID, "message": m}) }}, prefs)
	if e != nil {
		return nil, e
	}
	loaded[c.ID] = s
	paths[c.ID] = c.Path
	used[c.ID] = time.Now()
	return s, nil
}
func execute(c command) (any, error) {
	mu.Lock()
	defer mu.Unlock()
	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()
	if c.Op == "close" {
		if s := loaded[c.ID]; s != nil {
			s.Runner.Close(ctx)
			delete(loaded, c.ID)
		}
		return true, nil
	}
	s, e := acquire(ctx, c)
	if e != nil {
		return nil, e
	}
	switch c.Op {
	case "load":
		return map[string]any{"features": s.Runner.Features, "key": s.Key, "version": s.Version}, nil
	case "listings":
		return s.GetListings(ctx)
	case "filters":
		return s.GetSearchFilters(ctx)
	case "settings":
		return s.GetSettings(ctx)
	case "search":
		q := c.Query
		return s.GetSearchMangaList(ctx, &q, max(c.Page, 1), c.Filters)
	case "browse":
		if c.Listing.ID != "" {
			return s.GetMangaList(ctx, c.Listing, max(c.Page, 1))
		}
		result, err := s.GetSearchMangaList(ctx, nil, max(c.Page, 1), c.Filters)
		var sourceErr *models.SourceError
		if err != nil && errors.As(err, &sourceErr) && sourceErr.Kind == models.SourceErrorUnimplemented && s.Runner.Features.ProvidesHome {
			home, err := s.GetHome(ctx, nil)
			if err != nil {
				return nil, err
			}
			raw, _ := json.Marshal(home)
			var tree any
			json.Unmarshal(raw, &tree)
			entries := []models.Manga{}
			seen := map[string]bool{}
			var walk func(any)
			walk = func(v any) {
				switch node := v.(type) {
				case map[string]any:
					if key, ok := node["Key"].(string); ok && node["SourceKey"] == s.Key {
						if _, manga := node["Authors"]; manga {
							if !seen[key] {
								raw, _ := json.Marshal(node)
								var m models.Manga
								json.Unmarshal(raw, &m)
								entries = append(entries, m)
								seen[key] = true
							}
							return
						}
					}
					for _, child := range node {
						walk(child)
					}
				case []any:
					for _, child := range node {
						walk(child)
					}
				}
			}
			walk(tree)
			return &models.MangaPageResult{Entries: entries}, nil
		}
		return result, err
	case "home":
		return s.GetHome(ctx, nil)
	case "update":
		return s.GetMangaUpdate(ctx, c.Manga, true, true, nil)
	case "pages":
		return s.GetPageList(ctx, c.Manga, c.Chapter)
	case "basicLogin":
		return s.HandleBasicLogin(ctx, c.Key, c.Username, c.Password)
	case "webLogin":
		return s.HandleWebLogin(ctx, c.Key, c.Cookies)
	case "deepLink":
		return s.HandleDeepLink(ctx, c.URL)
	case "notify":
		return nil, s.HandleNotification(ctx, c.Notification)
	case "imageRequest":
		if !s.Runner.Features.ProvidesImageRequests {
			return map[string]any{"url": c.URL}, nil
		}
		r, e := s.GetImageRequest(ctx, c.URL, c.Context)
		if e != nil {
			return nil, e
		}
		return map[string]any{"url": r.URL.String(), "headers": r.Headers, "body": r.Body, "method": r.Method}, nil
	case "image":
		var request *host.NetRequest
		if s.Runner.Features.ProvidesImageRequests {
			request, e = s.GetImageRequest(ctx, c.URL, c.Context)
			if e != nil {
				return nil, e
			}
		} else {
			u, _ := http.NewRequest("GET", c.URL, nil)
			request = &host.NetRequest{URL: u.URL, Headers: map[string]string{}}
		}
		req, e := request.ToHTTPRequest(ctx)
		if e != nil {
			return nil, e
		}
		resp, e := (&http.Client{Transport: transport{}, Timeout: 45 * time.Second}).Do(req)
		if e != nil {
			return nil, e
		}
		defer resp.Body.Close()
		data, e := io.ReadAll(io.LimitReader(resp.Body, 64<<20))
		if e != nil {
			return nil, e
		}
		if resp.StatusCode < 200 || resp.StatusCode >= 300 {
			return nil, fmt.Errorf("image HTTP %d", resp.StatusCode)
		}
		if c.Key != "" {
			archive, err := zip.NewReader(bytes.NewReader(data), int64(len(data)))
			if err != nil {
				return nil, err
			}
			found := false
			for _, f := range archive.File {
				if f.Name == c.Key {
					if f.UncompressedSize64 > 64<<20 {
						return nil, fmt.Errorf("archive page exceeds size limit")
					}
					reader, err := f.Open()
					if err != nil {
						return nil, err
					}
					data, err = io.ReadAll(io.LimitReader(reader, 64<<20))
					reader.Close()
					if err != nil {
						return nil, err
					}
					found = true
					break
				}
			}
			if !found {
				return nil, fmt.Errorf("page not found in archive")
			}
		}
		if (c.Cover && s.Runner.Features.ProcessesCovers) || (!c.Cover && s.Runner.Features.ProcessesPages) {
			ref := s.Runner.StoreValue(append([]byte(nil), data...))
			defer s.Runner.RemoveValue(ref)
			headers := map[string]string{}
			for k, v := range resp.Header {
				if len(v) > 0 {
					headers[k] = v[0]
				}
			}
			response := models.Response{Code: uint16(resp.StatusCode), Headers: headers, Request: models.Request{URL: ptrString(req.URL.String()), Headers: request.Headers}, Image: models.ImageRef(ref)}
			var out *int32
			if c.Cover {
				out, e = s.ProcessCoverImage(ctx, response)
			} else {
				out, e = s.ProcessPageImage(ctx, response, c.Context)
			}
			if e != nil {
				return nil, e
			}
			if out != nil {
				defer s.Runner.RemoveValue(*out)
				switch im := s.Runner.Fetch(*out).(type) {
				case *host.EncodedImage:
					data = append([]byte(nil), im.Data...)
				case image.Image:
					var buf bytes.Buffer
					if err := png.Encode(&buf, im); err != nil {
						return nil, err
					}
					data = buf.Bytes()
				case []byte:
					data = append([]byte(nil), im...)
				default:
					return nil, fmt.Errorf("processed page is not an image")
				}
			}
		}
		return data, nil
	case "inlineImage":
		var ref int32
		fmt.Sscan(c.Key, &ref)
		defer s.Runner.RemoveValue(ref)
		if encoded, ok := s.Runner.Fetch(ref).(*host.EncodedImage); ok {
			return append([]byte(nil), encoded.Data...), nil
		}
		img, ok := s.Runner.Fetch(ref).(image.Image)
		if !ok {
			return nil, fmt.Errorf("missing inline image")
		}
		var buf bytes.Buffer
		e := png.Encode(&buf, img)
		return buf.Bytes(), e
	}
	return nil, fmt.Errorf("unknown operation %s", c.Op)
}
func run(input string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			b, _ := json.Marshal(answer{Error: fmt.Sprint("runtime panic: ", r)})
			result = string(b)
		}
	}()
	var c command
	if e := json.Unmarshal([]byte(input), &c); e != nil {
		b, _ := json.Marshal(answer{Error: e.Error()})
		return string(b)
	}
	v, e := execute(c)
	a := answer{Value: v}
	if e != nil {
		a = answer{Error: e.Error()}
	}
	b, e := json.Marshal(a)
	if e != nil {
		b, _ = json.Marshal(answer{Error: e.Error()})
	}
	return string(b)
}

//export YoruModernCall
func YoruModernCall(input *C.char) *C.char { return C.CString(run(C.GoString(input))) }

//export YoruModernFree
func YoruModernFree(p unsafe.Pointer) { C.free(p) }

//export YoruModernSetHost
func YoruModernSetHost(p C.uintptr_t) { C.setNativeHost(p) }
func main() {
	scanner := bufio.NewScanner(os.Stdin)
	scanner.Buffer(make([]byte, 4096), 8<<20)
	for scanner.Scan() {
		fmt.Println(run(scanner.Text()))
	}
}
