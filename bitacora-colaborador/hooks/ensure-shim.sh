#!/usr/bin/env bash
#
# El directorio instalado del plugin cambia con cada versión; los shims de
# ~/.local/bin son los paths estables que ven los consumidores:
#   bitacora-api      → api.sh, el cliente de la bitácora
#   bitacora-consumo  → skills/coding/scripts/consumo.py, los tokens y el costo de la
#                       sesión
#   bitacora-frentes  → skills/thinking/scripts/frentes.sh, el mapa de los frentes de tmux
#                       y el gesto de escribirles un comando de la CLI
#   bitacora-medir    → skills/harness/medir.sh, lo que carga una sesión y los olores del
#                       harness que un script detecta solo
# Los tres últimos los trae solo el plugin del dueño: el colaborador comparte este hook y
# enlaza lo que encuentra. Corre en SessionStart y es silencioso: su stdout entraría al
# contexto de la sesión.
set -euo pipefail

[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || exit 0
mkdir -p "$HOME/.local/bin"
ln -sfn "$CLAUDE_PLUGIN_ROOT/api.sh" "$HOME/.local/bin/bitacora-api"
for par in "skills/coding/scripts/consumo.py bitacora-consumo" "skills/thinking/scripts/frentes.sh bitacora-frentes" "skills/harness/medir.sh bitacora-medir"; do
  SCRIPT="$CLAUDE_PLUGIN_ROOT/${par% *}"
  if [ -f "$SCRIPT" ]; then
    chmod +x "$SCRIPT" 2>/dev/null || true
    ln -sfn "$SCRIPT" "$HOME/.local/bin/${par#* }"
  fi
done
