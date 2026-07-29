#!/bin/sh
#
# hangeul-keymap-setup.sh
# 오른쪽 커맨드(⌘) 등의 키를 F17로 리매핑해서 한/영 전환 키로 쓸 수 있게 해주는 스크립트
#
# 사용법:
#   sudo ./hangeul-keymap-setup.sh install               - 연결된 모든 키보드에 적용
#   sudo ./hangeul-keymap-setup.sh install --device      - 특정 키보드 한 대에만 적용 (목록에서 선택)
#   sudo ./hangeul-keymap-setup.sh list                  - 연결된 HID 장치 목록만 확인
#   sudo ./hangeul-keymap-setup.sh uninstall             - 제거
#
# 어떤 키를 쓸지 고르는 옵션 (install에 함께 붙입니다. 여러 개 동시 지정 가능):
#   --right-cmd     오른쪽 커맨드(⌘) 키   [옵션을 안 주면 이게 기본값]
#   --right-alt     오른쪽 Alt(Option) 키
#   --hangul-key    한/영 전용 키 (HID LANG1)
#   --dst <F13~F19> 리매핑 대상 키       [옵션을 안 주면 F17이 기본값]
#
#   윈도우용 키보드처럼 오른쪽 커맨드가 없는 경우:
#     sudo ./hangeul-keymap-setup.sh install --device --right-alt --hangul-key
#   한글 배열 키보드의 한/영 키는 모델에 따라 LANG1을 보내기도 하고 오른쪽 Alt로
#   인식되기도 해서, 둘 다 걸어두면 어느 쪽이든 동작합니다.
#   F17을 다른 용도(Stream Deck 등)로 이미 쓰고 있다면 --dst로 다른 키를 고르세요.
#
# 설치 후 반드시 해야 할 일:
#   시스템 설정 > 키보드 > 키보드 단축키 > 입력 소스
#   에서 "이전 입력 소스 선택" 단축키를 더블클릭한 뒤 오른쪽 커맨드 키를 눌러
#   F17로 등록해야 실제로 한/영 전환이 동작합니다.
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

# HID Usage 코드
SRC_RIGHT_CMD="0x7000000E7"    # 오른쪽 커맨드 (윈도우 키보드의 오른쪽 Win 키도 같은 값)
SRC_RIGHT_ALT="0x7000000E6"    # 오른쪽 Alt/Option
SRC_HANGUL="0x700000090"       # 한/영 전용 키 (LANG1)

# 리매핑 대상 키 (F13~F19). macOS 단축키 레코더가 인식하면서
# 물리 키보드에 거의 없는 구간이 이 대역뿐이라 여기서 고른다.
# F20은 HID 코드는 있지만 macOS Sequoia의 '이전 입력 소스 선택' 입력 칸이
# 등록을 받아주지 않아(실측 확인) 목록에서 제외했다.
# F21 이상은 macOS에 virtual keycode 자체가 없어 사용할 수 없다.
DST_DEFAULT_NAME="F17"

dst_code_for() {
  # $1 = F13~F19 (대소문자 무관). 유효하지 않으면 빈 문자열 반환
  case "$(echo "$1" | tr 'a-z' 'A-Z')" in
    F13) echo "0x700000068" ;;
    F14) echo "0x700000069" ;;
    F15) echo "0x70000006A" ;;
    F16) echo "0x70000006B" ;;
    F17) echo "0x70000006C" ;;
    F18) echo "0x70000006D" ;;
    F19) echo "0x70000006E" ;;
    *)   echo "" ;;
  esac
}

dst_name_for() {
  # $1 = HID 코드 (0x... 형태). 유효하지 않으면 빈 문자열 반환
  case "$1" in
    0x700000068) echo "F13" ;;
    0x700000069) echo "F14" ;;
    0x70000006A) echo "F15" ;;
    0x70000006B) echo "F16" ;;
    0x70000006C) echo "F17" ;;
    0x70000006D) echo "F18" ;;
    0x70000006E) echo "F19" ;;
    *)           echo "" ;;
  esac
}

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

