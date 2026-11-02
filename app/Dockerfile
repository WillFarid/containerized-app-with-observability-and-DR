# -----------------------------------------------------------------------------
# Dockerfile
# Small image, no extra packages, runs as a non-root user.
# -----------------------------------------------------------------------------
FROM python:3.12-slim

# Send logs straight to stdout so the ECS log driver ships them to CloudWatch.
ENV PYTHONUNBUFFERED=1

# A non-root user: if the app were compromised, it would have no root rights.
RUN useradd --create-home --uid 10001 appuser

WORKDIR /app
COPY server.py .

USER 10001
EXPOSE 8080

# Lets Docker (and anything reading container health) see whether the app answers.
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')" || exit 1

CMD ["python", "server.py"]
