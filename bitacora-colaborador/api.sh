#!/usr/bin/env bash
#
# El cliente de la bitácora interna: curl con la llave puesta, una llave POR PROYECTO.
#
# Es un envoltorio fino sobre la API de bitacora.dev-fran.com y nada más — ninguna regla
# del dominio vive acá. El número de una decisión, la fecha de una entrada y el reloj de
# la línea los pone el servidor; si algo de eso se calculara de este lado, habría dos
# implementaciones que tarde o temprano dirían cosas distintas.
#
# El proyecto se resuelve solo: del flag `-p <slug>` si viene, o de dónde estás parado
# bajo ~/ProyectosDev-Local (<workspace>/<proyecto>/… → <proyecto>; una subcarpeta del
# semillero webchicas cuenta por su cliente). El token de ese proyecto sale de
# ~/.config/bitacora/config.local, y el servidor scopea todo al tenant del token: acá
# no viaja ningún parámetro de proyecto.
#
# Se invoca por su shim estable ~/.local/bin/bitacora-api — el hook de sesión del
# plugin lo mantiene apuntando a la versión instalada.
#
# Los cuerpos JSON entran por stdin, que es como se escribe un texto largo sin pelearse
# con las comillas:
#
#   bitacora-api entrada cuenta <<'JSON'
#   {"tipo":"hallazgo","titulo":"…","cuerpo":"…"}
#   JSON
#
set -euo pipefail

# La config vive fuera del plugin: el directorio instalado se pisa entero en cada
# actualización, y las llaves jamás viajan por git. El path viejo se sigue leyendo
# mientras una instalación no haya mudado todavía su config.local.
CONFIG_DIR="$HOME/.config/bitacora"
CONFIG="$CONFIG_DIR/config.local"
[ -f "$CONFIG" ] || CONFIG="$HOME/.claude/skills/bitacora/config.local"
PENDIENTES="$CONFIG_DIR/pendientes.jsonl"

# --- el proyecto y su llave ---------------------------------------------------

# config.local: una línea por proyecto `<slug>=<token>`, más opcional `url=<base>`.
# No se sourcea: un slug con guión no es un nombre de variable de bash.
valor_de() {
  [ -f "$CONFIG" ] || return 1
  grep -E "^$1=" "$CONFIG" | head -1 | cut -d= -f2-
}

