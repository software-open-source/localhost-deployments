FROM alpine:3.22

RUN apk add --no-cache bash curl docker-cli jq

COPY sync.sh /usr/local/bin/sync.sh
COPY watch.sh /usr/local/bin/watch.sh

RUN chmod 0755 /usr/local/bin/sync.sh /usr/local/bin/watch.sh

ENTRYPOINT ["/usr/local/bin/watch.sh"]
