FROM alpine:3.19

RUN apk add --no-cache \
    bash \
    socat \
    jq \
    coreutils \
    grep \
    sed \
    util-linux

WORKDIR /app

COPY start-sqs.sh mini-sqs.sh ./

RUN chmod +x start-sqs.sh mini-sqs.sh

ENV PORT=8080
ENV QUEUE_DIR=/data/queues
ENV LOG_FILE=/var/log/mini-sqs.log

RUN mkdir -p /data/queues /var/log

EXPOSE 8080

VOLUME ["/data"]

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

CMD ["/app/start-sqs.sh"]