proyecto_del_cwd() {
  local base="$HOME/ProyectosDev-Local" resto
  case "$PWD" in
  "$base"/dev-fran/webchicas/*)
    resto="${PWD#"$base"/dev-fran/webchicas/}"
    printf '%s\n' "${resto%%/*}"
    ;;
  "$base"/*)
    resto="${PWD#"$base"/}"
    printf '%s\n' "${resto%%/*}"
    ;;
  *) return 1 ;;
  esac
}

# --- el alta: canjear el código de la invitación por la llave -----------------
#
# Corre antes de resolver proyecto y llave: quien se da de alta todavía no tiene
# ninguna. El código viene del email de invitación, vale una semana y un solo uso;
# el canje lo cambia por la llave y la guarda en config.local — la llave nunca viajó
# por email.
if [ "${1:-}" = "alta" ]; then
  CODIGO="${2:?Falta el código: bitacora-api alta <código>}"
  BASE="${BITACORA_URL:-$(valor_de url || true)}"
  BASE="${BASE:-https://bitacora.dev-fran.com}"
  RESPUESTA="$(curl -fsS --max-time 20 -H "Content-Type: application/json" \
    -d "$(jq -cn --arg c "$CODIGO" '{codigo:$c}')" "$BASE/api/alta")" || {
    echo "El canje falló: código vencido, ya usado o inexistente. Pedí que te reenvíen la invitación." >&2
    exit 1
  }
  PROYECTO_ALTA="$(printf '%s' "$RESPUESTA" | jq -r .proyecto)"
  TOKEN_ALTA="$(printf '%s' "$RESPUESTA" | jq -r .token)"
  TITULAR_ALTA="$(printf '%s' "$RESPUESTA" | jq -r .titular)"
  mkdir -p "$CONFIG_DIR"
  DESTINO="$CONFIG_DIR/config.local"
  touch "$DESTINO"
  chmod 600 "$DESTINO"
  if grep -qE "^$PROYECTO_ALTA=" "$DESTINO"; then
    grep -vE "^$PROYECTO_ALTA=" "$DESTINO" >"$DESTINO.tmp"
    mv "$DESTINO.tmp" "$DESTINO"
    chmod 600 "$DESTINO"
  fi
  printf '%s=%s\n' "$PROYECTO_ALTA" "$TOKEN_ALTA" >>"$DESTINO"
  echo "Listo: la llave de «${PROYECTO_ALTA}» quedó guardada en $DESTINO."
  echo "Firmás como «${TITULAR_ALTA}». Probala:  bitacora-api -p $PROYECTO_ALTA tablero"
  exit 0
fi

PROYECTO=""
if [ "${1:-}" = "-p" ]; then
  PROYECTO="${2:?Falta el slug después de -p}"
  shift 2
else
  PROYECTO="$(proyecto_del_cwd || true)"
  # Una carpeta puede no llamarse como su tenant (mi-carpeta → mi-tenant):
  # config.local lo declara con `alias.<carpeta>=<tenant>`.
  if [ -n "$PROYECTO" ]; then
    ALIAS="$(valor_de "alias.$PROYECTO" || true)"
    [ -n "$ALIAS" ] && PROYECTO="$ALIAS"
  fi
fi

if [ -z "$PROYECTO" ]; then
  echo "No sé de qué proyecto es esto: parate en el proyecto o pasá -p <slug>." >&2
  exit 1
fi

# El diagnóstico no necesita llave: dice qué proyecto resolvió y termina.
if [ "${1:-}" = "proyecto" ]; then
  printf '%s\n' "$PROYECTO"
  exit 0
fi

TOKEN="$(valor_de "$PROYECTO" || true)"
if [ -z "$TOKEN" ]; then
  echo "No hay token para «${PROYECTO}». Se declara en $CONFIG:" >&2
  echo "  $PROYECTO=…   (el token de su tenant en la app)" >&2
  exit 1
fi

BASE="${BITACORA_URL:-$(valor_de url || true)}"
BASE="${BASE:-https://bitacora.dev-fran.com}"

# --- la renovación: pedir el código nuevo con la llave actual como prueba ------
#
# Funciona también con la llave VENCIDA — va por su propia puerta, sin Bearer.
# El código llega al email registrado del titular; `bitacora-api alta <código>`
# lo canjea y guarda la llave rotada.
if [ "${1:-}" = "renovar" ]; then
  RESPUESTA="$(curl -fsS --max-time 20 -H "Content-Type: application/json" \
    -d "$(jq -cn --arg t "$TOKEN" '{token:$t}')" "$BASE/api/renovar")" || {
    echo "El pedido falló: la llave fue revocada, o hubo demasiados intentos seguidos." >&2
    exit 1
  }
  EMAIL_RENOVACION="$(printf '%s' "$RESPUESTA" | jq -r .email)"
  echo "Listo: te mandamos el código a $EMAIL_RENOVACION."
  echo "Abrí el email y corré:  bitacora-api alta <código>"
  exit 0
fi

# --- abrir: el tablero en el navegador, sin fricción de login ------------------
#
# La llave pide un enlace de entrada fresco de un solo uso y lo abre. En la URL viaja
# ese código efímero, jamás la llave; al abrirse queda la cookie de siempre.
if [ "${1:-}" = "abrir" ]; then
  RESPUESTA="$(curl -fsS --max-time 20 -X POST -H "Authorization: Bearer $TOKEN" \
    "$BASE/api/abrir")" || {
    echo "No se pudo pedir el enlace de entrada. ¿La llave sigue viva? Probá: bitacora-api renovar" >&2
    exit 1
  }
  URL_ABRIR="$(printf '%s' "$RESPUESTA" | jq -r .url)"
  if command -v open >/dev/null 2>&1; then
    open "$URL_ABRIR"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$URL_ABRIR"
  else
    echo "Abrí esto en tu navegador (vale unos minutos, un solo uso):"
    echo "$URL_ABRIR"
    exit 0
  fi
  echo "El tablero de «${PROYECTO}» se está abriendo en tu navegador."
  exit 0
fi

# --- el transporte ------------------------------------------------------------

leer() {
  curl -fsS --max-time 20 -H "Authorization: Bearer $TOKEN" "$BASE$1"
}

# Lo que viaja en la URL: un slug con espacios o un texto de búsqueda.
uri() { jq -rn --arg v "$1" '$v|@uri'; }

# Sube un archivo. No pasa por la cola: un binario no entra en una línea de JSONL, y
# reintentar una subida a ciegas es peor que volver a escribir el comando.
subir() {
  local archivo="$1"
  shift
  local campos=()
  for par in "$@"; do campos+=(-F "$par"); done
  curl -fsS --max-time 120 -H "Authorization: Bearer $TOKEN" \
    -F "archivo=@$archivo" "${campos[@]}" "$BASE/api/adjuntos"
}

# Manda un pedido y devuelve el cuerpo y el código, separados por un salto.
#
# `%{http_code}` vale 000 cuando no hubo respuesta, y esa es toda la diferencia que
# importa: sin respuesta el pedido espera, con respuesta ya está contestado.
pedir() {
  curl -sS --max-time 20 -X "$1" \
    -H "Authorization: Bearer $2" \
    -H "Content-Type: application/json" \
    -d "$4" -w $'\n%{http_code}' "$BASE$3" 2>/dev/null || printf '\n000'
}

# Escribe. Si no hubo red, guarda el pedido — CON su proyecto — para el próximo intento.
#
# Perder un hallazgo por un rato sin internet sería perder exactamente lo que la bitácora
# existe para no perder — pero un pedido que el SERVIDOR rechazó no espera nada: ya fue
# contestado, y reintentarlo lo repetiría en cada escritura sin que nunca entre.
escribir() {
  local metodo="$1" ruta="$2" cuerpo respuesta codigo salida
  cuerpo="$(cat)"

  respuesta="$(pedir "$metodo" "$TOKEN" "$ruta" "$cuerpo")"
  codigo="${respuesta##*$'\n'}"
  salida="${respuesta%$'\n'*}"

  case "$codigo" in
  2*)
    printf '%s\n' "$salida"
    return 0
    ;;
  000)
    mkdir -p "$CONFIG_DIR"
    printf '%s\n' "$(jq -cn --arg p "$PROYECTO" --arg m "$metodo" --arg r "$ruta" \
      --argjson c "$cuerpo" '{proyecto:$p, metodo:$m, ruta:$r, cuerpo:$c}')" >>"$PENDIENTES"
    echo "Sin respuesta: queda en la cola ($PENDIENTES). Se sube en la próxima escritura." >&2
    return 1
    ;;
  *)
    echo "El servidor dijo que no ($codigo): $salida" >&2
    return 1
    ;;
  esac
}

# Sube lo que quedó en la cola, cada pedido con la llave de SU proyecto.
#
# Lo que entra se descuenta; lo que sigue sin respuesta espera otra vuelta; lo que el
# servidor rechaza se descarta diciéndolo, porque un pedido rechazado no mejora con el
# tiempo y quedarse en la cola lo volvería a mandar en cada escritura.
vaciar_cola() {
  [ -s "$PENDIENTES" ] || return 0
  local resto="$PENDIENTES.resto"
  : >"$resto"

  while IFS= read -r fila; do
    local proyecto metodo ruta cuerpo llave respuesta codigo
    proyecto="$(jq -r '.proyecto // empty' <<<"$fila")"
    metodo="$(jq -r '.metodo' <<<"$fila")"
    ruta="$(jq -r '.ruta' <<<"$fila")"
    cuerpo="$(jq -c '.cuerpo' <<<"$fila")"

    llave="$(valor_de "${proyecto:-$PROYECTO}" || true)"
    if [ -z "$llave" ]; then
      echo "Descartado de la cola: no hay token para «${proyecto}» ($metodo $ruta)" >&2
      continue
    fi

    respuesta="$(pedir "$metodo" "$llave" "$ruta" "$cuerpo")"
    codigo="${respuesta##*$'\n'}"

    case "$codigo" in
    2*) echo "Subido de la cola: [$proyecto] $metodo $ruta" >&2 ;;
    000) printf '%s\n' "$fila" >>"$resto" ;;
    *) echo "Descartado de la cola ($codigo): $metodo $ruta — ${respuesta%$'\n'*}" >&2 ;;
    esac
  done <"$PENDIENTES"

  mv "$resto" "$PENDIENTES"
  [ -s "$PENDIENTES" ] || rm -f "$PENDIENTES"
}

comando="${1:-}"
shift || true

# Los argumentos que un comando necesita.
#
# Faltando uno se dice cuál y cómo se escribe: `set -u` cortaba con «$3: unbound
# variable», que nombra una variable interna que quien tipeó el comando nunca vio.
exige() {
  local cuantos="$1" uso="$2"
  shift 2
  if [ "$#" -lt "$cuantos" ]; then
    echo "Faltan argumentos — uso: bitacora-api [-p <proyecto>] $uso" >&2
    exit 1
  fi
}

case "$comando" in
tablero) leer "/api/tablero" ;;
# El taller dice HILO y la API dice `lineas`: los dos nombres alcanzan lo mismo, para que
# la palabra que se lee y la que se tipea sean la misma.
hilos | lineas) leer "/api/lineas" ;;
hilo | linea)
  exige 1 "hilo <slug|alias>" "$@"
  leer "/api/lineas/$1"
  ;;
buscar)
  exige 1 "buscar <texto>" "$@"
  leer "/api/buscar?q=$(uri "$1")"
  ;;
# La tríada del proyecto en una llamada: el lenguaje, el stack y los recorridos.
# Es la primera lectura al llegar a un proyecto que no se viene trabajando.
contexto) leer "/api/contexto" ;;
glosario) leer "/api/glosario" ;;
termino)
  exige 1 "termino <palabra|alias>" "$@"
  leer "/api/glosario/$(uri "$1")"
  ;;
flujos) leer "/api/flujos" ;;
flujo)
  exige 1 "flujo <slug>" "$@"
  leer "/api/flujos/$1"
  ;;
stack) leer "/api/stack${1:+?flujos=1}" ;;
pieza)
  exige 1 "pieza <slug|alias>" "$@"
  leer "/api/stack/$(uri "$1")"
  ;;
# Lo que falta traducir: lo que no tiene la capa y lo que la tiene vieja.
por-traducir) leer "/api/traducir?idioma=${1:-en}" ;;
# Las áreas: los mundos del proyecto, con cuántos hilos vive cada uno.
#
# Con un slug detrás contesta por ESA área, sea `areas` o `area`: quien tipeó el plural
# con un slug quiso una sola, y devolverle la lista entera le daba otra cosa sin avisar.
areas | area)
  if [ "$#" -ge 1 ]; then
    leer "/api/areas/$(uri "$1")"
  else
    leer "/api/areas"
  fi
  ;;
secciones) leer "/api/secciones" ;;
reviews) leer "/api/reviews" ;;
horas) leer "/api/trabajo" ;;
adjuntos) leer "/api/adjuntos${1:+?linea=$(uri "${1:-}")}" ;;
documento)
  exige 3 "documento <linea|seccion|flujo> <contenedor> <slug>" "$@"
  leer "/api/documentos?$1=$(uri "$2")&slug=$(uri "$3")"
  ;;
entrada)
  exige 1 "entrada <slug>   < JSON" "$@"
  vaciar_cola
  escribir POST "/api/lineas/$1/entradas"
  ;;
decision)
  exige 1 "decision <slug>   < JSON" "$@"
  vaciar_cola
  escribir POST "/api/lineas/$1/decisiones"
  ;;
cerrar)
  exige 1 "cerrar <id>   < JSON" "$@"
  vaciar_cola
  escribir PATCH "/api/decisiones/$1"
  ;;
# Los entregables que cuelgan de un punto. Reemplaza la lista entera, como `alias`.
entregables)
  exige 1 "entregables <id-de-punto>   < {\"entregables\":[{\"slug\":\"…\",\"estado\":\"preparacion\"}]}" "$@"
  vaciar_cola
  escribir PATCH "/api/decisiones/$1"
  ;;
superar)
  exige 2 "superar <linea> <id-de-entrada>   < {\"superadaPor\":\"…\"}" "$@"
  vaciar_cola
  escribir PATCH "/api/lineas/$1/entradas/$2"
  ;;
editar-hilo | editar-linea)
  exige 1 "editar-hilo <slug>   < {\"estado\":\"resuelta\"} · {\"area\":\"infra\"}" "$@"
  vaciar_cola
  escribir PATCH "/api/lineas/$1"
  ;;
fusionar)
  exige 1 "fusionar <slug-que-desaparece>   < {\"en\":\"el-que-queda\"}" "$@"
  vaciar_cola
  escribir POST "/api/lineas/$1/fusionar"
  ;;
# abrir-flujo  ← {"nombre":"…","queEs":"…","categoria":"runtime|editorial|ciclo-de-vida|migracion"}
abrir-flujo)
  vaciar_cola
  escribir POST "/api/flujos"
  ;;
editar-flujo)
  exige 1 "editar-flujo <slug>   < {\"estado\":\"construido\"} · {\"sumarStack\":[\"algolia\"]} · {\"sumarGlosario\":[\"route\"]}" "$@"
  vaciar_cola
  escribir PATCH "/api/flujos/$1"
  ;;
# anotar-pieza  ← {"nombre":"…","responsabilidad":"…","donde":"…","comoSeEntra":"…"}
anotar-pieza)
  vaciar_cola
  escribir POST "/api/stack"
  ;;
editar-pieza)
  exige 1 "editar-pieza <slug>   < {\"responsabilidad\":\"…\"}" "$@"
  vaciar_cola
  escribir PATCH "/api/stack/$1"
  ;;
# traducir  ← {"lineaSlug|seccionSlug|flujoSlug":"…","slug":"…","idioma":"en","cuerpo":"…","hash":"…"}
traducir)
  vaciar_cola
  escribir PUT "/api/traducir"
  ;;
# abrir-area  ← {"nombre":"…"}   ·  nace vacía y se llena mudando hilos
abrir-area)
  vaciar_cola
  escribir POST "/api/areas"
  ;;
# El renombre toca un registro y ningún hilo: el slug es la dirección, el nombre lo que se lee.
editar-area)
  exige 1 "editar-area <slug>   < {\"nombre\":\"…\"} · {\"orden\":2}" "$@"
  vaciar_cola
  escribir PATCH "/api/areas/$1"
  ;;
seccion)
  vaciar_cola
  escribir POST "/api/secciones"
  ;;
editar-seccion)
  exige 1 "editar-seccion <slug>   < JSON" "$@"
  vaciar_cola
  escribir PATCH "/api/secciones/$1"
  ;;
definir)
  # definir  ← {"termino":"…","definicion":"…"} o una lista de esos
  vaciar_cola
  escribir PUT "/api/glosario"
  ;;
review)
  # review  ← {"titulo":"<título del PR>","pr":"…","cuerpo":"…"}
  vaciar_cola
  escribir POST "/api/reviews"
  ;;
rato)
  # rato  ← {"tarea":"…","reloj":"1:30"}
  vaciar_cola
  escribir POST "/api/trabajo"
  ;;
mover-rato)
  exige 1 "mover-rato <id>   < {\"estado\":\"…\"}" "$@"
  vaciar_cola
  escribir PATCH "/api/trabajo/$1"
  ;;
mudar-documento)
  exige 3 "mudar-documento <linea|seccion|flujo> <contenedor> <slug>   < {\"lineaSlug\":\"otra\"}" "$@"
  vaciar_cola
  escribir PATCH "/api/documentos?$1=$(uri "$2")&slug=$(uri "$3")"
  ;;
adjuntar)
  exige 2 "adjuntar <archivo> linea=<slug> [queEs=\"…\"]" "$@"
  subir "$@"
  ;;
borrar)
  exige 1 "borrar <ruta-de-la-api>   (el servidor se niega si todavía cuelga algo)" "$@"
  curl -fsS --max-time 20 -X DELETE -H "Authorization: Bearer $TOKEN" "$BASE$1"
  ;;
abrir-hilo | abrir-linea)
  vaciar_cola
  escribir POST "/api/lineas"
  ;;
guardar-documento)
  vaciar_cola
  escribir PUT "/api/documentos"
  ;;
pendientes) vaciar_cola ;;
*)
  cat >&2 <<'USO'
Uso: bitacora-api [-p <proyecto>] <comando>
  El proyecto se deduce de dónde estás parado bajo ~/ProyectosDev-Local
  (webchicas/<cliente> cuenta como <cliente>); -p lo fija a mano.
  bitacora-api proyecto                      (dice cuál resolvió)

El sistema del proyecto — la tríada. Primera lectura al llegar:
  bitacora-api contexto                     (el lenguaje + el stack + los recorridos, de una)
  bitacora-api flujos                       · bitacora-api flujo <slug>
  bitacora-api stack [flujos]               · bitacora-api pieza <slug|alias>
  bitacora-api glosario                     · bitacora-api termino <palabra>

El trabajo (en el taller un tema se llama HILO; la API lo guarda como `lineas`):
  bitacora-api abrir                        (el tablero en tu navegador, sin login: enlace fresco de un solo uso)
  bitacora-api tablero
  bitacora-api hilos                        (= lineas)
  bitacora-api hilo <slug|alias>            (= linea)
  bitacora-api areas                        (los mundos del proyecto, con sus hilos)
  bitacora-api area <slug>                  (un área con los hilos que viven ahí; `areas <slug>` es lo mismo)
  bitacora-api buscar <texto>
  bitacora-api documento <linea|seccion|flujo> <contenedor> <slug>
  bitacora-api secciones · bitacora-api horas · bitacora-api adjuntos [linea] · bitacora-api reviews
  bitacora-api por-traducir [idioma]        (lo que falta y lo que quedó viejo)

Escritura (el cuerpo JSON entra por stdin):
  bitacora-api entrada <slug>               {"tipo":"hallazgo","titulo":"…","cuerpo":"…"}
  bitacora-api superar <slug> <id-entrada>  {"superadaPor":"…"}
  bitacora-api decision <slug>              {"titulo":"…","cierraEn":"…","cuerpo":"…","flujos":["…"]}
  bitacora-api cerrar <id>                  {"estado":"resuelta","nota":"qué se decidió"}
  bitacora-api abrir-hilo                   {"slug":"…","nombre":"…","area":"…","decide":"…","brief":"…"}
  bitacora-api editar-hilo <slug>           {"estado":"resuelta"} · {"brief":"…"} · {"area":"infra"}
  bitacora-api abrir-area                   {"nombre":"El contrato"}   (nace vacía; se llena mudando hilos)
  bitacora-api editar-area <slug>           {"nombre":"…"} (renombra) · {"orden":2} (su lugar en el menú)
  bitacora-api fusionar <slug>              {"en":"la-que-queda"}
  bitacora-api abrir-flujo                  {"nombre":"…","queEs":"…","categoria":"runtime"}
  bitacora-api editar-flujo <slug>          {"estado":"construido"} · {"sumarStack":[…]} · {"sumarGlosario":[…]}
  bitacora-api anotar-pieza                 {"nombre":"…","responsabilidad":"…","donde":"…"}
  bitacora-api editar-pieza <slug>          {"responsabilidad":"…"} · {"sumarAlias":["el CMS"]}
  bitacora-api seccion                      {"tipo":"archivo","nombre":"…","nota":"…"}
  bitacora-api editar-seccion <slug>        {"resumen":"…"} · {"tipo":"fuente"}
  bitacora-api definir                      {"termino":"…","definicion":"…"}  (o una lista)
  bitacora-api review                       {"titulo":"<título del PR>","pr":"…","cuerpo":"…"}
  bitacora-api guardar-documento            el documento entero
  bitacora-api traducir                     {"linea":"…","slug":"…","idioma":"en","cuerpo":"…","hash":"…"}
                                            (traduce desde el `escritoEn` del documento)
                                            (acepta linea|seccion|flujo, los nombres que da la cola)
  bitacora-api mudar-documento <linea|seccion|flujo> <contenedor> <slug>   {"lineaSlug":"otra"}

Archivos y bajas:
  bitacora-api adjuntar <archivo> linea=<slug> [queEs="…"]
  bitacora-api borrar /api/lineas/<slug>     (se niega si todavía cuelga algo)
  bitacora-api borrar /api/areas/<slug>      (se niega si algún hilo vive ahí)
  bitacora-api pendientes                    (sube lo que quedó sin red)

El alta y la renovación de la llave:
  bitacora-api alta <código>                 (canjea el código del email por la llave y la guarda)
  bitacora-api renovar                       (la llave vence sola: esto manda el código nuevo a tu email)
USO
  exit 1
  ;;
esac
