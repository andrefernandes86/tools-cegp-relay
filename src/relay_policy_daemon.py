#!/usr/bin/env python3
"""
CEGP SMTP Relay Policy Daemon
Enforces rate limiting, domain/host validation, and message rules per Trend Micro specifications.
"""

import asyncio
import socket
import os
import sys
import logging
import time
import json
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
from pathlib import Path
import struct

import redis
from pydantic import BaseModel, Field, validator
from prometheus_client import Counter, Gauge, Histogram, generate_latest, CollectorRegistry
from aiosmtpd.smtp import SMTP as BaseSMTP, Session
from aiosmtpd.handlers import Message
import structlog

# Configure logging
structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.stdlib.PositionalArgumentsFormatter(),
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.UnicodeDecoder(),
        structlog.processors.JSONRenderer()
    ],
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
    cache_logger_on_first_use=True,
)

log = structlog.get_logger(__name__)
logging.basicConfig(
    format="%(message)s",
    stream=sys.stdout,
    level=os.getenv("LOG_LEVEL", "INFO").upper()
)

# ============================================================================
# Configuration Models
# ============================================================================

class RelayConfig(BaseModel):
    """Configuration for the CEGP relay."""
    
    # CEGP Connection
    cegp_host: str = Field(default="relay.mx.trendmicro.com", description="CEGP relay endpoint")
    cegp_port: int = Field(default=25, description="CEGP relay port")
    cegp_use_tls: bool = Field(default=True, description="Use TLS for CEGP connection")
    
    # Rate Limiting (per Trend Micro specs)
    rate_limit_ip_per_min: int = Field(default=2000, description="Messages per minute per sender IP")
    rate_limit_rcpt_per_min: int = Field(default=200, description="Messages per minute per recipient")
    rate_limit_outbound_ip_per_5min: int = Field(default=1000, description="Outbound messages per 5 min per IP")
    
    # Connection Control
    connection_mode: str = Field(default="permit", regex="^(permit|deny)$")
    
    # Message Rules
    max_message_size: int = Field(default=52428800, description="50 MB default")
    max_recipients: int = Field(default=99999)
    
    # TLS Settings
    tls_enabled: bool = True
    tls_cert_path: str = "/etc/certs/relay-cert.pem"
    tls_key_path: str = "/etc/certs/relay-key.pem"
    tls_mode: str = Field(default="STARTTLS", regex="^(STARTTLS|IMPLICIT_TLS|OPTIONAL)$")
    
    # File paths
    relay_domains_file: str = "/var/lib/relay-policy/domains.conf"
    permit_list_file: str = "/var/lib/relay-policy/permit-ips.conf"
    
    # Redis
    redis_host: str = "localhost"
    redis_port: int = 6379
    redis_db: int = 0
    
    # Monitoring
    prometheus_port: int = 9090
    
    @validator('cegp_port')
    def validate_port(cls, v):
        if not 1 <= v <= 65535:
            raise ValueError('Port must be between 1 and 65535')
        return v
    
    class Config:
        case_sensitive = False


def load_config_from_env() -> RelayConfig:
    """Load configuration from environment variables."""
    return RelayConfig(
        cegp_host=os.getenv("CEGP_HOST", "relay.mx.trendmicro.com"),
        cegp_port=int(os.getenv("CEGP_PORT", 25)),
        cegp_use_tls=os.getenv("CEGP_USE_TLS", "true").lower() == "true",
        rate_limit_ip_per_min=int(os.getenv("RATE_LIMIT_IP_PER_MIN", 2000)),
        rate_limit_rcpt_per_min=int(os.getenv("RATE_LIMIT_RCPT_PER_MIN", 200)),
        rate_limit_outbound_ip_per_5min=int(os.getenv("RATE_LIMIT_OUTBOUND_IP_PER_5MIN", 1000)),
        connection_mode=os.getenv("CONNECTION_MODE", "permit").lower(),
        max_message_size=int(os.getenv("MAX_MESSAGE_SIZE", 52428800)),
        max_recipients=int(os.getenv("MAX_RECIPIENTS", 99999)),
        tls_enabled=os.getenv("TLS_ENABLED", "true").lower() == "true",
        tls_cert_path=os.getenv("TLS_CERT_PATH", "/etc/certs/relay-cert.pem"),
        tls_key_path=os.getenv("TLS_KEY_PATH", "/etc/certs/relay-key.pem"),
        tls_mode=os.getenv("TLS_MODE", "STARTTLS"),
        relay_domains_file=os.getenv("RELAY_DOMAINS_FILE", "/var/lib/relay-policy/domains.conf"),
        permit_list_file=os.getenv("PERMIT_LIST_FILE", "/var/lib/relay-policy/permit-ips.conf"),
        redis_host=os.getenv("REDIS_HOST", "localhost"),
        redis_port=int(os.getenv("REDIS_PORT", 6379)),
        prometheus_port=int(os.getenv("PROMETHEUS_PORT", 9090)),
    )


