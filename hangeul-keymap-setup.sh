#!/bin/sh
#
# hangeul-keymap-setup.sh
# 오른쪽 커맨드(⌘) 키를 F18로 리매핑해서 한/영 전환 키로 쓸 수 있게 해주는 스크립트
#
# 사용법:
#   sudo ./hangeul-keymap-setup.sh install              - 연결된 모든 키보드에 적용
#   sudo ./hangeul-keymap-setup.sh install --device      - 특정 키보드 한 대에만 적용 (목록에서 선택)
#   sudo ./hangeul-keymap-setup.sh list                  - 연결된 HID 장치 목록만 확인
#   sudo ./hangeul-keymap-setup.sh uninstall             - 제거
#
# 설치 후 반드시 해야 할 일:
#   시스템 설정 > 키보드 > 키보드 단축키 > 입력 소스
#   에서 "이전 입력 소스 선택" 단축키를 더블클릭한 뒤 오른쪽 커맨드 키를 눌러
#   F18로 등록해야 실제로 한/영 전환이 동작합니다.
#
#   그리고 Caps Lock 한/영 전환을 꺼두는 걸 권장합니다.
#   (전환 키가 두 개면 입력 소스 상태가 꼬이기 쉽습니다)
#   자세한 절차는 install 실행이 끝나면 화면에 안내됩니다.
#
# 이 스크립트가 건드리는 것 / 건드리지 않는 것:
#   건드림     - /Library/LaunchDaemons/local.hangeul-keymap.plist (hidutil 키 리매핑)
#   안 건드림  - 시스템 설정에서 지정하는 단축키, Caps Lock 관련 설정
#   따라서 uninstall 후에는 시스템 설정을 직접 되돌려야 하며,
#   그 절차도 uninstall 실행이 끝나면 화면에 안내됩니다.
#
# 요구 사항:
#   macOS 10.12 (Sierra) 이상. hidutil과 launchctl bootstrap을 사용합니다.
#   Apple Silicon / Intel 모두 동작하며 추가 설치나 커널 확장이 필요 없습니다.
#
# 주의:
#   이 스크립트는 sudo 권한으로 /Library/LaunchDaemons 에 파일을 만듭니다.
#   실행 전에 내용을 직접 읽어보시고, 파이프로 바로 실행(curl | sudo sh)하지
#   마세요. --device 모드에서 입력을 받지 못해 동작하지 않기도 합니다.
#
# License: MIT
# Copyright (c) 2026 <your name>
#

set -e

LABEL="local.hangeul-keymap"
PLIST_PATH="/Library/LaunchDaemons/${LABEL}.plist"

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "관리자 권한이 필요합니다. sudo $0 $* 로 다시 실행해주세요." >&2
    exit 1
  fi
}

list_devices() {
  echo "연결된 HID 장치 목록 (키보드의 VendorID / ProductID를 확인하세요):"
  echo "----------------------------------------------------------------"
  hidutil list
  echo "----------------------------------------------------------------"
  echo "위 목록에서 리매핑을 적용할 키보드의 VendorID, ProductID 값을 확인해주세요."
  echo "예: VendorID 0x004c, ProductID 0x0267 처럼 0x로 시작하는 값입니다."
}

build_mapping_json() {
  # $1 = "all" 또는 "device"
  # $2, $3 = device 모드일 때 VendorID, ProductID
  BASE_MAPPING='"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x7000000E7,"HIDKeyboardModifierMappingDst":0x70000006D}]'

  if [ "$1" = "device" ]; then
    echo "{${BASE_MAPPING},\"HIDMatch\":{\"VendorID\":$2,\"ProductID\":$3}}"
  else
    echo "{${BASE_MAPPING}}"
  fi
}

