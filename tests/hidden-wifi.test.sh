#!/usr/bin/env bash
# Tests for hidden-wifi using a fake nmcli on PATH. No real Wi-Fi needed.
# Run: bash tests/hidden-wifi.test.sh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir "$TMP/bin"

cat > "$TMP/bin/nmcli" <<'MOCK'
#!/usr/bin/env bash
echo "$*" >> "$MOCK_LOG"
case "$*" in
  *"general status"*)
    [[ "${MOCK_NM_DOWN:-}" == 1 ]] && { echo "Could not connect to NetworkManager" >&2; exit 1; }; exit 0 ;;
  *"radio wifi"*)
    echo "${MOCK_RADIO:-enabled}"; exit 0 ;;
  *"device"*)
    [[ "${MOCK_NO_DEVICE:-}" == 1 ]] && echo "eth0:ethernet" || echo "wlan0:wifi"; exit 0 ;;
  *"connection add"*)
    [[ "${MOCK_ADD_FAIL:-}" == 1 ]] && { echo "Error: invalid property" >&2; exit 1; }; exit 0 ;;
  *"connection up"*)
    [[ -n "${MOCK_UP_MSG:-}" ]] && { echo "$MOCK_UP_MSG" >&2; exit 1; }; exit 0 ;;
  *"connection delete"*) exit 0 ;;
  *"connection show"*)
    case "$*" in
      *ACTIVE*) echo yes ;;
      *IP4.ADDRESS*) echo "192.168.1.42/24" ;;
      *) [[ -n "${MOCK_EXISTING:-}" ]] && echo "$MOCK_EXISTING" ;;
    esac; exit 0 ;;
esac
exit 0
MOCK
chmod +x "$TMP/bin/nmcli"

PASS=0; FAILED=0
export MOCK_LOG="$TMP/log" MOCK_NM_DOWN=0 MOCK_RADIO=enabled \
  MOCK_NO_DEVICE=0 MOCK_ADD_FAIL=0 MOCK_UP_MSG= MOCK_EXISTING=
assert() { # description, result (0 = pass)
  if [[ "$2" == 0 ]]; then echo "ok   - $1"; PASS=$((PASS+1));
  else echo "FAIL - $1"; FAILED=$((FAILED+1)); fi
}
run() { # sets RC, OUT, LOG from $INPUT and current MOCK_* env
  : > "$TMP/log"
  MOCK_LOG="$TMP/log" PATH="$TMP/bin:$PATH" \
    bash "$ROOT/hidden-wifi" >"$TMP/out" 2>"$TMP/err" <<<"$INPUT"
  RC=$?; OUT="$(cat "$TMP/out")"; LOG="$(cat "$TMP/log")"
}
reset() { export MOCK_NM_DOWN=0 MOCK_RADIO=enabled MOCK_NO_DEVICE=0 \
  MOCK_ADD_FAIL=0 MOCK_UP_MSG= MOCK_EXISTING=; }

reset; INPUT=$'TestNet\npassword123\n\n'
run; assert "happy path exits 0" "$([ "$RC" == 0 ]; echo $?)"
assert "happy path reports connected" "$(grep -q "Connected to TestNet" <<<"$OUT"; echo $?)"
assert "happy path reports IP" "$(grep -q "192.168.1.42" <<<"$OUT"; echo $?)"
assert "happy path keeps profile (no delete)" "$(grep -q "connection delete" <<<"$LOG"; [ "$?" == 1 ]; echo $?)"

reset; INPUT=$'TestNet\npassword123\nwpa5\nwpa3\n'
run; assert "invalid security is re-prompted, wpa3 used" \
  "$(grep -q "wifi-sec.key-mgmt sae" <<<"$LOG"; echo $?)"

reset; INPUT=$'\npassword123\n\n'
run; assert "empty SSID exits 1" "$([ "$RC" == 1 ]; echo $?)"

reset; INPUT=$'TestNet\nshort\n\n'
run; assert "short password exits 1" "$([ "$RC" == 1 ]; echo $?)"

reset; MOCK_NM_DOWN=1; INPUT=$'TestNet\npassword123\n\n'
run; assert "NetworkManager down exits 1" \
  "$([ "$RC" == 1 ] && grep -q "doesn't appear to be running" <<<"$OUT"; echo $?)"

reset; MOCK_RADIO=disabled; INPUT=$'TestNet\npassword123\n\n'
run; assert "radio off exits 1 with hint" \
  "$([ "$RC" == 1 ] && grep -q "radio wifi on" <<<"$OUT"; echo $?)"

reset; MOCK_NO_DEVICE=1; INPUT=$'TestNet\npassword123\n\n'
run; assert "no device exits 1" "$([ "$RC" == 1 ]; echo $?)"

reset; MOCK_ADD_FAIL=1; INPUT=$'TestNet\npassword123\n\n'
run; assert "add failure exits 2" \
  "$([ "$RC" == 2 ] && grep -q "Could not create profile" <<<"$OUT"; echo $?)"

reset; MOCK_UP_MSG="Error: Connection activation failed: Secrets were required, but no secrets were provided."
INPUT=$'TestNet\npassword123\n\n'
run; assert "wrong password exits 3" \
  "$([ "$RC" == 3 ] && grep -q "wrong password" <<<"$OUT"; echo $?)"
assert "failed profile is cleaned up" "$(grep -q "connection delete" <<<"$LOG"; echo $?)"

reset; MOCK_UP_MSG="Error: No suitable device found for this connection."
INPUT=$'TestNet\npassword123\n\n'
run; assert "not found exits 3 with hint" \
  "$([ "$RC" == 3 ] && grep -q "Network not found" <<<"$OUT"; echo $?)"

reset; MOCK_EXISTING=TestNet; INPUT=$'TestNet\npassword123\n\nn'
run; assert "declining replace exits 0, profile untouched" \
  "$([ "$RC" == 0 ] && grep -q "Aborted" <<<"$OUT" && ! grep -q "connection add" <<<"$LOG"; echo $?)"

echo
echo "$PASS passed, $FAILED failed"
exit "$([ "$FAILED" == 0 ]; echo $?)"
