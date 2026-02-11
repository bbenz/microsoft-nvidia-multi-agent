# ============================================================
# GPU Parse Specialist Agent — Container Image
# Deployable to Azure Container Apps with NVIDIA GPU
# ============================================================

FROM python:3.11-slim AS base

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY parser_service/ parser_service/

# Expose FastAPI port
EXPOSE 8001

# Health check
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD python -c "import httpx; httpx.get('http://localhost:8001/health').raise_for_status()"

# Run
CMD ["uvicorn", "parser_service.main:app", "--host", "0.0.0.0", "--port", "8001"]
