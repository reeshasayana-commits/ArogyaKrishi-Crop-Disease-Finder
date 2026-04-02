# Hugging Face Space - Docker Deployment
# Combines Python AI Server + Node.js Scanner App
FROM python:3.10-slim

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1
ENV DEBIAN_FRONTEND noninteractive

WORKDIR /app

# Install system dependencies (including Node.js 18)
RUN apt-get update && apt-get install -y \
    curl \
    gnupg \
    build-essential \
    && curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# 1. Setup AI Server
COPY ai-server/requirements.txt /app/ai-server/
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r /app/ai-server/requirements.txt

COPY ai-server/ /app/ai-server/

# 2. Setup Node.js Scanner
COPY plant-disease-scanner/package*.json /app/plant-disease-scanner/
WORKDIR /app/plant-disease-scanner
RUN npm ci --only=production

COPY plant-disease-scanner/ /app/plant-disease-scanner/

# 3. Process Management Script
WORKDIR /app
RUN echo '#!/bin/bash\n\
set -e\n\
\n\
echo "🚀 Starting ArogyaKrishi AI Server..."\n\
cd /app/ai-server\n\
# Run gunicorn in background\n\
gunicorn --bind 127.0.0.1:5000 ai_server:app --timeout 120 --workers 1 --daemon\n\
\n\
echo "⏳ Waiting for AI models and dependencies to initialize (30s)..."\n\
current_time=0\n\
while [ $current_time -lt 30 ]; do\n\
    echo "   ...$((30-current_time))s remaining"\n\
    sleep 5\n\
    current_time=$((current_time+5))\n\
done\n\
\n\
echo "🌍 Starting Web Scanner on port 7860..."\n\
cd /app/plant-disease-scanner\n\
# Bind to 0.0.0.0 to be accessible via Hugging Face proxy\n\
export PORT=7860\n\
export AI_SERVER_URL=http://127.0.0.1:5000\n\
echo "👤 Current User: $(whoami)"\n\
echo "📡 AI Server configured at: $AI_SERVER_URL"\n\
exec node server.js' > /app/start.sh && chmod +x /app/start.sh

# Hugging Face Spaces default port
EXPOSE 7860

# Non-root user setup for security (HF suggests ID 1000)
# Note: Some actions might need root, so we do this last
RUN useradd -m -u 1000 user
RUN chown -R user:user /app
USER user

# Set internal AI URL
ENV AI_SERVER_URL=http://127.0.0.1:5000
ENV NODE_ENV=production

CMD ["/app/start.sh"]
