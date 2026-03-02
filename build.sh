#!/bin/bash

echo -e "==========================="
echo -e "= START COMPILING KERNEL  ="
echo -e "==========================="
bold=$(tput bold)
normal=$(tput sgr0)

TARGET_FAKE_VERSION="5.4.302"
export KBUILD_BUILD_USER="mornye"
export TZ=Asia/Jakarta
export KBUILD_BUILD_HOST="build-host"
export KERNELDIR="$(pwd)"
export KERNELNAME="Karbit"
export SRCDIR="${KERNELDIR}"
export OUTDIR="${KERNELDIR}/out"
export ANYKERNEL="${KERNELDIR}/AnyKernel3"
export DEFCONFIG="stone_defconfig"
export ZIP_DIR="${KERNELDIR}/files"
export IMAGE="${OUTDIR}/arch/arm64/boot/Image"
export VARI="soap"
export PATH="$(pwd)/22/bin:$PATH"

while (( ${#} )); do
    case ${1} in
        "-r"|"--regen") REGEN=true ;;
        "-c"|"--clean") CLEAN=true ;;
    esac
    shift
done

[[ -z ${ZIP} ]] && { echo "${bold}LOADING-_-....${normal}"; }

curl -LSs "https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh" | bash

if [[ "$CLEAN" == true ]]; then
    echo "[*] Cleaning out directory..."
    rm -rf out
fi

if [[ "$REGEN" == true ]]; then
    echo "[*] Regenerating defconfig..."
    mkdir -p out
    make O=out ARCH=arm64 $DEFCONFIG savedefconfig
    cp out/defconfig arch/arm64/configs/$DEFCONFIG
    echo "[*] Defconfig saved to arch/arm64/configs/$DEFCONFIG"
    exit
fi

mkdir -p out
if [[ -n $(git status --porcelain Makefile 2>/dev/null) ]]; then
    echo "[*] Detected Modified Makefile, Force restore it..."
    git restore Makefile 2>/dev/null
else
    echo "[*] Makefile looks clean. Skip do something."
fi

T_VER_MINOR=$(echo $TARGET_FAKE_VERSION | cut -d'.' -f1,2)

if [ "$T_VER_MINOR" = "5.4" ]; then
    echo "[*] Target 5.4 detected. add GKI Localization..."
else
    if [ -n "$TARGET_FAKE_VERSION" ]; then
        echo "[*] Patching Makefile to version: $TARGET_FAKE_VERSION"
        T_VER=$(echo $TARGET_FAKE_VERSION | cut -d'.' -f1)
        T_PATCH=$(echo $TARGET_FAKE_VERSION | cut -d'.' -f2)
        T_SUB=$(echo $TARGET_FAKE_VERSION | cut -d'.' -f3)

        cp Makefile Makefile.bak
        ORI_LINE='^KERNELVERSION = $(VERSION)$(if $(PATCHLEVEL),.$(PATCHLEVEL)$(if $(SUBLEVEL),.$(SUBLEVEL)))$(EXTRAVERSION)'
        NEW_LINE="KERNELVERSION = ${T_VER}\$(if ${T_PATCH},.${T_PATCH}\$(if ${T_SUB},.${T_SUB}))\$(EXTRAVERSION)"
        sed -i "s|$ORI_LINE|$NEW_LINE|" Makefile
    fi
fi

FETCH_MODE="remote"

case "$T_VER_MINOR" in
    "5.4")  FETCH_MODE="local";   CONFIG_PATH="build.config.common" ;;
    "5.10") AOSP_BRANCH="android12-5.10"; CONFIG_PATH="build.config.common" ;;
    "5.15") AOSP_BRANCH="android13-5.15"; CONFIG_PATH="build.config.common" ;;
    "6.1")  AOSP_BRANCH="android14-6.1";  CONFIG_PATH="build.config.common" ;;
    "6.6")  AOSP_BRANCH="android15-6.6";  CONFIG_PATH="build.config.common" ;;
    "6.12") AOSP_BRANCH="android16-6.12"; CONFIG_PATH="build.config.constants" ;;
    "6.18") AOSP_BRANCH="android17-6.18"; CONFIG_PATH="bazel/constants.scl" ;;
    *)
        AOSP_BRANCH=$(git ls-remote --heads https://android.googlesource.com/kernel/common | grep -o "refs/heads/android[0-9]\{2\}-[0-9]\.[0-9]\{1,2\}" | tail -n 1 | cut -d'/' -f3)
        CONFIG_PATH="build.config.common"
        ;;
esac

if [ "$FETCH_MODE" = "local" ]; then
    echo "[*] Mode 5.4: Reading from LOCAL $CONFIG_PATH"
    if [ -f "$CONFIG_PATH" ]; then
        RAW_CONFIG=$(cat "$CONFIG_PATH")
        AOSP_BRANCH=$(echo "$RAW_CONFIG" | grep -E "^BRANCH=" | cut -d= -f2 | tr -d ' "')
    fi
else
    GITHUB_URL="https://raw.githubusercontent.com/aosp-mirror/kernel_common/$AOSP_BRANCH/$CONFIG_PATH"

    echo "[*] Attempting to fetch KMI for branch: $AOSP_BRANCH"
    HTTP_CODE=$(curl -s --connect-timeout 5 -m 10 -o /dev/null -w "%{http_code}" "$GOOGLE_URL")
    RAW_CONFIG=$(curl -s --connect-timeout 5 -m 10 "$GITHUB_URL")
fi

export KMI_GENERATION=$(echo "$RAW_CONFIG" | grep -E "KMI_GENERATION" | tail -n 1 | grep -oE "[0-9]+")
[ -z "$KMI_GENERATION" ] && KMI_GENERATION=1

ANDROID_RELEASE=$(echo "$AOSP_BRANCH" | sed -E 's/^(android[0-9]+)-.*/\1/')

GIT_SHA=$(git rev-parse --verify HEAD 2>/dev/null | cut -c1-12)
[[ -n "$GIT_SHA" ]] && GIT_SUFFIX="-g${GIT_SHA}" || GIT_SUFFIX=""

AB_NUM="-abogki$(date +%s | cut -c4-10)"

FULL_GKI_STRING="-${ANDROID_RELEASE}-${KMI_GENERATION}${GIT_SUFFIX}${AB_NUM}"
echo "[*] Generating .config..."
make O=out ARCH=arm64 $DEFCONFIG

RAW_LOCAL=$(grep "CONFIG_LOCALVERSION=" "arch/arm64/configs/$DEFCONFIG" | cut -d'"' -f2)

if [[ "$RAW_LOCAL" == *"-android"* ]]; then
    echo "[*] Detected GKI String, Cleanup!..."
    CLEAN_LOCAL=$(echo "$RAW_LOCAL" | sed -E 's/^-android[0-9]+(-[0-9]+\.[0-9]+)?-[0-9]+(-g[a-f0-9]+)?(-abogki[0-9]+)?//')
else
    echo "[*] LOCALVERSION is clean, now patch it!."
    CLEAN_LOCAL="$RAW_LOCAL"
fi

CLEAN_LOCAL=$(echo "$CLEAN_LOCAL" | sed 's/^-*//')
[[ -n "$CLEAN_LOCAL" ]] && CLEAN_LOCAL="-${CLEAN_LOCAL}"

FINAL_LOCAL="${FULL_GKI_STRING}${CLEAN_LOCAL}"

sed -i "s/CONFIG_LOCALVERSION=\".*\"/CONFIG_LOCALVERSION=\"${FINAL_LOCAL}\"/" out/.config
echo "[*] New LOCALVERSION: $FULL_GKI_STRING"
echo -e "${bold}[*] Compiling Kernel...${normal}"
make -j$(nproc --all) O=out ARCH=arm64 \
    CC=clang LD=ld.lld HOSTCC=clang HOSTCXX=clang++ \
    READELF=llvm-readelf HOSTAR=llvm-ar AR=llvm-ar AS=llvm-as \
    NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump \
    STRIP=llvm-strip CROSS_COMPILE=aarch64-linux-gnu- \
    CROSS_COMPILE_ARM32=arm-linux-gnueabi- 2>&1 | tee log.txt

echo -e "==========================="
echo -e "   COMPILE KERNEL COMPLETE "
echo -e "==========================="
#TMP DROP IT
#cd out/arch/arm64/boot
#curl -LSs "https://raw.githubusercontent.com/ShirkNeko/SukiSU_patch/refs/heads/main/kpm/patch_linux" -o patch
#chmod 777 patch
#./patch
#mv -f oImage Image
#cd -

echo -e "${bold}[*] Proceeding to AnyKernel3 Zip Creation...${normal}"
if [ -f "$IMAGE" ]; then
    export ZIPNAME="${KERNELNAME}-Kernel-stone-${VARI}-$(date +%Y%m%d-%H%M%S).zip"
    export FINAL_ZIP="${ZIP_DIR}/${ZIPNAME}"
    rm -rf "${ZIP_DIR}"
    mkdir -p "${ZIP_DIR}"
    echo -e "[*] Injecting KERNELNAME ($KERNELNAME) to AnyKernel3..."
    sed -i "s/^kernel\.string=[^ ]*/kernel.string=${KERNELNAME}/" "${ANYKERNEL}/anykernel.sh"
    echo -e "[*] Copying kernel image to AnyKernel3"
    cp -rf -v "${IMAGE}" "${ANYKERNEL}/"
    #cp -rf -v "${DTBO}" "${ANYKERNEL}/"
    cd "${ANYKERNEL}" || exit
    echo -e "[*] Zipping kernel..."
    zip -r9 "${FINAL_ZIP}" * -x .git README.md *placeholder
    echo -e "[*] Erasing trace (Removing Image & Restoring anykernel.sh)..."
    rm -f "Image"
    #rm -f "dtbo.img"
    git restore anykernel.sh 2>/dev/null || git checkout anykernel.sh 2>/dev/null
    echo -e "[*] Uploading to GoFile..."
    curl -LSs "https://raw.githubusercontent.com/lordgaruda/GoFile-Upload/master/upload.sh" | bash -s "${FINAL_ZIP}"
    cd "${KERNELDIR}" || exit
else
    echo -e "[!] Build failed! Image not found at $IMAGE. Skipping ZIP."
    exit 1
fi

if [[ ":v" ]]; then
    exit
fi
