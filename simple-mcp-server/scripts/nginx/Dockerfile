# Neo4j MCP Server - API Key Authentication Proxy
# Based on OpenResty (Nginx with Lua support) for API key validation

FROM openresty/openresty:1.27.1.2-0-alpine

LABEL org.opencontainers.image.title="Neo4j MCP Auth Proxy"
LABEL org.opencontainers.image.description="API key authentication proxy for Neo4j MCP Server"
LABEL org.opencontainers.image.source="https://github.com/neo4j/mcp"

# Install curl for health checks during development
RUN apk add --no-cache curl

# Remove default nginx config
RUN rm -f /etc/nginx/conf.d/default.conf /usr/local/openresty/nginx/conf/nginx.conf

# Copy custom nginx configuration
COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf

# Create non-root user for security
RUN addgroup -g 101 -S nginx && \
    adduser -S -D -H -u 101 -h /var/cache/nginx -s /sbin/nologin -G nginx nginx

# Create required directories with proper permissions
RUN mkdir -p /var/cache/nginx /var/run && \
    chown -R nginx:nginx /var/cache/nginx /var/run /usr/local/openresty/nginx

# Use non-root user
USER nginx

# Expose the proxy port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Run OpenResty (Nginx)
CMD ["openresty", "-g", "daemon off;"]
