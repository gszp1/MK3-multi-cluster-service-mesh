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

func respond(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method Not Allowed", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "Error: "+err.Error(), http.StatusInternalServerError)
		return
	}
	content := strings.TrimRight(string(body), "\n")
	if content == "" {
		content = r.URL.Query().Get("content")
	}
	receivedAt := time.Now().Format("2006-01-02T15:04:05")

	var message strings.Builder
	if content != "" {
		fmt.Fprintf(&message, "Content: %s\n", content)
	}
	message.WriteString("\n")
	message.WriteString("\n")
	message.WriteString("Responder received this message.\n")
	fmt.Fprintf(&message, "Responder IP: %s\n", localIP())
	fmt.Fprintf(&message, "Time of receiving: %s\n", receivedAt)
	fmt.Fprintf(&message, "Request from: %s\n", remoteAddr(r))

	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	if _, err := w.Write([]byte(message.String())); err != nil {
		log.Printf("failed to write response: %v", err)
	}
}

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/api", respond)

	addr := ":" + port
	log.Printf("responder listening on %s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatalf("server error: %v", err)
	}
}