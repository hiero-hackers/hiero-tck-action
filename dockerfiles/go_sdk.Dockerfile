FROM golang:1.27.1 AS builder

WORKDIR /app

COPY . /app/hiero-sdk-go/
WORKDIR /app/hiero-sdk-go/tck

COPY tck/go.mod tck/go.sum ./

RUN go mod tidy
RUN go build -o server cmd/server.go


FROM alpine

WORKDIR /app
COPY --from=builder /app/hiero-sdk-go/tck/server .
RUN chmod +x /app/server

RUN apk add --no-cache libc6-compat

CMD ["./server"]
