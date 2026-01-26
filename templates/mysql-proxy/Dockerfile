FROM debian:bullseye-slim

RUN apt-get update && apt-get install -y \
    socat \
    default-mysql-client \
    iputils-ping \
    net-tools \
    curl \
    bash \
    vim

# Entrypoint-Script hinzufügen
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Container startet mit dem Entrypoint-Script
ENTRYPOINT ["/entrypoint.sh"]
