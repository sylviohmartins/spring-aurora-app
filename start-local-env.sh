#!/bin/bash

echo "Iniciando LocalStack e MySQL com Docker Compose..."
docker-compose up -d

echo "Aguardando o LocalStack e MySQL estarem prontos..."
sleep 30 # Ajuste conforme necessário para o seu ambiente

echo "Ambiente local iniciado. Você pode agora iniciar a aplicação Spring Boot."

