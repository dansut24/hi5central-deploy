FROM docker:28-cli

RUN apk add --no-cache curl jq docker-cli-compose

WORKDIR /operator
COPY compose.yml compose.release-edge.yml ./
COPY scripts/release-operator.sh /usr/local/bin/hi5central-release-operator
RUN chmod 0755 /usr/local/bin/hi5central-release-operator

ENTRYPOINT ["/usr/local/bin/hi5central-release-operator"]
