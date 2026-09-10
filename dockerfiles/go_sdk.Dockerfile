# JSON-RPC server for the Hiero SDK TCK.
#
# Build context is the repository root:
#   docker build -f dockerfiles/go_sdk.Dockerfile -t hiero-sdk-go-tck .

FROM golang:1.27.1-bookworm AS builder

WORKDIR /app

# tck is its own module and resolves the SDK through
# `replace github.com/hiero-ledger/hiero-sdk-go/v2 => ../`, so the checkout has
# to keep its shape: the parent directory must sit one level above tck.
COPY . /app/hiero-sdk-go/

WORKDIR /app/hiero-sdk-go/tck

# `go mod download` rather than `go mod tidy`: tidy rewrites go.mod and go.sum
# from whatever it can reach, so a build could silently ship a dependency set
# that differs from the committed one.
RUN go mod download

# Statically linked, so the runtime stage needs no libc at all. The previous
# build left cgo on and then reached for libc6-compat to paper over a
# glibc-linked binary landing on musl.
RUN CGO_ENABLED=0 GOOS=linux go build -o /server ./cmd/server.go


FROM alpine:3.22

RUN apk add --no-cache ca-certificates

WORKDIR /app

COPY --from=builder /server /app/server

EXPOSE 8544

# cmd/server.go reads TCK_PORT itself, defaulting to 8544, and listens on every
# interface, so no wrapper is needed to honour the action's serverEnv.
ENTRYPOINT ["/app/server"]
