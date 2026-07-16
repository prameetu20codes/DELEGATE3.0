# Tiny image so the pipeline has something real to build & push
FROM alpine:3.20

RUN apk add --no-cache curl

ARG BUILD_TIME=unknown
ENV BUILD_TIME=${BUILD_TIME}

WORKDIR /app
COPY hello.sh /app/hello.sh
RUN chmod +x /app/hello.sh

ENTRYPOINT ["/app/hello.sh"]
