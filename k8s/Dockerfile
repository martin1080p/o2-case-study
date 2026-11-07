# One small image for both parts; the Deployment picks the script. No dependencies - stdlib only.
FROM python:3.12-slim
ARG VERSION=1
ENV VERSION=$VERSION PYTHONUNBUFFERED=1
WORKDIR /app
COPY backend.py frontend.py ./
USER nobody