add_src_key() {
  # $1 = HID 코드, $2 = 사람이 읽을 이름. 같은 키를 두 번 지정하면 무시합니다.
  case " ${SRC_LIST} " in
    *" $1 "*) return 0 ;;
  esac
  SRC_LIST="${SRC_LIST}$1 "
  if [ -z "${SRC_NAMES}" ]; then
    SRC_NAMES="$2"
  else
    SRC_NAMES="${SRC_NAMES}, $2"
  fi
}

build_mapping_json() {
  # $1 = "all" 또는 "device"
  # $2, $3 = device 모드일 때 VendorID, ProductID
  # SRC_LIST 전역 변수에 담긴 키들을 모두 DST_CODE(전역 변수)로 매핑합니다.
  ENTRIES=""
  for SRC in ${SRC_LIST}; do
    ENTRY="{\"HIDKeyboardModifierMappingSrc\":${SRC},\"HIDKeyboardModifierMappingDst\":${DST_CODE}}"
    if [ -z "${ENTRIES}" ]; then
      ENTRIES="${ENTRY}"
    else
      ENTRIES="${ENTRIES},${ENTRY}"
    fi
  done
  BASE_MAPPING="\"UserKeyMapping\":[${ENTRIES}]"

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
  SRC_LIST=""
  SRC_NAMES=""
  DST_NAME="${DST_DEFAULT_NAME}"

  while [ $# -gt 0 ]; do
    case "$1" in
      --device)     SCOPE="device" ;;
      --right-cmd)  add_src_key "${SRC_RIGHT_CMD}" "오른쪽 커맨드(⌘)" ;;
      --right-alt)  add_src_key "${SRC_RIGHT_ALT}" "오른쪽 Alt(Option)" ;;
      --hangul-key) add_src_key "${SRC_HANGUL}" "한/영 키" ;;
      --dst)
        shift
        if [ $# -eq 0 ]; then
          echo "--dst 뒤에 키 이름이 필요합니다 (F13~F19)" >&2
          exit 1
        fi
        DST_NAME="$(echo "$1" | tr 'a-z' 'A-Z')"
        ;;
      *)
        echo "알 수 없는 옵션: $1" >&2
        echo "사용 가능한 옵션: --device, --right-cmd, --right-alt, --hangul-key, --dst" >&2
        exit 1
        ;;
    esac
    shift
  done

  # 아무 키도 지정하지 않으면 오른쪽 커맨드를 기본값으로 사용
  if [ -z "${SRC_LIST}" ]; then
    add_src_key "${SRC_RIGHT_CMD}" "오른쪽 커맨드(⌘)"
  fi

  DST_CODE="$(dst_code_for "${DST_NAME}")"
  if [ -z "${DST_CODE}" ]; then
    echo "알 수 없는 대상 키: ${DST_NAME}" >&2
    echo "사용 가능한 값: F13 F14 F15 F16 F17 F18 F19" >&2
    exit 1
  fi

  if [ "$SCOPE" = "device" ]; then
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
  echo "리매핑할 키: ${SRC_NAMES} -> ${DST_NAME}"
  echo ""

  if [ -f "${PLIST_PATH}" ]; then
    OLD_CODE="$(grep -o '"HIDKeyboardModifierMappingDst":0x[0-9A-Fa-f]*' "${PLIST_PATH}" \
                | head -n 1 | cut -d: -f2)"
    OLD_NAME="$(dst_name_for "${OLD_CODE}")"
    if [ -n "${OLD_NAME}" ] && [ "${OLD_NAME}" != "${DST_NAME}" ]; then
      echo "※ 이전에 ${OLD_NAME}(으)로 설치되어 있었습니다. 대상 키가 ${DST_NAME}(으)로 바뀝니다."
      echo "  시스템 설정의 '이전 입력 소스 선택' 단축키를 아래 [1]번대로 다시 등록해야 합니다."
      echo "  이전 설정을 유지하려면: sudo $0 install --dst ${OLD_NAME}"
      echo ""
    fi
  fi

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
    echo "${SRC_NAMES} 키가 ${DST_NAME}로 동작합니다. 다른 키보드는 영향받지 않습니다."
  else
    echo "설치 완료. 연결된 모든 키보드에서 ${SRC_NAMES} 키가 ${DST_NAME}로 동작합니다."
  fi
  echo ""
  echo "================================================================"
  echo " 이제 시스템 설정에서 아래 순서대로 마무리해주세요"
  echo "================================================================"
  echo ""
  echo "[1] ${DST_NAME}를 한/영 전환 단축키로 등록 (필수)"
  echo "    시스템 설정 > 키보드 > 키보드 단축키... > 입력 소스"
  echo "    '이전 입력 소스 선택' 항목을 더블클릭한 뒤"
  echo "    ${SRC_NAMES} 키를 누르면 ${DST_NAME}로 등록됩니다."
  echo "    (체크박스가 꺼져 있다면 함께 켜주세요)"
  echo "    여러 키를 지정했다면 아무 키나 하나만 눌러 등록하면 됩니다."
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
  echo "[2]번을 끄지 않으면 Caps Lock과 새로 지정한 키 두 곳에서 입력 소스가"
  echo "바뀌면서 현재 상태를 착각하기 쉬우니 함께 정리하는 걸 권합니다."
  echo "================================================================"
}

