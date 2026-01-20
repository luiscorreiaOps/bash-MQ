#!/bin/bash
set -eo pipefail

# ============================================================================
# Mini SQS - Inicializador Universal
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================================
# DETECTAR AMBIENTE
# ============================================================================

detect_environment() {
    if [[ -f /.dockerenv ]] || grep -q docker /proc/1/cgroup 2>/dev/null; then
        echo "container"
    elif [[ -n "${KUBERNETES_SERVICE_HOST:-}" ]]; then
        echo "kubernetes"
    else
        echo "local"
    fi
}

# ============================================================================
# CONFIGURAR DIRETÓRIOS
# ============================================================================

setup_directories() {
    local env="$1"

    case "$env" in
        container|kubernetes)
            QUEUE_DIR="/data/queues"
            LOG_FILE="/var/log/mini-sqs.log"
            mkdir -p "$QUEUE_DIR"
            mkdir -p "$(dirname "$LOG_FILE")"
            ;;
        local)
            QUEUE_DIR="$SCRIPT_DIR/queues"
            LOG_FILE="$SCRIPT_DIR/mini-sqs.log"
            mkdir -p "$QUEUE_DIR"
            touch "$LOG_FILE"
            ;;
    esac

    export QUEUE_DIR
    export LOG_FILE

    echo "[INFO] QUEUE_DIR: $QUEUE_DIR"
    echo "[INFO] LOG_FILE: $LOG_FILE"
}

# ============================================================================
# VERIFICAR DEPENDÊNCIAS
# ============================================================================

check_dependencies() {
    local missing=()

    for cmd in bash flock jq sed grep socat; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "[ERROR] Dependências faltando: ${missing[*]}"
        echo "[INFO] Instale com:"
        echo "  Debian/Ubuntu: sudo apt install ${missing[*]}"
        echo "  Fedora:        sudo dnf install ${missing[*]}"
        echo "  Alpine:        sudo apk add ${missing[*]}"
        exit 1
    fi
}

# ============================================================================
# CONFIGURAR PORTA
# ============================================================================

setup_port() {
    PORT="${PORT:-8080}"
    echo "[INFO] Porta configurada (fixa): $PORT"
    export PORT
}

    export PORT
    echo "[INFO] Porta configurada: $PORT"


# ============================================================================
# INICIAR SERVIDOR
# ============================================================================

start_server() {
    echo ""
    echo "=========================================="
    echo "  Mini SQS - Iniciando Servidor"
    echo "=========================================="
    echo "  Ambiente:    $ENV"
    echo "  Porta:       $PORT"
    echo "  Filas:       $QUEUE_DIR"
    echo "  Logs:        $LOG_FILE"
    echo "=========================================="
    echo ""

    if [[ -f "$SCRIPT_DIR/mini-sqs.sh" ]]; then
        exec "$SCRIPT_DIR/mini-sqs.sh"
    else
        echo "[ERROR] Arquivo mini-sqs.sh não encontrado em $SCRIPT_DIR"
        exit 1
    fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    echo "[INFO] Inicializando Mini SQS..."

    # 1. Detectar ambiente
    ENV=$(detect_environment)
    echo "[INFO] Ambiente detectado: $ENV"

    # 2. Configurar diretórios
    setup_directories "$ENV"

    # 3. Verificar dependências
    check_dependencies

    # 4. Configurar porta
    setup_port

    # 5. Iniciar servidor
    start_server
}

# Executar
main "$@"
