#!/usr/bin/env bash
# goal_loop.sh — /goal 라운드를 headless로 반복 실행하는 래퍼.
#
# 동작:
#   1. .claude/next-goal.md 의 내용을 프롬프트로 claude -p (새 세션) 실행
#   2. 세션은 기존 관행대로 마지막에 다음 /goal 프롬프트를 만들고,
#      래퍼가 덧붙인 지시에 따라 그것을 .claude/next-goal.md 에 덮어씀
#   3. 라운드가 게이트 그린 + 커밋까지 마쳐 작업 트리가 깨끗하고,
#      파일이 갱신되고 길이 상한 안이면 다음 라운드로 계속, 아니면 중단
#
# 사용:
#   .claude/next-goal.md 에 첫 goal 프롬프트를 넣고:
#     scripts/goal_loop.sh            # 기본 5라운드
#     MAX_ROUNDS=20 scripts/goal_loop.sh
#   중단: 저장소 루트에  touch STOP_GOAL_LOOP  (현재 라운드 종료 후 멈춤)
#
# 길이 상한: /goal 은 goal condition 을 4000자로 제한하며, 이 상한은
#   래퍼가 덧붙이는 하네스 지시문까지 포함해 적용된다. 그래서 파일 자체의
#   상한(MAX_GOAL_CHARS)은 지시문 길이를 빼서 자동 계산한다. 갭 노트를
#   라운드마다 누적하면 여기에 걸려 다음 라운드가 시작조차 못 한다.
#
# 권한: 무인 실행이므로 기본은 --dangerously-skip-permissions.
#   PERMISSION_FLAG='--permission-mode acceptEdits' 로 바꿀 수 있으나,
#   allowlist에 없는 Bash 호출이 거부되어 라운드가 도중에 좌초할 수 있음.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GOAL_FILE="$REPO_ROOT/.claude/next-goal.md"
LOG_DIR="$REPO_ROOT/.claude/goal-logs"
STOP_FILE="$REPO_ROOT/STOP_GOAL_LOOP"
MAX_ROUNDS="${MAX_ROUNDS:-5}"
PERMISSION_FLAG="${PERMISSION_FLAG:---dangerously-skip-permissions}"
GOAL_LIMIT="${GOAL_LIMIT:-4000}"    # /goal 의 goal condition 상한(문자)
GOAL_MARGIN="${GOAL_MARGIN:-120}"   # 슬래시 커맨드 접두사·개행 등 여유분

[ -f "$GOAL_FILE" ] || { echo "error: $GOAL_FILE 가 없습니다. 첫 goal 프롬프트를 넣어주세요." >&2; exit 1; }
mkdir -p "$LOG_DIR"

goal_chars() { LC_ALL=en_US.UTF-8 wc -m < "$1" | tr -d ' '; }

NOTE_TEMPLATE="$(cat <<'EOF'

---
(자동화 하네스 지시) 무인 루프로 실행 중입니다.
1. 게이트 그린 확인 *과 커밋*까지가 라운드 완료입니다. 커밋해 작업 트리를 깨끗이
   남기세요 — dirty로 끝나면 래퍼가 루프를 중단합니다.
2. 다음 "/goal …" 프롬프트를 .claude/next-goal.md 에 통째로 덮어쓰세요(코드펜스
   없이 "/goal"로 시작하는 본문만, 이 지시문은 빼고).
3. 갭 노트를 누적하지 마세요. 이전 라운드 노트를 복사해 덧붙이는 방식은 금지입니다.
   커밋 이력·ADR·DOGFOOD·가이드에서 읽을 수 있는 내용은 빼고, 아직 문서화되지 않은
   결정·함정·미봉합 축만 지금 시점 기준으로 새로 요약하세요.
4. 파일 전체 __MAXCHARS__자 이내. 넘으면 /goal 이 거부해 다음 라운드가 죽습니다.
5. 다음 goal이 없다고 판단되면 파일을 그대로 두고 이유를 보고에 남기세요.

