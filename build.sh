#!/usr/bin/env bash
# Copyright (C) 2019-2020 Jago Gardiner (nysascape)
#
# Licensed under the Raphielscape Public License, Version 1.d (the "License");
# you may not use this file except in compliance with the License.
#
# CI build script

# Needed exports
export TELEGRAM_TOKEN=7485743487:AAEKPw9ubSKZKit9BDHfNJSTWcWax4STUZs
export ANYKERNEL=$(pwd)/anykernel3

# Avoid hardcoding things
KERNEL=Wonderhoy
DEFCONFIG=surya_defconfig
MODEL=POCO X3 NGC
DEVICE=surya
CIPROVIDER=Github-Ubuntu
CLANG="Neutron Clang"
COMPILERDIR="$(pwd)/tc/clang-neutron"
PARSE_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
PARSE_ORIGIN="$(git config --get remote.origin.url)"
COMMIT_POINT="$(git log --pretty=format:'%h : %s' -1)"

# Export custom KBUILD
export KBUILD_BUILD_USER=mahiroo
export KBUILD_BUILD_HOST=wonderhoy-core
export OUTFILE=${OUTDIR}/arch/arm64/boot/Image.gz-dtb

# Kernel groups
CI_CHANNEL=-1002354747626

# Set default local datetime
DATE=$(TZ=Asia/Jakarta date +"%Y%m%d-%T")
BUILD_DATE=$(TZ=Asia/Jakarta date +"%Y%m%d-%H%M")

# Kernel revision
KERNELRELEASE=surya

# Clone AOSP Clang
function clang() {
export PATH="$COMPILERDIR/bin:$PATH"

if ! [ -d "$COMPILERDIR" ]; then
	echo "Neutron Clang not found! Downloading to $COMPILERDIR..."
	mkdir -p "$COMPILERDIR" && cd "$COMPILERDIR"
	curl -LO "https://raw.githubusercontent.com/Neutron-Toolchains/antman/main/antman"
	bash ./antman -S
	bash ./antman --patch=glibc
	cd ../..
	if ! [ -d "$COMPILERDIR" ]; then
		echo "Cloning failed! Aborting..."
		exit 1
	fi
fi

cd "$COMPILERDIR" && bash ./antman -U && cd ../..
}

# Function to replace defconfig versioning
setversioning() {
        # For staging branch
            KERNELNAME="${KERNEL}-${KERNELRELEASE}-SUKISU-${BUILD_DATE}"

    # Export our new localversion and zipnames
    export KERNELTYPE KERNELNAME
    export TEMPZIPNAME="${KERNELNAME}-unsigned.zip"
    export ZIPNAME="${KERNELNAME}.zip"
}

# Send to channel
tg_channelcast() {
    "${TELEGRAM}" -c "${CI_CHANNEL}" -H \
    "$(
		for POST in "${@}"; do
			echo "${POST}"
		done
    )"
}

# Make Defconfig
build_kernel() {
    export PATH="$COMPILERDIR/bin:$PATH"
    make -j$(nproc --all) O=out ARCH=arm64 ${DEFCONFIG}
    if [ $? -ne 0 ]
then
    echo -e "\n"
    echo -e "$red [!] BUILD FAILED \033[0m"
    echo -e "\n"
else
    echo -e "\n"
    echo -e "$green==================================\033[0m"
    echo -e "$green= [!] START BUILD ${DEFCONFIG}\033[0m"
    echo -e "$green==================================\033[0m"
    echo -e "\n"
fi

# Speed up build process
MAKE="./makeparallel"

# Build Start Here

   make -j$(nproc --all) \
    O=out \
    ARCH=arm64 \
    LLVM=1 \
    LLVM_IAS=1 \
    AR=llvm-ar \
    NM=llvm-nm \
    LD=ld.lld \
    OBJCOPY=llvm-objcopy \
    OBJDUMP=llvm-objdump \
    STRIP=llvm-strip \
    CC=clang \
    DTC_EXT=dtc \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CROSS_COMPILE_ARM32=arm-linux-gnueabi- 2>&1 | tee log.txt

}

# Ship the compiled kernel
shipkernel() {
    cp "${OUTDIR}"/arch/arm64/boot/Image.gz-dtb "${ANYKERNEL}"/

    cd "${ANYKERNEL}" || exit
    zip -r9 "${TEMPZIPNAME}" *

    curl -sLo zipsigner-3.0.jar https://raw.githubusercontent.com/baalajimaestro/AnyKernel2/master/zipsigner-3.0.jar
    java -jar zipsigner-3.0.jar ${TEMPZIPNAME} ${ZIPNAME}

    "${TELEGRAM}" -f "$ZIPNAME" -c "${CI_CHANNEL}"

    cd ..
}

# Ship China firmware builds
clearout() {
    rm -rf out
    mkdir -p out
}

#Patch zip name
setver2() {
    KERNELNAME="${KERNEL}-${KERNELRELEASE}-SUKISU-${BUILD_DATE}"
    export KERNELTYPE KERNELNAME
    export TEMPZIPNAME="${KERNELNAME}-unsigned.zip"
    export ZIPNAME="${KERNELNAME}.zip"
}

# Fix for CI builds running out of memory
fixcilto() {
    sed -i 's/CONFIG_LTO=y/# CONFIG_LTO is not set/g' arch/arm64/configs/${DEFCONFIG}
    sed -i 's/CONFIG_LD_DEAD_CODE_DATA_ELIMINATION=y/# CONFIG_LD_DEAD_CODE_DATA_ELIMINATION is not set/g' arch/arm64/configs/${DEFCONFIG}
}

## Start the kernel buildflow ##
setversioning
fixcilto
tg_channelcast "<b>CI Build Triggered</b>" \
        "Compiler: <code>${COMPILER_STRING}</code>" \
        "Model: ${MODEL}" \
	"Device: ${DEVICE}" \
	"Kernel: <code>${KERNEL}, ${KERNELRELEASE}</code>" \
	"Linux Version: <code>$(make kernelversion)</code>" \
	"Clang: <code>${CLANG}</code>" \
	"Branch: <code>${PARSE_BRANCH}</code>" \
	"Commit point: <code>${COMMIT_POINT}</code>" \
	"Clocked at: <code>$(date +%Y%m%d-%H%M)</code>"
START=$(date +"%s")
build_kernel || exit 1
shipkernel
setver2
build_kernel || exit 1
shipkernel
END=$(date +"%s")
DIFF=$(( END - START ))
tg_channelcast "Build for ${DEVICE} with ${COMPILER_STRING} <b>succeed</b> took $((DIFF / 60)) minute(s) and $((DIFF % 60)) second(s)!"
