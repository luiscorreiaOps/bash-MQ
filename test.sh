#!/bin/bash
set -e

BASE_URL="http://localhost:8080"
QUEUE_NAME="test-queue"

echo "Teste Bash MQ..."
echo ""

echo " Aguardando server..."
sleep 2

# Health Check
echo "1  Testando Health check..."
curl -s "$BASE_URL/health" | jq .
echo ""

# Criar fila
echo "2  Criando fila '$QUEUE_NAME'..."
curl -s -X POST "$BASE_URL/queue/$QUEUE_NAME"
echo ""
echo ""

# 3. Listar filas
echo "3  Listando filas..."
curl -s "$BASE_URL/queues" | jq .
echo ""

# Enviar mensagens
echo "4  Enviando 3 msgs..."
for i in {1..3}; do
    MSG="Mensagem de teste #$i - $(date)"
    RESPONSE=$(curl -s -X POST \
        -H "Content-Type: text/plain" \
        -d "$MSG" \
        "$BASE_URL/queue/$QUEUE_NAME/send")
    echo "   Enviada: $RESPONSE"
done
echo ""

# Estatisticas
echo "5  Estatísticas da fila..."
curl -s "$BASE_URL/queue/$QUEUE_NAME/stats" | jq .
echo ""

# Peek mensagem
echo "6  Peek (visualizar sem remover)..."
curl -s "$BASE_URL/queue/$QUEUE_NAME/peek" | jq .
echo ""

# Receber mensagem
echo "7 Recebendo mensagem..."
MSG_RECEIVED=$(curl -s "$BASE_URL/queue/$QUEUE_NAME/receive")
echo "$MSG_RECEIVED" | jq .
MSG_ID=$(echo "$MSG_RECEIVED" | jq -r '.id')
echo ""

# apos receber
echo "8  Estatísticas após receber..."
curl -s "$BASE_URL/queue/$QUEUE_NAME/stats" | jq .
echo ""

# Deletar mensagem
echo "9  Deletando mensagem $MSG_ID..."
curl -s -X DELETE "$BASE_URL/queue/$QUEUE_NAME/message/$MSG_ID" | jq .
echo ""

# finais
echo "10 Estatísticas finais..."
curl -s "$BASE_URL/queue/$QUEUE_NAME/stats" | jq .
echo ""

echo " Testes concluidos!"