헤드리스 1회성 실행이라 세션 종료 후에는 알림을 받을 수 없고 백그라운드 작업도 함께
죽습니다. "완료되면 알려드리겠습니다"로 끝내지 말고, 이 세션 안에서 동기적으로 폴링해
결과를 확인·커밋한 뒤 최종 보고를 쓰세요.
EOF
)"

# 지시문 길이를 빼서 파일 자체의 상한을 구한다(자릿수 보존을 위해 자리표시자로 먼저 측정).
NOTE_CHARS="$(printf '%s' "${NOTE_TEMPLATE//__MAXCHARS__/9999}" | LC_ALL=en_US.UTF-8 wc -m | tr -d ' ')"
MAX_GOAL_CHARS=$(( GOAL_LIMIT - NOTE_CHARS - GOAL_MARGIN ))
HARNESS_NOTE="${NOTE_TEMPLATE//__MAXCHARS__/$MAX_GOAL_CHARS}"

echo "== goal 파일 상한: ${MAX_GOAL_CHARS}자 (/goal 상한 ${GOAL_LIMIT} − 지시문 ${NOTE_CHARS} − 여유 ${GOAL_MARGIN})"

check_goal_length() {
  local chars
  chars="$(goal_chars "$GOAL_FILE")"
  if [ "$chars" -gt "$MAX_GOAL_CHARS" ]; then
    echo "== next-goal.md 가 ${chars}자로 상한 ${MAX_GOAL_CHARS}자를 넘었습니다 — 중단합니다."
    echo "   갭 노트가 누적되고 있지 않은지 확인하세요: $GOAL_FILE"
    return 1
  fi
  echo "   goal 길이: ${chars}/${MAX_GOAL_CHARS}자"
  return 0
}

round=1
check_goal_length || exit 1

while [ "$round" -le "$MAX_ROUNDS" ]; do
  if [ -f "$STOP_FILE" ]; then
    echo "== STOP_GOAL_LOOP 발견, 중단합니다."
    exit 0
  fi

  before_hash="$(shasum "$GOAL_FILE" | cut -d' ' -f1)"
  ts="$(date +%Y%m%d-%H%M%S)"
  log="$LOG_DIR/round-$ts.log"

  echo "== round $round/$MAX_ROUNDS 시작 ($(date '+%H:%M:%S')) — 로그: $log"
  prompt="$(cat "$GOAL_FILE")$HARNESS_NOTE"

  set +e
  (cd "$REPO_ROOT" && claude -p $PERMISSION_FLAG "$prompt") >"$log" 2>&1
  status=$?
  set -e

  if [ "$status" -ne 0 ]; then
    echo "== claude 종료 코드 $status — 중단합니다. 로그를 확인하세요: $log"
    exit "$status"
  fi

  # 라운드는 커밋까지가 완료. 남은 변경이 있으면 커밋 없이 끝난 것이므로 중단한다.
  dirty="$(cd "$REPO_ROOT" && git status --porcelain)"
  if [ -n "$dirty" ]; then
    echo "== 라운드가 커밋 없이 끝났습니다(작업 트리 dirty) — 중단합니다."
    echo "$dirty" | sed 's/^/   | /'
    echo "   마지막 보고: $log"
    exit 1
  fi

  after_hash="$(shasum "$GOAL_FILE" | cut -d' ' -f1)"
  if [ "$before_hash" = "$after_hash" ]; then
    echo "== next-goal.md 가 갱신되지 않았습니다 (다음 goal 없음 또는 실패) — 중단합니다."
    echo "   마지막 보고: $log"
    exit 0
  fi

  check_goal_length || { echo "   마지막 보고: $log"; exit 1; }

  echo "== round $round 완료. 다음 goal:"
  head -3 "$GOAL_FILE" | sed 's/^/   | /'
  round=$((round + 1))
done

echo "== MAX_ROUNDS($MAX_ROUNDS) 도달, 중단합니다."
