# Stage 1: Build
FROM golang:1.23-alpine AS builder
WORKDIR /app
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /app/sender .

# Stage 2: Run
FROM gcr.io/distroless/static-debian12
WORKDIR /app
COPY --from=builder /app/sender /app/sender
EXPOSE 8080
ENTRYPOINT ["/app/sender"]
