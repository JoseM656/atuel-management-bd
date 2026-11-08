FROM golang:1.26 AS build
WORKDIR /app
COPY . .
RUN CGO_ENABLED=0 go build -o /api ./cmd/api

FROM alpine:3
COPY --from=build /api /api
CMD ["/api"]