uninstall_keymap() {
  DST_NAME=""
  if [ -f "${PLIST_PATH}" ]; then
    OLD_CODE="$(grep -o '"HIDKeyboardModifierMappingDst":0x[0-9A-Fa-f]*' "${PLIST_PATH}" \
                | head -n 1 | cut -d: -f2)"
    DST_NAME="$(dst_name_for "${OLD_CODE}")"
  fi
  if [ -z "${DST_NAME}" ]; then
    DST_NAME="F13~F19 중 지정했던 키"
  fi

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
  echo "제거 완료. 리매핑했던 키가 모두 원래대로 동작합니다."
  echo "(그래도 ${DST_NAME}로 인식된다면 재부팅하면 확실히 초기화됩니다)"
  echo ""
  echo "================================================================"
  echo " 시스템 설정 되돌리기"
  echo "================================================================"
  echo "이 스크립트는 키 리매핑만 제거하며, 설치할 때 사람이 직접 바꾼"
  echo "시스템 설정은 그대로 남아 있습니다. 아래 항목을 확인해주세요."
  echo ""
  echo "[1] ${DST_NAME}로 지정했던 한/영 전환 단축키 되돌리기"
  echo "    시스템 설정 > 키보드 > 키보드 단축키... > 입력 소스"
  echo "    '이전 입력 소스 선택'을 더블클릭한 뒤 원하는 키 조합"
  echo "    (macOS 기본값은 Control + Space)을 다시 눌러 지정합니다."
  echo "    같은 화면 아래 '기본값 복원'을 눌러도 되지만, 그 화면의 다른"
  echo "    단축키까지 함께 초기화되니 주의하세요."
  echo "    ※ 그대로 두면 ${DST_NAME}는 눌리지 않는 키라 단축키만 비어 있게 됩니다."
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
    shift
    install_keymap "$@"
    ;;
  uninstall)
    require_root "$@"
    uninstall_keymap
    ;;
  list)
    list_devices
    ;;
  *)
    echo "사용법: sudo $0 [install|uninstall|list]" >&2
    echo "" >&2
    echo "install 옵션:" >&2
    echo "  --device        특정 키보드 한 대에만 적용 (목록에서 선택)" >&2
    echo "  --right-cmd     오른쪽 커맨드(⌘) 키를 사용 [기본값]" >&2
    echo "  --right-alt     오른쪽 Alt(Option) 키를 사용" >&2
    echo "  --hangul-key    한/영 전용 키(LANG1)를 사용" >&2
    echo "  --dst <F13~F19> 리매핑 대상 키 (기본값: F17)" >&2
    echo "" >&2
    echo "예) 윈도우용 키보드 한 대에만 적용:" >&2
    echo "  sudo $0 install --device --right-alt --hangul-key" >&2
    exit 1
    ;;
esac