# ============================================================================
# Prometheus Metrics
# ============================================================================

registry = CollectorRegistry()

relay_messages_received_total = Counter(
    'relay_messages_received_total',
    'Total messages received by relay',
    ['domain', 'src_ip'],
    registry=registry
)

relay_messages_delivered_total = Counter(
    'relay_messages_delivered_total',
    'Total messages delivered to CEGP',
    ['status'],
    registry=registry
)

relay_messages_dropped_total = Counter(
    'relay_messages_dropped_total',
    'Total messages dropped',
    ['reason'],
    registry=registry
)

relay_rate_limit_hits_total = Counter(
    'relay_rate_limit_hits_total',
    'Rate limit rejections',
    ['type', 'value'],
    registry=registry
)

relay_connection_total = Counter(
    'relay_connection_total',
    'Total SMTP connections',
    ['src_ip', 'status'],
    registry=registry
)

relay_message_size_bytes = Histogram(
    'relay_message_size_bytes',
    'Message size distribution',
    registry=registry
)

relay_recipient_count = Histogram(
    'relay_recipient_count',
    'Message recipient count distribution',
    registry=registry
)

relay_queue_size_messages = Gauge(
    'relay_queue_size_messages',
    'Current relay queue size',
    registry=registry
)

relay_delivery_latency_seconds = Histogram(
    'relay_delivery_latency_seconds',
    'CEGP delivery latency',
    registry=registry
)


# ============================================================================
# Rate Limiter (Token Bucket Algorithm)
# ============================================================================

class RateLimiter:
    """Token bucket rate limiter backed by Redis."""
    
    def __init__(self, redis_conn: redis.Redis, config: RelayConfig):
        self.redis = redis_conn
        self.config = config
    
    def _get_token_count(self, key: str, limit: int, window_seconds: int = 60) -> Tuple[int, float]:
        """
        Get remaining tokens for a key using sliding window with Redis.
        Returns (tokens_remaining, reset_at_seconds).
        """
        now = time.time()
        window_start = now - window_seconds
        
        # Use Redis sorted set to track request timestamps
        # Score = timestamp, Member = unique request ID
        pipe = self.redis.pipeline()
        key_name = f"ratelimit:{key}"
        
        # Remove old entries outside the window
        pipe.zremrangebyscore(key_name, 0, window_start)
        # Count requests in the window
        pipe.zcard(key_name)
        # Set expiration
        pipe.expire(key_name, window_seconds + 10)
        
        results = pipe.execute()
        current_count = results[1]
        remaining = limit - current_count
        reset_at = now + window_seconds
        
        return (remaining, reset_at)
    
    def check_rate_limit(self, key: str, limit: int, window_seconds: int = 60) -> Tuple[bool, int, float]:
        """
        Check if request is allowed under rate limit.
        Returns (allowed, remaining, reset_at).
        """
        remaining, reset_at = self._get_token_count(key, limit, window_seconds)
        
        if remaining <= 0:
            return (False, remaining, reset_at)
        
        # Record this request
        now = time.time()
        key_name = f"ratelimit:{key}"
        self.redis.zadd(key_name, {str(now): now})
        self.redis.expire(key_name, window_seconds + 10)
        
        return (True, remaining - 1, reset_at)


# ============================================================================
# Policy Daemon
# ============================================================================

