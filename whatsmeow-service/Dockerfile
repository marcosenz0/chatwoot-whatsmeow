FROM golang:alpine AS builder
RUN apk add --no-cache git gcc musl-dev patch
WORKDIR /app
COPY . .
RUN go mod download && \
    module_dir="$(go list -m -f '{{.Dir}}' go.mau.fi/whatsmeow)" && \
    chmod -R u+w "$module_dir" && \
    patch -d "$module_dir" -p1 < patches/whatsmeow-status-receipt-participant.patch
RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux go build -o main .

FROM alpine:latest
RUN apk add --no-cache ca-certificates ffmpeg tzdata
WORKDIR /app
COPY --from=builder /app/main .
EXPOSE 8080
CMD ["./main"]
