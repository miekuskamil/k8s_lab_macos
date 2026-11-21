// hits: the small web app of the Docker track (track 0).
//
//	GET /         "hello from <hostname>, visit <n>" and the app version
//	GET /healthz  200 "ok", or 503 when REDIS_ADDR is set and Redis does not answer
//	hits healthcheck   calls /healthz on localhost and exits 0 or 1, for a HEALTHCHECK in an
//	                   image that has no shell and no curl
//
// With REDIS_ADDR (host:port) the visit counter lives in Redis, so every copy of the app
// shares it. Without it, each copy counts on its own. It uses only the Go standard library,
// so the build needs no downloads beyond the Go image.
package main

import (
	"bufio"
	"context"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"sync/atomic"
	"syscall"
	"time"
)

// version is set at build time: go build -ldflags "-X main.version=1.0.0"
var version = "dev"

var local atomic.Int64

// incr sends INCR hits to Redis with its plain text protocol and returns the new value.
func incr(addr string) (int64, error) {
	c, err := net.DialTimeout("tcp", addr, 2*time.Second)
	if err != nil {
		return 0, err
	}
	defer c.Close()
	c.SetDeadline(time.Now().Add(2 * time.Second))
	if _, err := c.Write([]byte("*2\r\n$4\r\nINCR\r\n$4\r\nhits\r\n")); err != nil {
		return 0, err
	}
	line, err := bufio.NewReader(c).ReadString('\n')
	if err != nil {
		return 0, err
	}
	var n int64
	if _, err := fmt.Sscanf(strings.TrimSpace(line), ":%d", &n); err != nil {
		return 0, fmt.Errorf("unexpected reply %q", strings.TrimSpace(line))
	}
	return n, nil
}

func ping(addr string) error {
	c, err := net.DialTimeout("tcp", addr, 2*time.Second)
	if err != nil {
		return err
	}
	return c.Close()
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8000"
	}
	redis := os.Getenv("REDIS_ADDR")
	host, _ := os.Hostname()

	if len(os.Args) > 1 && os.Args[1] == "healthcheck" {
		c := http.Client{Timeout: 3 * time.Second}
		resp, err := c.Get("http://127.0.0.1:" + port + "/healthz")
		if err != nil || resp.StatusCode != http.StatusOK {
			fmt.Println("unhealthy")
			os.Exit(1)
		}
		fmt.Println("healthy")
		os.Exit(0)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		var n int64
		if redis != "" {
			v, err := incr(redis)
			if err != nil {
				log.Printf("redis %s: %v", redis, err)
				http.Error(w, "redis unavailable: "+err.Error(), http.StatusServiceUnavailable)
				return
			}
			n = v
		} else {
			n = local.Add(1)
		}
		w.Header().Set("X-App-Version", version)
		fmt.Fprintf(w, "hello from %s, visit %d, version %s\n", host, n, version)
	})
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		if redis != "" {
			if err := ping(redis); err != nil {
				http.Error(w, "redis unavailable", http.StatusServiceUnavailable)
				return
			}
		}
		fmt.Fprintln(w, "ok")
	})

	srv := &http.Server{
		Addr: ":" + port,
		Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()
			mux.ServeHTTP(w, r)
			log.Printf("%s %s from %s in %s", r.Method, r.URL.Path, r.RemoteAddr, time.Since(start).Round(time.Microsecond))
		}),
		ReadHeaderTimeout: 5 * time.Second,
	}

	// Stop cleanly on SIGTERM, the signal docker stop sends first.
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGTERM, os.Interrupt)
	go func() {
		s := <-stop
		log.Printf("got %s, shutting down", s)
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		srv.Shutdown(ctx)
	}()

	log.Printf("hits %s listening on :%s, redis=%q, uid=%d", version, port, redis, os.Getuid())
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatal(err)
	}
	log.Print("bye")
}
