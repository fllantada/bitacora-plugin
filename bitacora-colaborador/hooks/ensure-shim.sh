#!/usr/bin/env bash
#
# El directorio instalado del plugin cambia con cada versión; los shims de
# ~/.local/bin son los paths estables que ven los consumidores:
#   bitacora-api      → api.sh, el cliente de la bitácora
#   bitacora-consumo  → skills/coding/scripts/consumo.py, los tokens y el costo de la
#                       sesión (solo el plugin del dueño lo trae: el colaborador comparte
#                       este hook y no lo enlaza)
# Corre en SessionStart y es silencioso: su stdout entraría al contexto de la sesión.
set -euo pipefail

[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || exit 0
mkdir -p "$HOME/.local/bin"
ln -sfn "$CLAUDE_PLUGIN_ROOT/api.sh" "$HOME/.local/bin/bitacora-api"
CONSUMO="$CLAUDE_PLUGIN_ROOT/skills/coding/scripts/consumo.py"
if [ -f "$CONSUMO" ]; then
  chmod +x "$CONSUMO" 2>/dev/null || true
  ln -sfn "$CONSUMO" "$HOME/.local/bin/bitacora-consumo"
fi
