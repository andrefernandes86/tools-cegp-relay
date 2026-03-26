FROM ubuntu:22.04

LABEL maintainer="TrendAI SMTP Relay Team"
LABEL description="CEGP SMTP Relay Service for internal email routing to Trend Micro Cloud Email Gateway Protection"

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    POSTFIX_VERSION=3.6.4-1ubuntu1.5 \
    TZ=UTC

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    postfix=3.6.4-1ubuntu1.5 \
    postfix-sqlite=3.6.4-1ubuntu1.5 \
    postfix-policyd-spf-python \
    python3.10 \
    python3-pip \
    python3-aiosmtpd \
    supervisor \
    redis-server \
    openssl \
    curl \
    net-tools \
    telnet \
    vim-tiny \
    dnsutils \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
RUN pip3 install --no-cache-dir \
    redis==4.5.0 \
    pydantic==2.0.0 \
    prometheus-client==0.16.0 \
    structlog==23.1.0 \
    python-dotenv==1.0.0 \
    aioredis==2.0.1

# Create necessary directories
RUN mkdir -p /opt/relay-policy \
    /etc/certs \
    /var/lib/relay-policy \
    /var/spool/postfix \
    /var/log/relay \
    && chown -R postfix:postfix /var/spool/postfix \
    /var/log/relay

# Copy policy daemon
COPY relay_policy_daemon.py /opt/relay-policy/
COPY health_check.py /opt/relay-policy/
RUN chmod +x /opt/relay-policy/*.py

# Copy Postfix configuration
COPY postfix/main.cf /etc/postfix/main.cf.template
COPY postfix/master.cf /etc/postfix/master.cf.template
COPY postfix/transport /etc/postfix/transport

# Copy supervisor config for managing multiple services
COPY supervisor/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Copy entrypoint
COPY entrypoint.sh /
RUN chmod +x /entrypoint.sh

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD python3 /opt/relay-policy/health_check.py

# Expose ports
EXPOSE 25 587 465 9090

ENTRYPOINT ["/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
