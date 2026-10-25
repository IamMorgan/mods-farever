#!/bin/bash
# Сборка мода farmer. Не полагается на слово "error" в выводе (ошибки типов Haxe его не содержат):
# проверяется код возврата haxe, а старый farmer.hl удаляется до сборки, чтобы устаревший файл не прошёл.
cd "$(dirname "$0")" || exit 2
OUT=build/farmer/farmer.hl
rm -f "$OUT"
LOG=$(haxe compile.hxml 2>&1)
CODE=$?
echo "$LOG" | grep -v "Warning : This API"
if [ $CODE -ne 0 ] || [ ! -s "$OUT" ]; then
  echo "=== СБОРКА ПРОВАЛЕНА (haxe exit=$CODE, farmer.hl есть: $([ -s "$OUT" ] && echo да || echo нет)) ==="
  exit 1
fi
echo "=== СБОРКА ОК: $(date -r "$OUT" '+%H:%M:%S'), $(stat -c %s "$OUT") байт ==="
