#!/bin/bash

# =================================================================
#  Build Script - by Riaru Moda
#  Target Device: Xiaomi Redmi Note 7 Pro (violet)
# =================================================================

echo "- Setting up build environment..."
export KBUILD_BUILD_USER=Joker-V2
export KBUILD_BUILD_HOST=superior.ci
export KERNEL_NAME="-xcalibur"
export KERNEL_VERSION="4.14"

export MAIN_DEFCONFIG="arch/arm64/configs/vendor/sdmsteppe-perf_defconfig"
export ACTUAL_MAIN_DEFCONFIG="vendor/sdmsteppe-perf_defconfig"
export COMMON_DEFCONFIG="vendor/debugfs.config"
export DEVICE_DEFCONFIG="vendor/violet.config"

export CLANG_ROOT="$PWD/clang"
export GCC64_ROOT="$PWD/gcc64"
export GCC32_ROOT="$PWD/gcc32"
export PATH="$CLANG_ROOT/bin:$GCC64_ROOT/bin:$GCC32_ROOT/bin:/usr/bin:$PATH"

export MAKE_ARGS=(
        ARCH=arm64 LLVM=1 LLVM_IAS=1 CC=clang LD=ld.lld AR=llvm-ar AS=llvm-as
        NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip
        CROSS_COMPILE=aarch64-linux-android- CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
        CLANG_TRIPLE=aarch64-linux-gnu-
)

TC_URLS=(
    "clang|https://github.com/LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b.git"
    "gcc64|https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-android-4.9.git"
    "gcc32|https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_arm_arm-linux-androideabi-4.9.git"
)

for tc in "${TC_URLS[@]}"; do
    dir="${tc%%|*}"; url="${tc##*|}"
    if [ ! -d "$dir/.git" ]; then
        echo "-- Cloning $dir..."
        rm -rf "$dir"
        git clone "$url" --depth=1 "$dir" &> /dev/null || { echo "-- Fatal: Failed to clone $dir!"; exit 1; }
    else
        echo "-- Using local $dir"
    fi
done

echo "-- Applying O3 compiler optimization tweaks..."
sed -i 's/KBUILD_CFLAGS\s\++= -O2/KBUILD_CFLAGS   += -O3/g' Makefile
sed -i 's/LDFLAGS\s\++= -O2/LDFLAGS += -O3/g' Makefile

rm -rf out
mkdir -p out &> /dev/null
MAKE_CMD=(make O=out "${MAKE_ARGS[@]}")

echo "-- Generating base configuration engine..."
"${MAKE_CMD[@]}" $ACTUAL_MAIN_DEFCONFIG &> /dev/null

echo "-- Merging configuration fragments..."
for fragment in $COMMON_DEFCONFIG $DEVICE_DEFCONFIG; do
    if [ -f "arch/arm64/configs/$fragment" ]; then
        echo "   -> Merging $fragment..."
        cat "arch/arm64/configs/$fragment" >> out/.config
    fi
done

echo "CONFIG_LOCALVERSION=\"$KERNEL_NAME\"" >> out/.config
echo "CONFIG_LOCALVERSION_AUTO=n" >> out/.config

echo "-- Validating defconfig generation..."
{ yes "" 2>/dev/null || true; } | "${MAKE_CMD[@]}" olddefconfig &> /dev/null
{ yes "" 2>/dev/null || true; } | "${MAKE_CMD[@]}" syncconfig &> /dev/null

echo " "
echo "====================================="
echo " COMPILING PROCESS STARTED FOR VIOLET"
echo "====================================="
echo " "

make -j$(nproc --all) O=out "${MAKE_ARGS[@]}"

echo " "
echo "====================================="
echo " COMPILING PROCESS COMPLETED         "
echo "====================================="
echo " "

if [ -f "out/arch/arm64/boot/Image.gz" ]; then
    echo "- Build successful! Starting AnyKernel3 packaging process..."
    DATE=$(date +'%Y%m%d')
    TIME=$(date +'%s')

    if [ -d "$PWD/AnyKernel3" ]; then
        rm -rf AnyKernel3
    fi

    echo "-- Cloning AnyKernel3 flash template..."
    git clone https://github.com/riarumoda/AnyKernel3 AnyKernel3 --depth=1 &> /dev/null

    echo "-- Transferring Image.gz into template..."
    cp out/arch/arm64/boot/Image.gz AnyKernel3/

    echo "-- Injecting flash rules and configurations for violet..."
    sed -i 's/supported.versions=11-16/supported.versions=15-16/' AnyKernel3/anykernel.sh
    sed -i 's/device.name1=sweet/device.name1=violet/' AnyKernel3/anykernel.sh
    sed -i 's/device.name2=sweetin/device.name2=violetin/' AnyKernel3/anykernel.sh
    sed -i 's/sweet (sm6150)/violet (sm6150)/g' AnyKernel3/banner
    sed -i "$a \\nBuild timestamp: $TIME" AnyKernel3/banner

    echo "-- Packing files into flashable recovery zip..."
    ZIPNAME="xcalibur-violet-weekly-$DATE.zip"
    cd AnyKernel3
    zip -rq9 "../$ZIPNAME" ./*
    cd ..

    echo " "
    echo "=========================================================="
    echo " SUCCESS: Your flashable kernel zip is ready!"
    echo " Location: $PWD/$ZIPNAME"
    echo "=========================================================="
    echo " "
    ls -lah "$ZIPNAME"
else
    echo "- Error: out/arch/arm64/boot/Image.gz was not found. Compilation failed."
    exit 1
fi
