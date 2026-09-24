#!/usr/bin/env bash
# Written by: cyberknight777
# YAKB v2.0
# Copyright (c) 2022-2023 Cyber Knight <cyberknight755@gmail.com>
#
#			GNU GENERAL PUBLIC LICENSE
#			 Version 3, 29 June 2007
#
# Copyright (C) 2007 Free Software Foundation, Inc. <https://fsf.org/>
# Everyone is permitted to copy and distribute verbatim copies
# of this license document, but changing it is not allowed.

# Some Placeholders: [!] [*] [✓] [✗]

BOT_MSG_URL="https://api.telegram.org/bot${TOKEN}/sendMessage"
BOT_BUILD_URL="https://api.telegram.org/bot${TOKEN}/sendDocument"
BOT_STICKER_URL="https://api.telegram.org/bot${TOKEN}/sendSticker"

# Helper function to escape HTML special characters (<, >, &)
escape_html() {
  local val="$1"
  val="${val//&/&amp;}"
  val="${val//</&lt;}"
  val="${val//>/&gt;}"
  echo "$val"
}

tg_post_msg() {
  local clean_text
  clean_text=$(echo "$1" | tr -d '\r')
  curl -s -X POST "$BOT_MSG_URL" -d chat_id="$CHATID" \
    -d "disable_web_page_preview=true" \
    -d "parse_mode=html" \
    -d text="$clean_text"
}

tg_post_build(){
  local MD5CHECK
  MD5CHECK=$(md5sum "$1" | cut -d' ' -f1)
  curl --progress-bar -F document=@"$1" "$BOT_BUILD_URL" \
    -F chat_id="$CHATID" \
    -F "disable_web_page_preview=true" \
    -F "parse_mode=Markdown" \
    -F caption="$2 | *MD5 Checksum : *\`$MD5CHECK\`"
}

tg_post_sticker() {
  curl -s -X POST "$BOT_STICKER_URL" -d chat_id="$CHATID" \
    -d sticker="CAACAgUAAxkBAAECHIJgXlYR8K8bYvyYIpHaFTJXYULy4QACtgIAAs328FYI4H9L7GpWgR4E"
}

# Build Configurations & Variables
export CONFIG=vendor/xcalibur-perf_defconfig
KDIR=$(pwd)
export KDIR
export LINKER="ld"
export DEVICE="Redmi Note 7 Pro"
DATE=$(date +"%Y-%m-%d")
export DATE
export CODENAME="Violet"
export BUILDER="Joker-V2"
export REPO_URL="https://github.com/AxionAOSP-devices/android_kernel_xiaomi_violet"
COMMIT_HASH=$(git rev-parse --short HEAD)
export COMMIT_HASH
PROCS=$(nproc --all)
export PROCS
export ARCH=arm64

OUT_DIR="${KDIR}/out"
kernel_name="Xcalibur-v6.0-violet"
support="Android 14.0-16.0"
variant="Retrofit Dynamic"
cores=$(nproc --all)

os_info=$(grep -oP 'PRETTY_NAME="\K[^"]+' /etc/os-release 2>/dev/null || cat /etc/issue | head -n 1 | tr -d '\\\r')
build_time_str=$(TZ="Asia/Kolkata" date "+%a %b %d %r")
commit_head=$(git log --oneline -1 2>/dev/null | tr -d '\\\r' || echo "Unknown commit")

zipn="${kernel_name}-$(date '+%Y%m%d-%H%M').zip"

# Exit on SIGINT
exit_on_signal_SIGINT() {
	echo -e "\n\n\e[1;31m[✗] Received INTR call - Exiting...\e[0m"
	exit 0
}
trap exit_on_signal_SIGINT SIGINT

MAKE+=(
    ARCH=arm64
    O="${OUT_DIR}"
    CROSS_COMPILE=aarch64-linux-gnu-
    CROSS_COMPILE_ARM32=arm-linux-gnueabi-
    LLVM=1
    LLVM_IAS=1
    LD=ld.lld
)

if [ ! -d "${KDIR}/AnyKernel3/" ]; then
	git clone -b sixteen https://github.com/Joker-V2/AnyKernel3
fi

export KBUILD_BUILD_USER="Joker-V2"
export KBUILD_BUILD_HOST="Xcalibur-Ci"

# A function to inject build date into anykernel.sh
patch_anykernel() {
    sed -i "s/##   Build    :  .*                 ##/##   Build    :  ${DATE}                 ##/" \
        "${KDIR}/AnyKernel3/anykernel.sh"
    echo -e "\n\e[1;32m[✓] Build date injected: ${DATE}\e[0m"
}

