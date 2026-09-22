#!/bin/bash
set -euo pipefail

DEFCONFIG="xcalibur-perf_defconfig"
DEFCONFIG_PATH="arch/arm64/configs/vendor/${DEFCONFIG}"

export ARCH=arm64
export SUBARCH=arm64

mkdir -p out

make -j"$(nproc --all)" O=out "vendor/${DEFCONFIG}"
make -j"$(nproc --all)" O=out savedefconfig
cp -af out/defconfig "${DEFCONFIG_PATH}"

git add "${DEFCONFIG_PATH}"
git commit -m "arm64: configs: vendor: xcalibur-perf: Regenerate"
echo -e "\nSuccessfully regenerated defconfig at ${DEFCONFIG_PATH}"
