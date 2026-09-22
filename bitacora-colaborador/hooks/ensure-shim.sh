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

# La versión de un directorio instalado del plugin, leída de su manifiesto.
version_de() {
  sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1/.claude-plugin/plugin.json" 2>/dev/null | head -1
}

# $1 >= $2, comparando cada segmento como número.
mayor_o_igual() {
  local IFS=. i; local -a a b
  read -ra a <<<"$1"; read -ra b <<<"$2"
  for i in 0 1 2; do
    [ "${a[$i]:-0}" -gt "${b[$i]:-0}" ] && return 0
    [ "${a[$i]:-0}" -lt "${b[$i]:-0}" ] && return 1
  done
  return 0
}

# Los perfiles de esta máquina comparten los shims, y el que arrancaba último los escribía:
# una sesión del perfil que quedó atrás le bajaba de versión los scripts al otro. Manda la
# versión más alta instalada: si el shim ya apunta a un plugin más nuevo que este, se lo
# deja; el enlace roto (la versión vieja podada) se rehace.
actual="$(readlink "$HOME/.local/bin/bitacora-api" 2>/dev/null || true)"
actual="${actual%/api.sh}"
if [ -n "$actual" ] && [ -f "$actual/api.sh" ] && [ -f "$actual/.claude-plugin/plugin.json" ]; then
  nueva="$(version_de "$CLAUDE_PLUGIN_ROOT")"; vieja="$(version_de "$actual")"
  if [ -n "$nueva" ] && [ -n "$vieja" ] && ! mayor_o_igual "$nueva" "$vieja"; then
    exit 0
  fi
fi

ln -sfn "$CLAUDE_PLUGIN_ROOT/api.sh" "$HOME/.local/bin/bitacora-api"
for par in "skills/coding/scripts/consumo.py bitacora-consumo" "skills/thinking/scripts/frentes.sh bitacora-frentes" "skills/harness/medir.sh bitacora-medir"; do
  SCRIPT="$CLAUDE_PLUGIN_ROOT/${par% *}"
  if [ -f "$SCRIPT" ]; then
    chmod +x "$SCRIPT" 2>/dev/null || true
    ln -sfn "$SCRIPT" "$HOME/.local/bin/${par#* }"
  fi
done
