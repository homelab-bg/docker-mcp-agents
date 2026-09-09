# Pinned Python patch version, not just the 3.12 minor floating tag —
# rebuilds stay reproducible even if a new 3.12.x base image is published.
FROM python:3.12.8-slim

RUN useradd -m -u 1000 mcp
RUN pip install --no-cache-dir truenas-ws-mcp==0.1.1

USER mcp
CMD ["truenas-ws-mcp"]
