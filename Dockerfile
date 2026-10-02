FROM registry.access.redhat.com/hi/python:latest-fips-builder@sha256:b9428ee102589e152733779b2e032bce9f50be385906f0b39faa98363ed9b190 AS builder

USER 0

RUN dnf5 install -y gcc gcc-c++ python3-devel make \
    openssl-devel cyrus-sasl-devel libxcrypt && \
    dnf5 clean all

COPY hermetic/librdkafka /tmp/librdkafka
RUN cd /tmp/librdkafka && \
    ./configure --prefix=/usr --libdir=/usr/lib64 && \
    make && \
    make INSTALL=/usr/bin/install install && \
    ldconfig

COPY src src
COPY pyproject.toml pyproject.toml

RUN python3 -m pip install --use-pep517 .

# DEBUG VERSION: Use builder image as runtime (has shell and tools)
# This gives us bash, dnf, and all the debugging tools we need
FROM registry.access.redhat.com/hi/python:latest-fips-builder@sha256:b9428ee102589e152733779b2e032bce9f50be385906f0b39faa98363ed9b190

USER 0

# Install debugging tools
RUN dnf5 install -y \
    bash \
    curl \
    wget \
    vim-minimal \
    less \
    bind-utils \
    iputils \
    net-tools \
    openssl \
    strace \
    tcpdump \
    && dnf5 clean all

# Copy runtime dependencies from builder
COPY --from=builder /usr/lib64/librdkafka* /usr/lib64/
COPY --from=builder /usr/lib64/libsasl2* /usr/lib64/
COPY --from=builder /usr/lib64/libcrypt* /usr/lib64/
COPY --from=builder /etc/ld.so.cache /etc/ld.so.cache
COPY --from=builder /usr/local/lib/ /usr/local/lib/
COPY --from=builder /usr/local/lib64/ /usr/local/lib64/
COPY --from=builder /usr/local/bin/ /usr/local/bin/

# Copy application files
COPY default_map.yaml /opt/app-root/src/default_map.yaml
COPY rhosak_map.yaml /opt/app-root/src/rhosak_map.yaml
COPY licenses/LICENSE /licenses/LICENSE

# Copy test scripts for debugging
COPY test_ssl_debug.py /opt/app-root/test_ssl_debug.py
COPY test_s3_connection.py /opt/app-root/test_s3_connection.py

# Create a debugging entrypoint script
RUN cat > /opt/app-root/debug.sh << 'EOF'
#!/bin/bash
echo "========================================================================"
echo "  Storage Broker Debug Container"
echo "========================================================================"
echo ""
echo "Python version: $(python3 --version)"
echo "OpenSSL version: $(python3 -c 'import ssl; print(ssl.OPENSSL_VERSION)')"
echo ""
echo "Available commands:"
echo "  python3 /opt/app-root/test_ssl_debug.py          - SSL/FIPS diagnostics"
echo "  python3 /opt/app-root/test_s3_connection.py      - Test S3 connectivity"
echo "  storage_broker                                    - Run the main app"
echo "  storage_broker_api                                - Run API server"
echo "  storage_broker_consumer_api                       - Run consumer+API"
echo ""
echo "Debugging tools available:"
echo "  curl, wget, openssl, dig, ping, netstat, strace, tcpdump"
echo ""
echo "Environment variables for S3 testing:"
echo "  AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID:-<not set>}"
echo "  AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:+***}"
echo "  S3_ENDPOINT_URL=${S3_ENDPOINT_URL:-<not set>}"
echo "  STAGE_BUCKET=${STAGE_BUCKET:-<not set>}"
echo ""
echo "========================================================================"
echo ""
exec /bin/bash "$@"
EOF

RUN chmod +x /opt/app-root/debug.sh

# Stay as root for debugging (can su to 1001 if needed)
USER 0

# Start with bash shell for interactive debugging
ENTRYPOINT ["/opt/app-root/debug.sh"]
CMD []
