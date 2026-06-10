#!/usr/bin/env bash
# 06-vector-layer.sh — Install vector database options for RAG and
# semantic search. All run as Docker containers.
# Run as root.

set -euo pipefail

echo "==> Installing vector database layer..."

# Ensure Docker is available
if ! command -v docker &>/dev/null; then
    echo "  ERROR: Docker required. Run 05-ai-runtime.sh first."
    exit 1
fi

docker network create aios-vectors 2>/dev/null || true

VECTOR_DB="${VECTOR_DB:-qdrant}"

echo "  Selected vector DB: ${VECTOR_DB}"
echo "  (Override with VECTOR_DB=qdrant|milvus|weaviate|pgvector)"

case "${VECTOR_DB}" in
    qdrant)
        echo "  Starting Qdrant..."
        docker run -d \
            --name qdrant \
            --network aios-vectors \
            --restart unless-stopped \
            -p 6333:6333 -p 6334:6334 \
            -v qdrant_storage:/qdrant/storage \
            qdrant/qdrant:latest
        echo "  Qdrant running on http://localhost:6333"
        ;;

    milvus)
        echo "  Starting Milvus Standalone..."
        mkdir -p /opt/milvus && cd /opt/milvus
        if [ ! -f docker-compose.yml ]; then
            wget -qO docker-compose.yml \
                https://github.com/milvus-io/milvus/releases/latest/download/milvus-standalone-docker-compose.yml
        fi
        docker compose up -d
        echo "  Milvus running on http://localhost:19530"
        ;;

    weaviate)
        echo "  Starting Weaviate..."
        docker run -d \
            --name weaviate \
            --network aios-vectors \
            --restart unless-stopped \
            -p 8080:8080 -p 50051:50051 \
            -e AUTHENTICATION_ANONYMOUS_ACCESS_ENABLED=true \
            -e PERSISTENCE_DATA_PATH=/var/lib/weaviate \
            -v weaviate_data:/var/lib/weaviate \
            cr.weaviate.io/semitechnologies/weaviate:latest
        echo "  Weaviate running on http://localhost:8080"
        ;;

    pgvector)
        echo "  Starting PostgreSQL with pgvector..."
        docker run -d \
            --name pgvector \
            --network aios-vectors \
            --restart unless-stopped \
            -p 5432:5432 \
            -e POSTGRES_PASSWORD="${PGVECTOR_PASSWORD:-vaaniai}" \
            -e POSTGRES_DB=vectors \
            -v pgvector_data:/var/lib/postgresql/data \
            pgvector/pgvector:pg16
        echo "  pgvector running on localhost:5432 (db=vectors)"
        ;;

    all)
        echo "  Installing all vector databases..."
        VECTOR_DB=qdrant   "$0"
        VECTOR_DB=pgvector "$0"
        echo "  All vector databases started."
        ;;

    *)
        echo "  Unknown VECTOR_DB=${VECTOR_DB}. Options: qdrant, milvus, weaviate, pgvector, all"
        exit 1
        ;;
esac

echo "==> Vector layer installed."
