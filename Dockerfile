# Dockerfile
FROM python:3.11-slim
WORKDIR /app

# Install dependencies
RUN pip install --no-cache-dir \
    kubernetes==28.1.0 \
    requests==2.31.0 \
    prometheus-client==0.19.0

# Copy autoscaler code
COPY reactive.py .

# Run as non-root user
RUN useradd -m autoscaler
USER autoscaler

CMD ["python", "reactive.py"]
