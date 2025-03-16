#!/bin/bash

# 从Makefile获取基础信息
PACKAGE_NAME=$(grep 'APPLICATION_NAME =' Makefile | cut -d' ' -f3)
BASE_VERSION=$(grep 'VERSION =' Makefile | cut -d' ' -f3)

# 清理工作区
rm -rf packages "${PACKAGE_NAME}_"*.ipa "${PACKAGE_NAME}_"*.tipa *.deb

# 初始化或递增构建号
BUILD_NUMBER_FILE=".build_number"
if [ -f "$BUILD_NUMBER_FILE" ]; then
    BUILD_NUMBER=$(cat "$BUILD_NUMBER_FILE")
    BUILD_NUMBER=$((BUILD_NUMBER + 1))
else
    BUILD_NUMBER=1
fi
echo "$BUILD_NUMBER" > "$BUILD_NUMBER_FILE"

# 生成版本号
FULL_VERSION="${BASE_VERSION}(${BUILD_NUMBER})"   # 用于IPA/Info.plist
DEB_VERSION="${BASE_VERSION}.${BUILD_NUMBER}"     # 用于.deb包

echo "========================================"
echo "  开始构建 ${PACKAGE_NAME}"
echo "  基础版本：${BASE_VERSION}"
echo "  构建号：${BUILD_NUMBER}"
echo "  构建时间：$(date +'%Y-%m-%d %H:%M:%S')"
echo "========================================"

if make package FINALPACKAGE=1; then
    BINARY_PATH=".theos/_/Applications/${PACKAGE_NAME}.app/${PACKAGE_NAME}"
    
    if [ ! -f "${BINARY_PATH}" ]; then
        echo "错误：未找到二进制文件 ${BINARY_PATH}"
        exit 1
    fi

    # 计算哈希（仅记录用，不用于版本号）
    SHA_HASH=$(shasum -a 1 "${BINARY_PATH}" | awk '{print $1}')
    DIGITS_ONLY=$(echo "${SHA_HASH}" | tr -cd '0-9')
    LAST_SIX_DIGITS=${DIGITS_ONLY: -6}
    FORMATTED_HASH=$(printf "%06d" "${LAST_SIX_DIGITS}")

    echo "----------------------------------------"
    echo "  二进制哈希：${SHA_HASH}"
    echo "  数字部分：${DIGITS_ONLY}"
    echo "  APP版本号：${FULL_VERSION}"
    echo "  DEB版本号：${DEB_VERSION}"
    echo "----------------------------------------"

    # 更新应用元数据（记录哈希）
    INFO_PLIST=".theos/_/Applications/${PACKAGE_NAME}.app/Info.plist"
    if [ -f "$INFO_PLIST" ]; then
        /usr/libexec/PlistBuddy -c "Delete :BuildHash" "$INFO_PLIST" 2>/dev/null
        /usr/libexec/PlistBuddy -c "Add :BuildHash string ${SHA_HASH}" "$INFO_PLIST"
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${FULL_VERSION}" "$INFO_PLIST"
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${FULL_VERSION}" "$INFO_PLIST"
        echo "元数据更新完成 → ${INFO_PLIST}"
    fi

    # 生成IPA文件
    cd .theos/_/Applications
    ln -sf ./ Payload 2>/dev/null
    IPA_FILE="${PACKAGE_NAME}_${FULL_VERSION}.ipa"
    TIPA_FILE="${PACKAGE_NAME}_${FULL_VERSION}.tipa"
    zip -r9q "../${IPA_FILE}" Payload/*.app
    zip -r9q "../${TIPA_FILE}" Payload/*.app
    mv "../${IPA_FILE}" "../../../"
    mv "../${TIPA_FILE}" "../../../"
    cd ../../../

    # 生成.deb包
    DEB_SRC_DIR=".theos/_"
    DEB_OUTPUT_FILE="${PACKAGE_NAME}_${DEB_VERSION}_iphoneos-arm.deb"
    
    if [ ! -f "${DEB_SRC_DIR}/DEBIAN/control" ]; then
        echo "错误：缺少DEBIAN控制文件 → ${DEB_SRC_DIR}/DEBIAN/control"
        exit 3
    fi

    # 更新.deb的control文件版本号
    CONTROL_FILE="${DEB_SRC_DIR}/DEBIAN/control"
    echo "正在更新DEB控制文件 → ${CONTROL_FILE}"
    
    if sed --version 2>/dev/null | grep -q GNU; then
        sed -i "/^Version:/d" "${CONTROL_FILE}"      # Linux
    else
        sed -i '' "/^Version:/d" "${CONTROL_FILE}"   # macOS
    fi
    
    echo "Version: ${DEB_VERSION}" >> "${CONTROL_FILE}"
    echo "已注入DEB版本号 → Version: ${DEB_VERSION}"

    # 打包.deb
    dpkg-deb -Zgzip --root-owner-group -b "${DEB_SRC_DIR}" "${DEB_OUTPUT_FILE}"
    
    # 输出结果
    echo "========================================"
    echo "  生成以下安装包："
    echo "  - IPA: ${IPA_FILE}       （版本号：${FULL_VERSION}）"
    echo "  - TIPA: ${TIPA_FILE}     （版本号：${FULL_VERSION}）"
    echo "  - DEB: ${DEB_OUTPUT_FILE}（版本号：${DEB_VERSION}）"
    echo "========================================"
    
else
    echo "========================================"
    echo "  构建失败！"
    echo "========================================"
    exit 1
fi