# A function to build AnyKernel3 zip, sign it with AOSP keys, upload it, and notify Telegram.
mkzip() {
	echo -e "\n\e[1;93m[*] Building zip! \e[0m"
	mkdir -p "${KDIR}"/AnyKernel3/dtbs
	if [ -f "${OUT_DIR}/arch/arm64/boot/Image.gz" ]; then
		mv "${OUT_DIR}/arch/arm64/boot/Image.gz" "${KDIR}"/AnyKernel3 || { tg_post_msg "<code>Failed to move Image.gz! ❎</code>"; exit 1; }
	fi
	[ -f "${OUT_DIR}/arch/arm64/boot/dtbo.img" ] && mv "${OUT_DIR}/arch/arm64/boot/dtbo.img" "${KDIR}"/AnyKernel3
	patch_anykernel

	cd "${KDIR}"/AnyKernel3 || exit 1
	zip -r9 "$zipn" . -x ".git*" -x "README.md" -x "LICENSE" -x "*.zip" || exit 1

	mv "$zipn" "${KDIR}/$zipn"
	cd "${KDIR}"

	# Sign the zip with AOSP keys
	tg_post_msg "<code>Signing build with AOSP keys </code>"
	if [ ! -f "zipsigner-3.0.jar" ]; then
		wget -q -O zipsigner-3.0.jar https://github.com/Magisk-Modules-Repo/zipsigner/raw/master/bin/zipsigner-3.0-dexed.jar
	fi
	signed_zip="${zipn%.zip}-signed.zip"
	java -jar zipsigner-3.0.jar "$zipn" "$signed_zip"

	# Send Document & Upload
	DIFF=$((BUILD_END - BUILD_START))
	tg_post_build "${KDIR}/$signed_zip" "Build took : $((DIFF / 60)) minute(s) and$((DIFF % 60)) second(s)"
	tg_post_msg "<code>Compiled and Signed successfully ✅</code>"
	curl -s -T "${KDIR}/$signed_zip" bashupload.com

	echo -e "\n\e[1;32m[✓] Built, signed, and uploaded zip successfully! \e[0m"
}

img() {
	# 1. Send Telegram Trigger Banner
	tg_post_sticker

	local safe_commit
	local safe_os
	safe_commit=$(escape_html "$commit_head")
	safe_os=$(escape_html "$os_info")

	local trigger_msg="<b>Build Triggered ⌛</b>%0A"
	trigger_msg+="<b>Kernel : </b><code>$kernel_name</code>%0A"
	trigger_msg+="<b>Support : </b><code>$support</code>%0A"
	trigger_msg+="<b>Variant : </b><code>$variant</code>%0A"
	trigger_msg+="<b>Machine : </b><code>$safe_os</code>%0A"
	trigger_msg+="<b>Cores : </b><code>$cores</code>%0A"
	trigger_msg+="<b>Time : </b><code>$build_time_str</code>%0A"
	trigger_msg+="<b>Top Commit : </b><code>$safe_commit</code>"
	tg_post_msg "$trigger_msg"

	# 2. Toolchain Check & Notification
	if [ ! -f "${KDIR}/neutron-clang/bin/clang" ]; then
		tg_post_msg "<code>Toolchain not found! Cloning Neutron-Clang </code>"
		rm -rf "${KDIR}"/neutron-clang
		mkdir "${KDIR}"/neutron-clang
		cd "${KDIR}"/neutron-clang || exit 1
		bash <(curl -s "https://raw.githubusercontent.com/Neutron-Toolchains/antman/main/antman") -S
		cd "${KDIR}" || exit 1
	else
		tg_post_msg "<code>Neutron Clang is already present ✅</code>"
	fi

	KBUILD_COMPILER_STRING=$("${KDIR}"/neutron-clang/bin/clang -v 2>&1 | head -n 1 | sed 's/(https..*//' | sed 's/ version//')
	export KBUILD_COMPILER_STRING
	export PATH=$KDIR/neutron-clang/bin/:/usr/bin/:${PATH}

	# 3. Defconfig Generation & Notification
	echo -e "\n\e[1;93m[*] Applying defconfig (${CONFIG})... \e[0m"
	make "${MAKE[@]}" $CONFIG || { tg_post_msg "<code>Defconfig generation failed ❎</code>"; exit 1; }
	tg_post_msg "<code>Defconfig generated successfully ✅</code>"

	# 4. Build Kernel & Final Package
	echo -e "\n\e[1;93m[*] Building Kernel! \e[0m"
	BUILD_START=$(date +"%s")
	time make -j"$PROCS" "${MAKE[@]}" Image.gz-dtb Image.gz dtbs 2>&1 | tee error.log
	BUILD_END=$(date +"%s")

	if [ -f "${OUT_DIR}/arch/arm64/boot/Image.gz" ]; then
		echo -e "\n\e[1;32m[✓] Kernel built successfully! \e[0m"
		mkzip
	else
		tg_post_build "${KDIR}/error.log" "Debug Mode Logs"
		tg_post_msg "<code>Compilation failed ❎</code>"
		echo -e "\n\e[1;31m[✗] Build Failed! Check error.log\e[0m"
		exit 1
	fi
}

# Execute build
img
