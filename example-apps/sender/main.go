package main

import (
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"time"
)

func localIP() string {
	host, err := os.Hostname()
	if err == nil {
		if ips, err := net.LookupIP(host); err == nil {
			for _, ip := range ips {
				if v4 := ip.To4(); v4 != nil {
					return v4.String()
				}
			}
		}
	}
	return "unknown"
}

func remoteAddr(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

func passMessageToResponder(responderURL string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		content := r.URL.Query().Get("content")
		receivedAt := time.Now().Format("2006-01-02T15:04:05")

		var message strings.Builder
		message.WriteString("Sender received this message.\n")
		fmt.Fprintf(&message, "Sender IP: %s\n", localIP())
		fmt.Fprintf(&message, "Time of receiving: %s\n", receivedAt)
		fmt.Fprintf(&message, "Request from: %s\n", remoteAddr(r))
		if content != "" {
			fmt.Fprintf(&message, "Content: %s\n", content)
		}

		resp, err := http.Post(responderURL, "text/plain", strings.NewReader(message.String()))
		if err != nil {
			fmt.Fprintf(w, "Error: %s", err)
			return
		}
		defer resp.Body.Close()

		body, err := io.ReadAll(resp.Body)
		if err != nil {
			fmt.Fprintf(w, "Error: %s", err)
			return
		}

		w.Header().Set("Content-Type", "text/plain; charset=utf-8")
		if _, err := w.Write(body); err != nil {
			log.Printf("failed to write response: %v", err)
		}
	}
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	responderURL := os.Getenv("RESPONDER_URL")
	if responderURL == "" {
		log.Fatal("RESPONDER_URL environment variable is required")
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/api", passMessageToResponder(responderURL))

	addr := ":" + port
	log.Printf("sender listening on %s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatalf("server error: %v", err)
	}
}