install_keymap() {
  SCOPE="all"
  VENDOR_ID=""
  PRODUCT_ID=""

  if [ "$1" = "--device" ]; then
    SCOPE="device"
    list_devices
    echo ""
    printf "적용할 키보드의 VendorID (예: 0x004c): "
    read -r VENDOR_ID
    printf "적용할 키보드의 ProductID (예: 0x0267): "
    read -r PRODUCT_ID

    if [ -z "$VENDOR_ID" ] || [ -z "$PRODUCT_ID" ]; then
      echo "VendorID / ProductID를 모두 입력해야 합니다. 설치를 취소합니다." >&2
      exit 1
    fi
  fi

  MAPPING_JSON=$(build_mapping_json "$SCOPE" "$VENDOR_ID" "$PRODUCT_ID")

  echo ""
  echo "1) ${PLIST_PATH} 생성 중..."
  cat <<EOF > "${PLIST_PATH}"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/hidutil</string>
        <string>property</string>
        <string>--set</string>
        <string>${MAPPING_JSON}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF

  echo "2) 권한 설정 중..."
  chown root:wheel "${PLIST_PATH}"
  chmod 644 "${PLIST_PATH}"

  echo "3) launchd에 등록 및 즉시 적용 중..."
  launchctl bootout system "${PLIST_PATH}" 2>/dev/null || true
  launchctl bootstrap system "${PLIST_PATH}"

  echo ""
  if [ "$SCOPE" = "device" ]; then
    echo "설치 완료. VendorID ${VENDOR_ID} / ProductID ${PRODUCT_ID} 키보드에서만"
    echo "오른쪽 커맨드 키가 F18로 동작합니다. 다른 키보드는 영향받지 않습니다."
  else
    echo "설치 완료. 연결된 모든 키보드에서 오른쪽 커맨드 키가 F18로 동작합니다."
  fi
  echo ""
  echo "================================================================"
  echo " 이제 시스템 설정에서 아래 순서대로 마무리해주세요"
  echo "================================================================"
  echo ""
  echo "[1] 오른쪽 커맨드 키를 한/영 전환 키로 등록 (필수)"
  echo "    시스템 설정 > 키보드 > 키보드 단축키... > 입력 소스"
  echo "    '이전 입력 소스 선택' 항목을 더블클릭한 뒤"
  echo "    오른쪽 커맨드 키를 누르면 F18로 등록됩니다."
  echo "    (체크박스가 꺼져 있다면 함께 켜주세요)"
  echo ""
  echo "[2] Caps Lock 한/영 전환 끄기 (권장)"
  echo "    시스템 설정 > 키보드 > 텍스트 입력 > 입력 소스 옆 [편집...]"
  echo "    'Caps Lock 키로 ABC 입력 소스 전환' 을 끕니다."
  echo "    (영문 표기: Use Caps Lock key to switch to and from ABC)"
  echo "    * macOS 12 이하에서는 시스템 환경설정 > 키보드 > 입력 소스 탭에"
  echo "      같은 항목이 있습니다."
  echo ""
  echo "[3] Caps Lock 키를 완전히 죽이기 (선택)"
  echo "    [2]번만 꺼도 한/영 전환은 안 되지만 대문자 고정 기능은 남습니다."
  echo "    아예 쓰지 않으려면"
  echo "    시스템 설정 > 키보드 > 키보드 단축키... > 보조 키"
  echo "    에서 'Caps Lock 키'를 '동작 없음'으로 바꿔주세요."
  echo "    이 설정은 키보드별로 따로 저장되므로, 창 위쪽 '적용 대상'에서"
  echo "    사용 중인 키보드를 각각 선택해 설정해야 합니다."
  echo ""
  echo "[2]번을 끄지 않으면 Caps Lock과 오른쪽 커맨드 두 곳에서 입력 소스가"
  echo "바뀌면서 현재 상태를 착각하기 쉬우니 함께 정리하는 걸 권합니다."
  echo "================================================================"
}

uninstall_keymap() {
  echo "1) launchd에서 제거 중..."
  launchctl bootout system "${PLIST_PATH}" 2>/dev/null || true

  echo "2) plist 파일 삭제 중..."
  rm -f "${PLIST_PATH}"

  # 이전 버전(local.keymap)으로 설치했던 경우도 함께 정리
  LEGACY_PLIST="/Library/LaunchDaemons/local.keymap.plist"
  if [ -f "${LEGACY_PLIST}" ]; then
    echo "   이전 버전 설정(local.keymap)도 발견되어 함께 제거합니다..."
    launchctl bootout system "${LEGACY_PLIST}" 2>/dev/null || true
    rm -f "${LEGACY_PLIST}"
  fi

  echo "3) 현재 세션에 적용된 리매핑 해제 중..."
  hidutil property --set '{"UserKeyMapping":[]}' >/dev/null 2>&1 || true

  echo ""
  echo "제거 완료. 오른쪽 커맨드 키가 원래대로 동작합니다."
  echo "(그래도 F18로 인식된다면 재부팅하면 확실히 초기화됩니다)"
  echo ""
  echo "================================================================"
  echo " 시스템 설정 되돌리기"
  echo "================================================================"
  echo "이 스크립트는 키 리매핑만 제거하며, 설치할 때 사람이 직접 바꾼"
  echo "시스템 설정은 그대로 남아 있습니다. 아래 항목을 확인해주세요."
  echo ""
  echo "[1] F18로 지정했던 한/영 전환 단축키 되돌리기"
  echo "    시스템 설정 > 키보드 > 키보드 단축키... > 입력 소스"
  echo "    '이전 입력 소스 선택'을 더블클릭한 뒤 원하는 키 조합"
  echo "    (macOS 기본값은 Control + Space)을 다시 눌러 지정합니다."
  echo "    같은 화면 아래 '기본값 복원'을 눌러도 되지만, 그 화면의 다른"
  echo "    단축키까지 함께 초기화되니 주의하세요."
  echo "    ※ 그대로 두면 F18은 눌리지 않는 키라 단축키만 비어 있게 됩니다."
  echo ""
  echo "[2] Caps Lock 한/영 전환 다시 켜기"
  echo "    설치할 때 껐다면,"
  echo "    시스템 설정 > 키보드 > 텍스트 입력 > 입력 소스 옆 [편집...]"
  echo "    'Caps Lock 키로 ABC 입력 소스 전환' 을 다시 켭니다."
  echo "    이걸 켜두지 않으면 한/영 전환 방법이 하나도 남지 않을 수 있으니"
  echo "    [1]번과 함께 꼭 확인해주세요."
  echo ""
  echo "[3] Caps Lock 키 동작 되돌리기"
  echo "    '동작 없음'으로 바꿔뒀다면,"
  echo "    시스템 설정 > 키보드 > 키보드 단축키... > 보조 키"
  echo "    에서 'Caps Lock 키'를 다시 'Caps Lock'으로 지정합니다."
  echo "    키보드별 설정이므로 '적용 대상'에서 각 키보드를 확인하세요."
  echo "================================================================"
}

case "$1" in
  install)
    require_root "$@"
    install_keymap "$2"
    ;;
  uninstall)
    require_root "$@"
    uninstall_keymap
    ;;
  list)
    list_devices
    ;;
  *)
    echo "사용법: sudo $0 [install|install --device|uninstall|list]" >&2
    exit 1
    ;;
esac