class CegpRelayPolicy:
    """Implements Trend Micro CEGP relay policies."""
    
    def __init__(self, config: RelayConfig):
        self.config = config
        self.logger = structlog.get_logger(__name__)
        
        # Connect to Redis
        try:
            self.redis = redis.Redis(
                host=config.redis_host,
                port=config.redis_port,
                db=config.redis_db,
                decode_responses=True,
                socket_connect_timeout=5
            )
            self.redis.ping()
            self.logger.info("redis_connected", host=config.redis_host, port=config.redis_port)
        except redis.ConnectionError as e:
            self.logger.error("redis_connection_failed", error=str(e))
            raise
        
        self.rate_limiter = RateLimiter(self.redis, config)
        self._load_policies()
    
    def _load_policies(self):
        """Load relay domains and permit/deny lists from files."""
        # Load relay domains
        self.relay_domains = set()
        if Path(self.config.relay_domains_file).exists():
            with open(self.config.relay_domains_file) as f:
                self.relay_domains = {
                    line.strip().lower() 
                    for line in f if line.strip() and not line.startswith('#')
                }
        self.logger.info("domains_loaded", count=len(self.relay_domains))
        
        # Load permit/deny list
        self.ip_list = set()
        if Path(self.config.permit_list_file).exists():
            with open(self.config.permit_list_file) as f:
                self.ip_list = {
                    line.strip() 
                    for line in f if line.strip() and not line.startswith('#')
                }
        self.logger.info("ip_list_loaded", mode=self.config.connection_mode, count=len(self.ip_list))
    
    def reload_policies(self):
        """Reload policies from disk (called on HUP signal)."""
        self._load_policies()
        self.logger.info("policies_reloaded")
    
    def check_connection(self, src_ip: str) -> Tuple[bool, str]:
        """
        Check if connection from src_ip is allowed.
        Returns (allowed, reason).
        """
        if self.config.connection_mode == "permit":
            # Permit list: only allow listed IPs
            if self._ip_in_range(src_ip, self.ip_list):
                return (True, "permit_list_match")
            return (False, "not_in_permit_list")
        else:
            # Deny list: block listed IPs
            if self._ip_in_range(src_ip, self.ip_list):
                return (False, "deny_list_match")
            return (True, "not_in_deny_list")
    
    @staticmethod
    def _ip_in_range(ip: str, ip_list: set) -> bool:
        """Check if IP is in any CIDR range in the list."""
        try:
            import ipaddress
            ip_obj = ipaddress.ip_address(ip)
            for entry in ip_list:
                if '/' in entry:
                    # CIDR notation
                    network = ipaddress.ip_network(entry, strict=False)
                    if ip_obj in network:
                        return True
                else:
                    # Single IP
                    if ip_obj == ipaddress.ip_address(entry):
                        return True
            return False
        except Exception as e:
            log.warning("ip_range_check_failed", error=str(e))
            return False
    
    def check_sender_domain(self, from_addr: str) -> Tuple[bool, str]:
        """
        Check if sender domain is in relay_domains list.
        Returns (allowed, reason).
        """
        if not from_addr or '@' not in from_addr:
            return (False, "invalid_sender_format")
        
        domain = from_addr.split('@')[1].lower()
        
        if domain in self.relay_domains:
            return (True, "domain_allowed")
        
        return (False, f"domain_not_in_relay_list")
    
    def check_message_size(self, message_size: int) -> Tuple[bool, str]:
        """Check if message size is within limits."""
        if message_size <= 0:
            return (False, "invalid_message_size")
        
        if message_size > self.config.max_message_size:
            return (False, f"message_exceeds_max_size_{self.config.max_message_size}")
        
        return (True, "message_size_ok")
    
    def check_recipient_count(self, recipient_count: int) -> Tuple[bool, str]:
        """Check if recipient count is within limits."""
        if recipient_count <= 0:
            return (False, "no_recipients")
        
        if recipient_count > self.config.max_recipients:
            return (False, f"exceeds_max_recipients_{self.config.max_recipients}")
        
        return (True, "recipient_count_ok")
    
    def check_rate_limit_ip(self, src_ip: str) -> Tuple[bool, str]:
        """
        Check inbound rate limit per sender IP: 2000 msg/min.
        """
        allowed, remaining, reset_at = self.rate_limiter.check_rate_limit(
            f"inbound_ip:{src_ip}",
            self.config.rate_limit_ip_per_min,
            window_seconds=60
        )
        
        if not allowed:
            relay_rate_limit_hits_total.labels(type="ip", value=src_ip).inc()
            reset_in = int(reset_at - time.time())
            return (False, f"rate_limit_exceeded_ip_reset_in_{reset_in}s")
        
        return (True, "rate_limit_ip_ok")
    
    def check_rate_limit_recipient(self, recipient_addr: str) -> Tuple[bool, str]:
        """
        Check inbound rate limit per recipient: 200 msg/min.
        """
        allowed, remaining, reset_at = self.rate_limiter.check_rate_limit(
            f"inbound_rcpt:{recipient_addr}",
            self.config.rate_limit_rcpt_per_min,
            window_seconds=60
        )
        
        if not allowed:
            relay_rate_limit_hits_total.labels(type="rcpt", value=recipient_addr).inc()
            reset_in = int(reset_at - time.time())
            return (False, f"rate_limit_exceeded_rcpt_reset_in_{reset_in}s")
        
        return (True, "rate_limit_rcpt_ok")


