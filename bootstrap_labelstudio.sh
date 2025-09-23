#!/usr/bin/env bash
# Bootstrap Label Studio on a fresh SageMaker Studio instance.
# Usage: ./bootstrap_labelstudio.sh
# Save with LF (Unix) line endings.

set -euo pipefail

echo "=== Label Studio bootstrap for SageMaker Studio ==="

# --- 0) Collect inputs -------------------------------------------------------
echo "[*] Gathering required inputs..."
read -rp "Enter your AWS region (e.g., eu-west-2): " REGION
[[ -z "${REGION}" ]] && { echo "[!] Region required. Aborting."; exit 1; }

read -rp "Enter your SageMaker Studio base token OR full URL: " INPUT
[[ -z "${INPUT}" ]] && { echo "[!] Token or URL required. Aborting."; exit 1; }

# Accept full URL or token; derive STUDIO_BASE
if [[ "$INPUT" == http*://* ]]; then
  HOST=${INPUT#*://}; HOST=${HOST%%/*}
  TOKEN=${HOST%%.studio.*}
else
  TOKEN=$INPUT
fi
[[ "$TOKEN" =~ ^[A-Za-z0-9-]+$ ]] || { echo "[!] Invalid token: $TOKEN"; exit 1; }

STUDIO_BASE="https://${TOKEN}.studio.${REGION}.sagemaker.aws"
echo "[*] Using Studio base: $STUDIO_BASE"

read -rp "Enter Label Studio username (email): " LS_USER
read -srp "Enter Label Studio password: " LS_PASS
echo
[[ -z "${LS_USER}" || -z "${LS_PASS}" ]] && { echo "[!] Username and password required. Aborting."; exit 1; }

# --- 1) Conda bootstrap (no 'conda init' needed) -----------------------------
echo "[*] Loading conda environment tooling..."
if [[ -f /opt/conda/etc/profile.d/conda.sh ]]; then
  source /opt/conda/etc/profile.d/conda.sh
else
  echo "[!] Conda not found at /opt/conda. Aborting." >&2
  exit 1
fi

# --- 2) Create/activate persistent env --------------------------------------
ENV_PATH="$HOME/conda-envs/labelstudio"
echo "[*] Ensuring conda env at: $ENV_PATH"
mkdir -p "$(dirname "$ENV_PATH")"
if ! conda env list | grep -q "^$ENV_PATH"; then
  echo "[*] Creating conda environment (python=3.11)..."
  conda create -y -p "$ENV_PATH" python=3.11
else
  echo "[*] Conda environment already exists."
fi
echo "[*] Activating conda environment..."
conda activate "$ENV_PATH"

# --- 3) Install/upgrade packages (idempotent) --------------------------------
echo "[*] Installing/upgrading Label Studio packages..."
python -m pip install --upgrade pip
pip install --upgrade label-studio label-studio-sdk

# --- 4) Write env files ------------------------------------------------------
CFG_DIR="$HOME/.labelstudio"
DATA_DIR="$HOME/labelstudio-data"
echo "[*] Writing configuration to: $CFG_DIR"
mkdir -p "$CFG_DIR" "$DATA_DIR"

# Static env (credentials, fixed settings)
cat > "$CFG_DIR/static.env" <<EOSTATIC
LABEL_STUDIO_USERNAME="$LS_USER"
LABEL_STUDIO_PASSWORD="$LS_PASS"
DJANGO_ALLOWED_HOSTS="*"
LS_DATA_DIR="\$HOME/labelstudio-data"
EOSTATIC

# Session env (Studio base + proxy host)
cat > "$CFG_DIR/session.env" <<EOS
STUDIO_BASE="$STUDIO_BASE"
LABEL_STUDIO_HOST="$STUDIO_BASE/jupyterlab/default/proxy/8080"
LABEL_STUDIO_CSRF_TRUSTED_ORIGINS="$STUDIO_BASE"
EOS

# --- 5) Create launcher ------------------------------------------------------
echo "[*] Creating launcher: ~/start_labelstudio.sh"
cat > "$HOME/start_labelstudio.sh" <<'EOLAUNCH'
#!/usr/bin/env bash
# Start Label Studio inside SageMaker Studio using saved env files.
set -euo pipefail

# Load conda (no conda init)
# shellcheck disable=SC1091
source /opt/conda/etc/profile.d/conda.sh
conda activate "$HOME/conda-envs/labelstudio"

# Load env vars
set -a
source "$HOME/.labelstudio/static.env"
[[ -f "$HOME/.labelstudio/session.env" ]] && source "$HOME/.labelstudio/session.env"
set +a

# If missing, prompt once and persist (accept token or full URL; also ask region)
if [[ -z "${STUDIO_BASE:-}" || -z "${LABEL_STUDIO_HOST:-}" ]]; then
  echo "[*] Session base not found. Collecting details..."
  read -rp "Enter Studio base token OR full URL: " INPUT
  if [[ "$INPUT" == http*://* ]]; then
    HOST=${INPUT#*://}; HOST=${HOST%%/*}
    TOKEN=${HOST%%.studio.*}
  else
    TOKEN=$INPUT
  fi
  read -rp "Enter AWS region (e.g., eu-west-2): " REGION
  STUDIO_BASE="https://${TOKEN}.studio.${REGION}.sagemaker.aws"
  LABEL_STUDIO_HOST="$STUDIO_BASE/jupyterlab/default/proxy/8080"
  LABEL_STUDIO_CSRF_TRUSTED_ORIGINS="$STUDIO_BASE"
  {
    echo "STUDIO_BASE=\"$STUDIO_BASE\""
    echo "LABEL_STUDIO_HOST=\"$LABEL_STUDIO_HOST\""
    echo "LABEL_STUDIO_CSRF_TRUSTED_ORIGINS=\"$STUDIO_BASE\""
  } > "$HOME/.labelstudio/session.env"
fi

# Ensure data dir
mkdir -p "$LS_DATA_DIR"

# --- Print the proxy URL prominently before logs ---
echo ""
echo "======================================================="
echo " Label Studio will be available at:"
echo "   ${LABEL_STUDIO_HOST}/"
echo "======================================================="
echo ""

# Start Label Studio
label-studio start --data-dir "$LS_DATA_DIR" --port 8080 --host 0.0.0.0
EOLAUNCH

chmod +x "$HOME/start_labelstudio.sh"

echo "=== Bootstrap complete ==="
echo "Run to start Label Studio next time:  ~/start_labelstudio.sh"
