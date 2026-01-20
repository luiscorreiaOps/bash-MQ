#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

QUEUE_DIR="${QUEUE_DIR:-$SCRIPT_DIR/queues}"
PORT="${PORT:-8080}"
LOG_FILE="${LOG_FILE:-$SCRIPT_DIR/mini-sqs.log}"

mkdir -p "$QUEUE_DIR"
touch "$LOG_FILE"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

generate_id() {
    echo "$(date +%s%N)"
}

# filas
create_queue() {
    local queue="$1"
    local qfile="$QUEUE_DIR/$queue.q"

    if [[ ! -f "$qfile" ]]; then
        touch "$qfile"
        log "Queue created: $queue"
    fi
}

send_message() {
    local queue="$1"
    local body="$2"
    local qfile="$QUEUE_DIR/$queue.q"

    local id
    id=$(generate_id)
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    (
        flock -x 200
        printf '{"id":"%s","timestamp":"%s","body":%s,"status":"available"}\n' \
            "$id" "$ts" "$(printf '%s' "$body" | jq -Rs .)" >> "$qfile"
    ) 200>"$qfile.lock"

    printf '{"messageId":"%s","queue":"%s"}\n' "$id" "$queue"
}

receive_message() {
    local queue="$1"
    local qfile="$QUEUE_DIR/$queue.q"

    local line msg_id

    (
        flock -x 200

        while IFS= read -r line; do
            if echo "$line" | grep -q '"status":"available"'; then
                msg_id=$(echo "$line" | jq -r '.id')

                tmp="${qfile}.tmp"
                : > "$tmp"

                while IFS= read -r l; do
                    if echo "$l" | grep -q "\"id\":\"$msg_id\""; then
                        echo "$l" | jq '.status="processing"' >> "$tmp"
                    else
                        echo "$l" >> "$tmp"
                    fi
                done < "$qfile"

                mv "$tmp" "$qfile"
                echo "$line" | jq '.status="processing"'
                return 0
            fi
        done < "$qfile"

        echo "{}"
    ) 200>"$qfile.lock"
}

delete_message() {
    local queue="$1"
    local msg_id="$2"
    local qfile="$QUEUE_DIR/$queue.q"

    (
        flock -x 200
        tmp="${qfile}.tmp"
        : > "$tmp"

        while IFS= read -r line; do
            if ! echo "$line" | grep -q "\"id\":\"$msg_id\""; then
                echo "$line" >> "$tmp"
            fi
        done < "$qfile"

        mv "$tmp" "$qfile"
    ) 200>"$qfile.lock"

    printf '{"deleted":"%s"}\n' "$msg_id"
}

peek_message() {
    local queue="$1"
    local qfile="$QUEUE_DIR/$queue.q"

    (
        flock -s 200
        while IFS= read -r line; do
            if echo "$line" | grep -q '"status":"available"'; then
                echo "$line"
                return 0
            fi
        done < "$qfile"

        echo "{}"
    ) 200>"$qfile.lock"
}

queue_stats() {
    local queue="$1"
    local qfile="$QUEUE_DIR/$queue.q"

    (
        flock -s 200

        local total available processing

        # tratamento espacos em branco
        total=$(wc -l < "$qfile" | tr -d ' ')
        available=$(grep -c '"status":"available"' "$qfile" 2>/dev/null || echo 0)
        processing=$(grep -c '"status":"processing"' "$qfile" 2>/dev/null || echo 0)

        printf '{"queue":"%s","total":%d,"available":%d,"processing":%d}\n' \
            "$queue" "$total" "$available" "$processing"
    ) 200>"$qfile.lock"
}

# http response
send_headers() {
    printf "HTTP/1.1 200 OK\r\n"
    printf "Content-Type: application/json\r\n"
    printf "Connection: close\r\n"
    printf "\r\n"
}

# http serv
process_request() {
    local method="$1"
    local path="$2"
    local body="$3"

    log "Request: $method $path"

    send_headers

    # HEALTH
    if [[ "$path" == "/health" ]]; then
        printf '{"status":"healthy"}\n'
        return
    fi

    # lista
    if [[ "$method" == "GET" && "$path" == "/queues" ]]; then
        ls "$QUEUE_DIR" | sed 's/\.q$//' | jq -R . | jq -s .
        return
    fi

    # cria
    if [[ "$method" == "POST" && "$path" =~ ^/queue/([^/]+)$ ]]; then
        local queue="${BASH_REMATCH[1]}"
        create_queue "$queue"
        printf '{"queue":"%s","status":"created"}\n' "$queue"
        return
    fi

    # enviar
    if [[ "$method" == "POST" && "$path" =~ ^/queue/([^/]+)/send$ ]]; then
        local queue="${BASH_REMATCH[1]}"
        send_message "$queue" "$body"
        return
    fi

    # receber
    if [[ "$method" == "GET" && "$path" =~ ^/queue/([^/]+)/receive$ ]]; then
        local queue="${BASH_REMATCH[1]}"
        receive_message "$queue"
        return
    fi

    # peek
    if [[ "$method" == "GET" && "$path" =~ ^/queue/([^/]+)/peek$ ]]; then
        local queue="${BASH_REMATCH[1]}"
        peek_message "$queue"
        return
    fi

    # del
    if [[ "$method" == "DELETE" && "$path" =~ ^/queue/([^/]+)/message/([^/]+)$ ]]; then
        local queue="${BASH_REMATCH[1]}"
        local id="${BASH_REMATCH[2]}"
        delete_message "$queue" "$id"
        return
    fi

    # STATS
    if [[ "$method" == "GET" && "$path" =~ ^/queue/([^/]+)/stats$ ]]; then
        local queue="${BASH_REMATCH[1]}"
        queue_stats "$queue"
        return
    fi

    printf '{"error":"not_found"}\n'
}

handle_connection() {
    # Não deixe erro de leitura matar o processo à toa
    if ! read -r request_line; then
        return 0
    fi

    method=$(echo "$request_line" | awk '{print $1}')
    path=$(echo "$request_line" | awk '{print $2}')

    content_length=0
    # Ler cabeçalhos HTTP até linha em branco
    while IFS=$'\r' read -r header; do
        header=$(echo "$header" | tr -d '\r\n')
        [[ -z "$header" ]] && break
        if echo "$header" | grep -qi '^Content-Length:'; then
            content_length=$(echo "$header" | awk '{print $2}')
        fi
    done

    body=""
    if [[ "$content_length" -gt 0 ]]; then
        body=$(dd bs=1 count="$content_length" 2>/dev/null || true)
    fi

    process_request "$method" "$path" "$body"
}

log "Mini SQS started on port $PORT"

if [[ "${1:-}" == "worker" ]]; then
    handle_connection || true
    exit 0
fi

socat TCP-LISTEN:"$PORT",fork,reuseaddr EXEC:"bash $SCRIPT_DIR/mini-sqs.sh worker",stderr 2>>"$LOG_FILE"
