#!/bin/bash
set -e

echo "🐳 Starting BTC Guess Game with Docker..."
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker and try again."
    exit 1
fi

# Build and start services
echo "📦 Building Docker images..."
docker-compose build

echo ""
echo "🚀 Starting services..."
docker-compose up -d

echo ""
echo "⏳ Waiting for services to be healthy..."
sleep 5

# Check if services are running
if docker-compose ps | grep -q "Up"; then
    echo ""
    echo "✅ Services are running!"
    echo ""
    echo "🎮 Game is available at: http://localhost:4000"
    echo ""
    echo "📊 View logs with: docker-compose logs -f app"
    echo "🛑 Stop services with: docker-compose down"
else
    echo ""
    echo "❌ Failed to start services. Check logs with: docker-compose logs"
    exit 1
fi
