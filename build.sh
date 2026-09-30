#!/usr/bin/env bash
set -euo pipefail

# Resolve paths
WWW_ROOT_ARG="${1:-/var/www}/lomotron.de/pub/models/tts"
if [ -d "${WWW_ROOT_ARG}" ]; then
    WWW_ROOT="$(cd "${WWW_ROOT_ARG}" && pwd)"
else
    mkdir -p "${WWW_ROOT_ARG}" 2>/dev/null || true
    if [ -d "${WWW_ROOT_ARG}" ]; then
        WWW_ROOT="$(cd "${WWW_ROOT_ARG}" && pwd)"
    else
        WWW_ROOT="${WWW_ROOT_ARG}"
    fi
fi
# mkdir -p "${WWW_ROOT}" 2>/dev/null

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

# 3.1 Adding german.txt and Cleaning up unwanted files
rm -f "${REPO_ROOT}/pocket-tts-onnx/onnx/german/flow_lm_flow.onnx"
rm -f "${REPO_ROOT}/pocket-tts-onnx/onnx/german/flow_lm_main.onnx"
rm -f "${REPO_ROOT}/pocket-tts-onnx/onnx/german/mimi_encoder_int8.onnx"
rm -f "${REPO_ROOT}/pocket-tts-onnx/onnx/german/mimi_decoder.onnx"
rm -f "${REPO_ROOT}/pocket-tts-onnx/onnx/german/text_conditioner_int8.onnx"

mkdir -p "${REPO_ROOT}/pocket-tts-onnx/onnx/german/test_wavs"
cp ${REPO_ROOT}/pocket_tts/config/*.wav "${REPO_ROOT}/pocket-tts-onnx/onnx/german/test_wavs/"
cp ${REPO_ROOT}/pocket_tts/config/*.txt "${REPO_ROOT}/pocket-tts-onnx/onnx/german/test_wavs/"

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
    if [ "${WWW_ROOT}" != "${REPO_ROOT}/target" ]; then
        sudo -n -u www-data cp -a "${REPO_ROOT}/target/pocket-tts-onnx-german."* "${WWW_ROOT}/" 2>/dev/null || true
    fi
    echo "==> Cleaning old releases (keeping last 3)..."
    sudo -n -u www-data bash -c "ls -dt '${RELEASES_DIR}/'* 2>/dev/null | tail -n +4 | xargs -r rm -rf"
else
    mkdir -p "${RELEASE_PATH}"
    tar -C "${REPO_ROOT}/target" -cf - . | tar -C "${RELEASE_PATH}" -xf -
    ln -sfn "${RELEASE_PATH}" "${CURRENT_LINK}"
    if [ "${WWW_ROOT}" != "${REPO_ROOT}/target" ]; then
        cp -a "${REPO_ROOT}/target/pocket-tts-onnx-german."* "${WWW_ROOT}/" 2>/dev/null || true
    fi
    echo "==> Cleaning old releases (keeping last 3)..."
    bash -c "ls -dt '${RELEASES_DIR}/'* 2>/dev/null | tail -n +4 | xargs -r rm -rf" || true
fi

echo "==> Deployment completed successfully! Active release: ${RELEASE_TAG}"
