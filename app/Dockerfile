FROM python:3.12-slim

WORKDIR /app

# Run as non-root (K8s securityContext friendly)
RUN addgroup --system appgroup && adduser --system --ingroup appgroup appuser

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

USER appuser

ENV PORT=8080
EXPOSE 8080

# gunicorn for production-style serving instead of Flask dev server
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]
