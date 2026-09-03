# P0 perf fix (2026-07-22) — force IPv4-only DNS resolution for the aider
# subprocess spawned by run-aider-deepseek.sh.
#
# Root cause (confirmed via faulthandler.dump_traceback_later stack dumps):
# 9router.proxy.com is dual-stack (Cloudflare). Python's synchronous
# socket.create_connection() has no happy-eyeballs — it tries addresses in
# the order getaddrinfo() returns them (IPv6 first here) and blocks on each
# until it times out before trying the next. The IPv6 route to this host is
# blackholed (SYN sent, no response — not a fast reject), so every affected
# call blocks for the OS-level TCP connect timeout (tens of seconds, varies)
# before falling through to the working IPv4 address. Measured directly:
# raw IPv6 connect to the resolved address timed out at 8s (artificial cap);
# IPv4 connect to the same host completed in 0.11s.
#
# This must not be "fixed" by disabling IPv6 system-wide (affects unrelated
# apps) or by patching vendored httpx/litellm inside the aider formula
# (reverts on `brew upgrade aider`). Restricting getaddrinfo() to AF_INET
# only within this subprocess, loaded via PYTHONPATH so it's automatic
# (site module imports sitecustomize.py if importable), is scoped and safe:
# it changes nothing except which address family this one process's DNS
# lookups return.
import socket

_orig_getaddrinfo = socket.getaddrinfo


def _ipv4_only_getaddrinfo(host, port, family=0, type=0, proto=0, flags=0):
    return _orig_getaddrinfo(host, port, socket.AF_INET, type, proto, flags)


socket.getaddrinfo = _ipv4_only_getaddrinfo
