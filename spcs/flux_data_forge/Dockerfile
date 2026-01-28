# Flux Data Forge - Streaming Synthetic Data Generator
#
# Build: docker build -t flux-data-forge:latest .
# Run: docker run -p 8080:8080 flux-data-forge:latest

FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY src/ ./src/

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')"

CMD ["python", "-m", "src.main"]
