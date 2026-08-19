#!/usr/bin/env bash
#
# El directorio instalado del plugin cambia con cada versión; el shim
# ~/.local/bin/bitacora-api es el path estable que ven los consumidores.
# Corre en SessionStart y es silencioso: su stdout entraría al contexto de la sesión.
set -euo pipefail

[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || exit 0
mkdir -p "$HOME/.local/bin"
ln -sfn "$CLAUDE_PLUGIN_ROOT/api.sh" "$HOME/.local/bin/bitacora-api"
