FROM golang:alpine AS builder
RUN apk add --no-cache git gcc musl-dev patch
WORKDIR /app
COPY . .
RUN go mod download && \
    module_dir="$(go list -m -f '{{.Dir}}' github.com/polymorfa/hypermeow)" && \
    chmod -R u+w "$module_dir" && \
    patch -d "$module_dir" -p1 < patches/hypermeow-status-receipt-participant.patch && \
    patch -d "$module_dir" -p1 < patches/hypermeow-profile-about.patch && \
    module_dir="$(go list -m -f '{{.Dir}}' github.com/purpshell/meowcaller)" && \
    chmod -R u+w "$module_dir" && \
    patch -d "$module_dir" -p1 < patches/meowcaller-linked-device-reject.patch && \
    patch -d "$module_dir" -p1 < patches/meowcaller-group-jid.patch
RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux go build -o main .

FROM alpine:latest
RUN apk add --no-cache ca-certificates ffmpeg tzdata
WORKDIR /app
COPY --from=builder /app/main .
EXPOSE 8080 8081
CMD ["./main"]
