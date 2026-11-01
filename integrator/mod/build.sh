#!/bin/bash
# Сборка мода integrator; успех определяется по коду возврата haxe и наличию integrator.hl.
cd "$(dirname "$0")" || exit 2
OUT=build/integrator/integrator.hl
rm -f "$OUT"
LOG=$(haxe compile.hxml 2>&1)
CODE=$?
echo "$LOG" | grep -v "Warning : This API"
if [ $CODE -ne 0 ] || [ ! -s "$OUT" ]; then
  echo "=== СБОРКА ПРОВАЛЕНА (haxe exit=$CODE) ==="
  exit 1
fi
echo "=== СБОРКА ОК: $(stat -c %s "$OUT") байт ==="
