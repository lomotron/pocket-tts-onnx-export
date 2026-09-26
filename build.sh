#!/usr/bin/env bash
set -euo pipefail

# Resolve paths
WWW_ROOT="${1:-/var/www/lomotron.de/pub/models/tts}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CURRENT_LINK="${WWW_ROOT}/current"
RELEASES_DIR="${WWW_ROOT}/releases"

RELEASE_TAG="$(date +%Y%m%d%H%M%S)"
RELEASE_PATH="${RELEASES_DIR}/${RELEASE_TAG}"

echo "=================================================="
echo "==> Export & Package PocketTTS Models: ${RELEASE_TAG}"
echo "=================================================="

# 1. Setup / activate virtual environment
VENV_DIR="${REPO_ROOT}/.venv"
if [ ! -d "${VENV_DIR}" ] || [ ! -f "${VENV_DIR}/bin/activate" ]; then
    echo "==> Creating Python virtual environment in ${VENV_DIR}..."
    python3 -m venv "${VENV_DIR}"
fi

# shellcheck source=/dev/null
source "${VENV_DIR}/bin/activate"

echo "==> Installing / updating dependencies from requirements.txt..."
pip install -r "${REPO_ROOT}/requirements.txt"

# 2. Export and quantize ONNX models
echo "==> Exporting German PocketTTS ONNX models..."
cd "${REPO_ROOT}"
python export.py --language german --quantize

# 3. Prepare target directory and tarballs
rm -rf "${REPO_ROOT}/target"
mkdir -p "${REPO_ROOT}/target"

TARBALL_NAME="pocket-tts-onnx-german.tar.gz"
echo "==> Creating tarball ${TARBALL_NAME}..."
tar -czf "${REPO_ROOT}/target/${TARBALL_NAME}" -C "${REPO_ROOT}" pocket-tts-onnx
tar -cjf "${REPO_ROOT}/target/pocket-tts-onnx-german.tar.bz2" -C "${REPO_ROOT}" pocket-tts-onnx
cd "${REPO_ROOT}/target"
ln -sf "${TARBALL_NAME}" "pocket-tts-onnx-german.tgz"
# Also expose the directory structure directly in target for direct file access
tar -C "${REPO_ROOT}" -cf - pocket-tts-onnx | tar -xf -
cd "${REPO_ROOT}"

echo "==> Build completed successfully in ${REPO_ROOT}/target"

# 4. Deploy release
echo "==> Deploying to atomic release: ${RELEASE_PATH}..."
if sudo -n -u www-data true 2>/dev/null; then
    sudo -n -u www-data mkdir -p "${RELEASE_PATH}"
    tar -C "${REPO_ROOT}/target" -cf - . | sudo -n -u www-data tar -C "${RELEASE_PATH}" -xf -
    sudo -n -u www-data ln -sfn "${RELEASE_PATH}" "${CURRENT_LINK}"
    echo "==> Cleaning old releases (keeping last 3)..."
    sudo -n -u www-data bash -c "ls -dt '${RELEASES_DIR}/'* 2>/dev/null | tail -n +4 | xargs -r rm -rf"
else
    mkdir -p "${RELEASE_PATH}"
    tar -C "${REPO_ROOT}/target" -cf - . | tar -C "${RELEASE_PATH}" -xf -
    ln -sfn "${RELEASE_PATH}" "${CURRENT_LINK}"
    echo "==> Cleaning old releases (keeping last 3)..."
    bash -c "ls -dt '${RELEASES_DIR}/'* 2>/dev/null | tail -n +4 | xargs -r rm -rf" || true
fi

echo "==> Deployment completed successfully! Active release: ${RELEASE_TAG}"
