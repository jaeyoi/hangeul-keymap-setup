# hangeul-keymap-setup

macOS에서 **오른쪽 커맨드(⌘) 키를 한/영 전환 키로** 쓰기 위한 셸 스크립트입니다.
오른쪽 커맨드를 F18로 리매핑한 뒤, 그 F18을 입력 소스 전환 단축키로 지정하는 방식입니다.

Karabiner-Elements 같은 별도 앱이나 커널 확장 없이, macOS에 기본 내장된
`hidutil`과 `launchd`만 사용합니다.

## 요구 사항

- macOS 10.12 (Sierra) 이상
- Apple Silicon / Intel 모두 동작
- 관리자(sudo) 권한

## 설치

```sh
chmod +x hangeul-keymap-setup.sh
sudo ./hangeul-keymap-setup.sh install
```

특정 키보드 한 대에만 적용하려면:

```sh
sudo ./hangeul-keymap-setup.sh install --device
```

연결된 HID 장치 목록이 출력되고, 적용할 키보드의 VendorID / ProductID를
입력받습니다. 내장 키보드는 그대로 두고 외장 키보드에만 적용하고 싶을 때 유용합니다.

연결된 장치 목록만 먼저 보려면 `./hangeul-keymap-setup.sh list` (sudo 불필요).

## 설치 후 설정 (필수)

스크립트는 키 리매핑까지만 합니다. **시스템 설정에서 아래를 직접 지정해야**
실제로 한/영 전환이 동작합니다. 설치가 끝나면 같은 내용이 터미널에도 안내됩니다.

1. **F18을 전환 키로 등록** — 시스템 설정 > 키보드 > 키보드 단축키... > 입력 소스에서
   `이전 입력 소스 선택`을 더블클릭하고 오른쪽 커맨드 키를 누릅니다.
2. **Caps Lock 한/영 전환 끄기 (권장)** — 시스템 설정 > 키보드 > 텍스트 입력 >
   입력 소스 `[편집...]`에서 `Caps Lock 키로 ABC 입력 소스 전환`을 끕니다.
   전환 키가 두 개면 현재 입력 상태를 착각하기 쉽습니다.

## 제거

```sh
sudo ./hangeul-keymap-setup.sh uninstall
```

LaunchDaemon을 내리고 plist를 지운 뒤 현재 세션의 리매핑까지 해제합니다.
설치할 때 사람이 직접 바꾼 시스템 설정(F18 단축키, Caps Lock 옵션)은
스크립트가 건드릴 수 없으므로, 제거 후 출력되는 안내를 보고 되돌려주세요.

특히 F18 단축키를 그대로 둔 채 Caps Lock 전환도 꺼져 있으면 **한/영 전환
수단이 하나도 남지 않을 수 있습니다.** 둘 중 하나는 꼭 되살려주세요.

## 동작 방식

`/Library/LaunchDaemons/local.hangeul-keymap.plist`를 만들어, 부팅 시
아래 명령이 실행되도록 등록합니다.

```
hidutil property --set '{"UserKeyMapping":[
  {"HIDKeyboardModifierMappingSrc":0x7000000E7,
   "HIDKeyboardModifierMappingDst":0x70000006D}]}'
```

`0x7000000E7`은 오른쪽 커맨드, `0x70000006D`은 F18의 HID 사용 코드입니다.
이 외에 시스템 파일을 수정하거나 백그라운드에 상주하는 프로세스는 없습니다.

## 알려진 제한

- 블루투스 키보드를 껐다 켜거나 새 키보드를 연결한 뒤 리매핑이 풀렸다는
  보고가 있습니다. 이 경우 재부팅하거나 `install`을 다시 실행하면 됩니다.
- `--device` 모드로 설치한 경우, `uninstall`의 즉시 해제가 적용되지 않을 수
  있습니다. 재부팅하면 확실히 초기화됩니다.
- 오른쪽 커맨드 키 본래 기능은 사용할 수 없게 됩니다. 왼쪽 커맨드 키로
  대체되지 않는 작업이 있는지 먼저 확인해보세요.

## 라이선스

MIT
