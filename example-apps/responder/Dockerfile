# Stage 1: Build
FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /app/responder .

# Stage 2: Run
FROM gcr.io/distroless/static-debian12
WORKDIR /app
COPY --from=builder /app/responder /app/responder
EXPOSE 8080
ENTRYPOINT ["/app/responder"]
