FROM golang:1.21-alpine AS builder
RUN apk add --no-cache git gcc musl-dev
WORKDIR /app
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o main .

FROM alpine:latest
RUN apk add --no-cache ca-certificates tzdata
WORKDIR /app
COPY --from=builder /app/main .
EXPOSE 8080
CMD ["./main"]