# ============================================================================
# Postfix Policy Socket Service
# ============================================================================

class PostfixPolicyService:
    """
    Implements Postfix policy daemon protocol (over UNIX socket).
    Ref: http://www.postfix.org/SMTPD_POLICY_README.html
    """
    
    def __init__(self, policy: CegpRelayPolicy, socket_path: str = "/var/spool/postfix/private/policy-socket"):
        self.policy = policy
        self.socket_path = socket_path
        self.logger = structlog.get_logger(__name__)
        self.server = None
    
    async def handle_request(self, reader, writer):
        """Handle a policy request from Postfix."""
        try:
            request_attrs = {}
            
            # Read request lines until blank line
            while True:
                line = await reader.readline()
                if not line:
                    break
                
                line = line.decode('utf-8').strip()
                if not line:
                    break
                
                key, value = line.split('=', 1)
                request_attrs[key] = value
            
            # Extract relevant attributes
            protocol_state = request_attrs.get('protocol_state', 'unknown')
            client_address = request_attrs.get('client_address', 'unknown')
            sender = request_attrs.get('sender', '')
            recipient = request_attrs.get('recipient', '')
            
            self.logger.info("policy_request_received", 
                           protocol_state=protocol_state,
                           client_address=client_address,
                           sender=sender)
            
            action = "DUNNO"
            reason = ""
            
            # Check connection
            if protocol_state == "CONNECT":
                allowed, reason = self.policy.check_connection(client_address)
                if not allowed:
                    action = f"REJECT {reason}"
                    relay_connection_total.labels(src_ip=client_address, status="rejected").inc()
                else:
                    relay_connection_total.labels(src_ip=client_address, status="accepted").inc()
            
            # Check sender domain
            elif protocol_state == "MAIL":
                allowed, reason = self.policy.check_sender_domain(sender)
                if not allowed:
                    action = f"REJECT {reason}"
                    relay_messages_dropped_total.labels(reason=reason).inc()
            
            # Check rate limits per recipient
            elif protocol_state == "RCPT":
                # Check rate limit for this recipient
                allowed, reason = self.policy.check_rate_limit_recipient(recipient)
                if not allowed:
                    action = f"DEFER {reason}"
                    relay_messages_dropped_total.labels(reason=reason).inc()
                else:
                    allowed, reason = self.policy.check_rate_limit_ip(client_address)
                    if not allowed:
                        action = f"DEFER {reason}"
                        relay_messages_dropped_total.labels(reason=reason).inc()
            
            # Send response
            response = f"action={action}\n\n"
            writer.write(response.encode('utf-8'))
            await writer.drain()
            
            self.logger.info("policy_response_sent", action=action, reason=reason)
        
        except Exception as e:
            self.logger.error("policy_request_error", error=str(e), exc_info=True)
            writer.write(b"action=DUNNO\n\n")
            await writer.drain()
        
        finally:
            writer.close()
            await writer.wait_closed()
    
    async def start(self):
        """Start the policy service."""
        # Remove old socket file if exists
        Path(self.socket_path).unlink(missing_ok=True)
        
        # Create UNIX socket server
        self.server = await asyncio.start_unix_server(
            self.handle_request,
            self.socket_path
        )
        
        # Fix permissions for Postfix
        os.chmod(self.socket_path, 0o666)
        
        self.logger.info("policy_service_started", socket_path=self.socket_path)
        
        async with self.server:
            await self.server.serve_forever()


# ============================================================================
# Main
# ============================================================================

async def run_policy_service():
    """Run the policy service."""
    config = load_config_from_env()
    policy = CegpRelayPolicy(config)
    
    service = PostfixPolicyService(policy)
    
    try:
        await service.start()
    except KeyboardInterrupt:
        log.info("policy_service_shutting_down")


if __name__ == "__main__":
    asyncio.run(run_policy_service())
