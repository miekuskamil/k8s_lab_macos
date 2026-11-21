# Two stages: the first compiles, the second holds only the program.
FROM golang:1.25.3-alpine3.22 AS build
WORKDIR /src
# The module file first, so a change to the code reuses this layer.
COPY go.mod ./
RUN go mod download
COPY *.go ./
ARG VERSION=dev
# CGO_ENABLED=0 makes a static binary that needs no C library at run time.
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o /out/hits .

FROM scratch
LABEL org.opencontainers.image.title="hits" lab.course="docker"
COPY --from=build /out/hits /hits
# A numeric user, because scratch has no /etc/passwd to look a name up in.
USER 65532:65532
EXPOSE 8000
HEALTHCHECK --interval=5s --timeout=3s --start-period=2s --retries=3 CMD ["/hits", "healthcheck"]
ENTRYPOINT ["/hits"]
