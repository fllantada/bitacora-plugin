#!/usr/bin/env bash
#
# El cliente de la bitácora interna: curl con la llave puesta, una llave POR PROYECTO.
#
# Es un envoltorio fino sobre la API de bitacora.dev-fran.com y nada más — ninguna regla
# del dominio vive acá. El número de una decisión, la fecha de una entrada y el reloj de
# la línea los pone el servidor; si algo de eso se calculara de este lado, habría dos
# implementaciones que tarde o temprano dirían cosas distintas.
#
# El proyecto se resuelve solo: del flag `-p <slug>` si viene, o de dónde estás parado —
# bajo ~/ProyectosDev-Local y bajo cada raíz que config.local declare con `raiz=<path>`
# (<raíz>/<proyecto>/… → <proyecto>, y `alias.<carpeta>=<tenant>` traduce la carpeta que
# no se llama como su tenant). El token de ese proyecto sale de
# ~/.config/bitacora/config.local, y el servidor scopea todo al tenant del token: acá no
# viaja ningún parámetro de proyecto.
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

# Una clave repetible: todas sus líneas, en el orden en que están declaradas.
valores_de() {
  [ -f "$CONFIG" ] || return 0
  grep -E "^$1=" "$CONFIG" | cut -d= -f2-
}

# Dónde vive el trabajo de esta máquina: `raiz=<path>` en config.local, repetible, más
# ~/ProyectosDev-Local, que es la de siempre y no hace falta declarar.
#
# Es información de la máquina y no del cliente: una raíz nueva es una línea en un archivo
# local, en vez de un cambio del cliente distribuido con su despliegue detrás.
raices() {
  valores_de raiz
  printf '%s\n' "$HOME/ProyectosDev-Local"
}

proyecto_del_cwd() {
  local base resto
  while IFS= read -r base; do
    [ -n "$base" ] || continue
    case "$PWD" in
    "$base"/*)
      resto="${PWD#"$base"/}"
      printf '%s\n' "${resto%%/*}"
      return 0
      ;;
    esac
  done < <(raices)
  return 1
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
# El idioma de lectura: vacío sirve la capa del proyecto, y lo que no la tenga cae a su
# original. Quien lee en otra lengua lo dice una vez por comando, junto al proyecto.
IDIOMA=""
while true; do
  case "${1:-}" in
  -p)
    PROYECTO="${2:?Falta el slug después de -p}"
    shift 2
    ;;
  -i)
    IDIOMA="${2:?Falta el código de idioma después de -i}"
    shift 2
    ;;
  *) break ;;
  esac
done

# --- la bandeja: el ciclo del encargo en TODOS los proyectos de esta máquina ----------
#
# Va antes de resolver el proyecto porque no es de ninguno: recorre cada llave de
# config.local y junta los planes entregados (esperan firma), en curso (alguien los
# tiene) y encargados (esperan que alguien los tome). Es el vistazo del día entre todas
# las sesiones, y sale de acá porque la llave de la API es de un tenant y el servidor no
# cruza tenants. Una llave vencida o sin red se dice y se sigue con las demás.
if [ "${1:-}" = "bandeja" ]; then
  BASE="${BITACORA_URL:-$(valor_de url || true)}"
  BASE="${BASE:-https://bitacora.dev-fran.com}"
  [ -f "$CONFIG" ] || { echo "No hay config.local con llaves ($CONFIG)." >&2; exit 1; }
  {
    grep -E '^[a-z0-9-]+=' "$CONFIG" | grep -vE '^(url|raiz)=' | while IFS='=' read -r tenant llave; do
      respuesta="$(curl -fsS --max-time 20 -H "Authorization: Bearer $llave" \
        "$BASE/api/items/planes?abiertos" 2>/dev/null)" || {
        echo "· sin respuesta de «${tenant}» (llave vencida, o sin red)" >&2
        continue
      }
      printf '%s' "$respuesta" | jq -c --arg p "$tenant" \
        '.items[] | select(.estado == "entregado" or .estado == "en-curso" or .estado == "encargado")
         | {proyecto: $p, estado, hilo, area, titulo, id, ficha}'
    done
  } | jq -s 'sort_by(if .estado == "entregado" then 0 elif .estado == "en-curso" then 1 else 2 end)'
  exit 0
fi

if [ -z "$PROYECTO" ]; then
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
  local ruta="$1"
  # El idioma viaja en la query, y algunas rutas ya traen la suya.
  if [ -n "$IDIOMA" ]; then
    case "$ruta" in
    *\?*) ruta="$ruta&idioma=$IDIOMA" ;;
    *) ruta="$ruta?idioma=$IDIOMA" ;;
    esac
  fi
  curl -fsS --max-time 20 -H "Authorization: Bearer $TOKEN" "$BASE$ruta"
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
# La versión instalada contra la última publicada. El mismo push que despliega el
# servidor publica el plugin, así que lo que el servidor contesta ES lo último que
# existe. Es lo primero que corre cada invocación de la skill: una sesión abierta
# sigue con la doctrina con la que arrancó, y sin esto no hay forma de enterarse.
# Sale 0 aunque haya versión nueva — estar atrás no corta el trabajo, lo avisa.
version)
  manifiesto="$(dirname "$0")/.claude-plugin/plugin.json"
  if [ ! -f "$manifiesto" ]; then
    # El shim es un symlink al api.sh instalado: el manifiesto vive al lado del real.
    real="$(readlink -f "$0" 2>/dev/null || true)"
    [ -n "$real" ] && manifiesto="$(dirname "$real")/.claude-plugin/plugin.json"
  fi
  nombre="$(jq -r '.name // "bitacora"' "$manifiesto" 2>/dev/null || echo bitacora)"
  instalada="$(jq -r '.version // empty' "$manifiesto" 2>/dev/null || true)"
  publicada="$(leer "/api/version" 2>/dev/null | jq -r --arg n "$nombre" '.[$n] // empty' || true)"
  if [ "$nombre" = "bitacora-colaborador" ]; then
    actualizar="claude plugin marketplace update bitacora-plugin && claude plugin update bitacora-colaborador@bitacora-plugin"
  else
    actualizar="claude plugin marketplace update bitacora && claude plugin update bitacora@bitacora"
  fi
  if [ -z "$publicada" ]; then
    # El chequeo que no llega al servidor no frena nada: es un aviso, no una puerta.
    echo "No pude consultar la última versión (sin red, o la llave venció). Seguí con el trabajo:"
    echo "las escrituras se encolan solas, y si la llave venció el camino es  bitacora-api renovar"
  elif [ -z "$instalada" ]; then
    echo "No encuentro el manifiesto instalado; la última publicada es $publicada."
  elif [ "$instalada" = "$publicada" ]; then
    echo "Al día: $instalada."
  else
    echo "Hay una versión nueva: $publicada (instalada: $instalada)."
    echo "La doctrina de ESTA sesión es la instalada: puede faltarle lo que la nueva cuenta."
    echo "Para traerla:  $actualizar"
    echo "Rige en la próxima sesión, o ya con /reload-plugins."
  fi
  ;;
tablero) leer "/api/tablero" ;;
# El ciclo del encargo, leído por escritorio: lo que una sesión /coding puede tomar, lo
# que alguien tiene entre manos, y lo que espera la firma de /thinking. Cada plan trae
# su hilo y su área; `item planes <id>` lo trae entero, con el handoff y el reporte.
encargados) leer "/api/items/planes?estado=encargado" ;;
en-curso) leer "/api/items/planes?estado=en-curso" ;;
entregados) leer "/api/items/planes?estado=entregado" ;;
# El taller dice HILO y la API dice `lineas`: los dos nombres alcanzan lo mismo, para que
# la palabra que se lee y la que se tipea sean la misma.
hilos | lineas) leer "/api/lineas" ;;
hilo | linea)
  exige 1 "hilo <slug|alias>" "$@"
  leer "/api/lineas/$(uri "$1")"
  ;;
buscar)
  exige 1 "buscar <texto>" "$@"
  leer "/api/buscar?q=$(uri "$1")"
  ;;
# La tríada del proyecto en una llamada: el dominio, el stack y los flujos.
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
  leer "/api/flujos/$(uri "$1")"
  ;;
stack) leer "/api/stack${1:+?flujos=1}" ;;
# Los accesos directos del proyecto: las direcciones de afuera a las que se entra todos
# los días — el engine, el repo, el tablero de tickets, el diseño.
accesos) leer "/api/enlaces" ;;   # con su `usuario`/`clave`, el que la pide
# Qué falta HACER: del proyecto entero, o de un hilo si se lo nombra. El segundo argumento
# filtra por estado — `acciones "" pendiente` es el frente del proyecto sin lo ya cerrado.
# Los nombres anteriores al modelo de tipos. Siguen resolviendo contra su colección vieja
# —una instalación sin actualizar no se queda sin puerta— y avisan por dónde va el trabajo
# hoy, para que quien los lea no aprenda el vocabulario que se fue.
acciones)
  echo "· El trabajo por hacer es un PLAN: bitacora-api abiertos planes" >&2
  ruta="/api/acciones"
  sep="?"
  if [ -n "${1:-}" ]; then
    ruta="$ruta${sep}linea=$(uri "$1")"
    sep="&"
  fi
  [ -n "${2:-}" ] && ruta="$ruta${sep}estado=$(uri "$2")"
  leer "$ruta"
  ;;
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
# ─────────────────────────────────────────────────────────────────────────────
# LOS TIPOS DE UN HILO — analisis · planes · bugs · client-reports · decisiones
#
# Un hilo es el ticket y adentro cuelgan cosas de tipo distinto. El tipo se nombra
# en plural y en la misma palabra que se lee en la app, así lo que se escribe y lo
# que se navega dicen igual.
# ─────────────────────────────────────────────────────────────────────────────
tipo)
  exige 1 "tipo <analisis|planes|bugs|client-reports|decisiones> [estado]" "$@"
  leer "/api/items/$(uri "$1")${2:+?estado=$(uri "${2:-}")}"
  ;;
abiertos)
  exige 1 "abiertos <analisis|planes|bugs|client-reports|decisiones>" "$@"
  leer "/api/items/$(uri "$1")?abiertos"
  ;;
del-hilo)
  exige 2 "del-hilo <hilo> <tipo>" "$@"
  leer "/api/hilos/$(uri "$1")/$(uri "$2")"
  ;;
# Un ítem entero, con su cuerpo y su historia: es cómo se relee lo que se escribió.
item)
  exige 2 "item <tipo> <id>" "$@"
  leer "/api/items/$(uri "$1")/$(uri "$2")"
  ;;
# La capa traducida de un ítem, con la huella del original que tradujo.
traducir-item)
  exige 2 "traducir-item <tipo> <id>   < {\"traduccion\":{…}}" "$@"
  vaciar_cola
  escribir PATCH "/api/items/$(uri "$1")/$(uri "$2")"
  ;;
analisis | plan | bug | client-report)
  exige 1 "$comando <hilo>   < JSON" "$@"
  vaciar_cola
  case "$comando" in
    analisis) ruta_tipo=analisis ;;
    plan) ruta_tipo=planes ;;
    bug) ruta_tipo=bugs ;;
    client-report) ruta_tipo=client-reports ;;
  esac
  escribir POST "/api/hilos/$(uri "$1")/$ruta_tipo"
  ;;
mover)
  exige 2 "mover <tipo> <id>   < JSON" "$@"
  vaciar_cola
  escribir PATCH "/api/items/$(uri "$1")/$(uri "$2")"
  ;;
# ─────────────────────────────────────────────────────────────────────────────
# EL CICLO DEL ENCARGO — el plan lleva el handoff en el cuerpo y el reporte al volver.
#
# /thinking lo escribe con `plan <hilo>` y "estado":"encargado"; /coding lo toma y lo
# entrega; /thinking lo firma, o lo devuelve con la ronda siguiente en el cuerpo. Son
# azúcar sobre `mover planes <id>`: el estado lo pone el verbo, así nadie lo tipea mal.
# El servidor exige, para llegar a entregado, el reporte y la PR en la ficha.
tomar)
  exige 1 "tomar <id> [nota: el worktree o la copia que lo tiene]" "$@"
  vaciar_cola
  jq -cn --arg n "${2:-}" '{estado:"en-curso"} + (if $n == "" then {} else {nota:$n} end)' |
    escribir PATCH "/api/items/planes/$(uri "$1")"
  ;;
entregar)
  exige 1 "entregar <id>   < {\"reporte\":{\"es\":\"## Hecho\\n…\"},\"ficha\":{\"pr\":\"…\",\"rama\":\"…\"},\"nota\":\"…\"}" "$@"
  vaciar_cola
  jq -c '. + {estado:"entregado"}' | escribir PATCH "/api/items/planes/$(uri "$1")"
  ;;
firmar)
  exige 1 "firmar <id> [nota: la PR mergeada]" "$@"
  vaciar_cola
  jq -cn --arg n "${2:-}" '{estado:"hecho"} + (if $n == "" then {} else {nota:$n} end)' |
    escribir PATCH "/api/items/planes/$(uri "$1")"
  ;;
devolver)
  exige 1 "devolver <id>   < {\"cuerpo\":{\"es\":\"<el cuerpo entero, con su ## Ronda N>\"},\"nota\":\"…\"}" "$@"
  vaciar_cola
  jq -c '. + {estado:"encargado"}' | escribir PATCH "/api/items/planes/$(uri "$1")"
  ;;
# Sin stdin: un DELETE no lleva cuerpo, y esperarlo colgaría la terminal en un Ctrl-D.
sacar)
  exige 2 "sacar <tipo> <id>" "$@"
  curl -fsS --max-time 20 -X DELETE -H "Authorization: Bearer $TOKEN" \
    "$BASE/api/items/$(uri "$1")/$(uri "$2")"
  ;;

documento)
  exige 3 "documento <linea|seccion|flujo> <contenedor> <slug>" "$@"
  leer "/api/documentos?$1=$(uri "$2")&slug=$(uri "$3")"
  ;;
entrada)
  exige 1 "entrada <slug>   < JSON" "$@"
  vaciar_cola
  escribir POST "/api/lineas/$(uri "$1")/entradas"
  ;;
decision)
  exige 1 "decision <slug>   < JSON" "$@"
  vaciar_cola
  escribir POST "/api/lineas/$(uri "$1")/decisiones"
  ;;
# La puerta vieja de las acciones: el Plan absorbió ese trabajo. Abrir está cerrado y no
# encola —sin red, guardar el pedido sería guardar algo que el servidor va a rechazar
# igual—; `hecha` sigue moviendo las que quedaron de antes, con el mismo aviso.
accion)
  exige 1 "accion <hilo>   (cerrado: el trabajo por hacer es un plan)" "$@"
  echo "El trabajo por hacer es un PLAN, que además lleva su análisis:" >&2
  echo "  bitacora-api plan $1 <<< '{\"titulo\":\"…\",\"cierraEn\":\"…\",\"cuerpo\":{\"es\":\"# …\"}}'" >&2
  exit 1
  ;;
hecha)
  exige 1 "hecha <id>   < {\"estado\":\"hecha\",\"nota\":\"…\"}" "$@"
  echo "· Las acciones son lo anterior al Plan: lo de hoy se mueve con bitacora-api mover planes <id>" >&2
  vaciar_cola
  escribir PATCH "/api/acciones/$(uri "$1")"
  ;;
# La decisión nace tomada y no tiene escritorios que mover. `cerrar` queda como la puerta
# de salida de lo HEREDADO: el punto que quedó abierto en el modelo anterior se cierra
# diciendo qué se decidió. La decisión nueva entra ya cerrada por `decision`.
cerrar)
  exige 1 "cerrar <id>   < {\"veredicto\":\"qué se decidió\"}" "$@"
  vaciar_cola
  jq -c '. + {estado:"resuelta"}' | escribir PATCH "/api/decisiones/$(uri "$1")"
  ;;
diferir)
  exige 1 "diferir <id>   (cerrado: lo que espera su momento es un plan)" "$@"
  echo "Diferir era del modelo anterior. Lo que espera su momento es un PLAN," >&2
  echo "con su gatillo escrito en el cuerpo:" >&2
  echo "  bitacora-api plan <hilo> <<< '{\"titulo\":\"…\",\"cierraEn\":\"…\",\"cuerpo\":{\"es\":\"…\"}}'" >&2
  exit 1
  ;;
# Corregir una decisión registrada: su veredicto, su marco, sus textos — o mudarla de hilo.
corregir)
  exige 1 "corregir <id>   < {\"veredicto\":\"…\"} · {\"cuerpo\":{…}} · {\"lineaSlug\":\"…\"}" "$@"
  vaciar_cola
  escribir PATCH "/api/decisiones/$(uri "$1")"
  ;;
superar)
  exige 2 "superar <linea> <id-de-entrada>   < {\"superadaPor\":\"…\"}" "$@"
  vaciar_cola
  escribir PATCH "/api/lineas/$(uri "$1")/entradas/$(uri "$2")"
  ;;
editar-hilo | editar-linea)
  exige 1 "editar-hilo <slug>   < {\"estado\":\"resuelta\"} · {\"area\":\"infra\"}" "$@"
  vaciar_cola
  escribir PATCH "/api/lineas/$(uri "$1")"
  ;;
fusionar)
  exige 1 "fusionar <slug-que-desaparece>   < {\"en\":\"el-que-queda\"}" "$@"
  vaciar_cola
  escribir POST "/api/lineas/$(uri "$1")/fusionar"
  ;;
# abrir-flujo  ← {"nombre":"…","queEs":"…","categoria":"runtime|editorial|ciclo-de-vida|migracion"}
abrir-flujo)
  vaciar_cola
  escribir POST "/api/flujos"
  ;;
editar-flujo)
  exige 1 "editar-flujo <slug>   < {\"estado\":\"construido\"} · {\"sumarStack\":[\"algolia\"]} · {\"sumarGlosario\":[\"route\"]}" "$@"
  vaciar_cola
  escribir PATCH "/api/flujos/$(uri "$1")"
  ;;
# anotar-pieza  ← {"nombre":"…","responsabilidad":"…","donde":"…","comoSeEntra":"…"}
anotar-pieza)
  vaciar_cola
  escribir POST "/api/stack"
  ;;
editar-pieza)
  exige 1 "editar-pieza <slug>   < {\"responsabilidad\":\"…\"}" "$@"
  vaciar_cola
  escribir PATCH "/api/stack/$(uri "$1")"
  ;;
# traducir  ← un documento {"linea|seccion|flujo":"…","slug":"…","idioma":"en","cuerpo":"…","hash":"…"}
#           ← o una ficha  {"tipo":"hilo|area|seccion|flujo|pieza|termino|entrada|punto",
#                          "llave":"…","idioma":"en","campos":{…},"huella":"…"}
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
  escribir PATCH "/api/areas/$(uri "$1")"
  ;;
seccion)
  vaciar_cola
  escribir POST "/api/secciones"
  ;;
editar-seccion)
  exige 1 "editar-seccion <slug>   < JSON" "$@"
  vaciar_cola
  escribir PATCH "/api/secciones/$(uri "$1")"
  ;;
definir)
  # definir  ← {"termino":"…","definicion":"…"} o una lista de esos
  vaciar_cola
  escribir PUT "/api/glosario"
  ;;
anotar-acceso)
  # anotar-acceso  ← {"nombre":"…","url":"https://…","nota":"staging","usuario":"…","clave":"…"}
  #                  o una lista de esos. `usuario`/`clave` son con qué se entra al lugar.
  vaciar_cola
  escribir PUT "/api/enlaces"
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
  escribir PATCH "/api/trabajo/$(uri "$1")"
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
  El proyecto se deduce de dónde estás parado, bajo ~/ProyectosDev-Local y bajo cada
  `raiz=<path>` de config.local (<raíz>/<proyecto> → <proyecto>, y
  `alias.<carpeta>=<tenant>` traduce la que no se llama como su tenant);
  -p lo fija a mano. Lo marcado (dueño) contesta 403 con la llave de un colaborador.
  bitacora-api proyecto                      (dice cuál resolvió)
  bitacora-api version                       (la instalada contra la última publicada — lo primero de cada invocación)

El sistema del proyecto — la tríada. Primera lectura al llegar:
  bitacora-api contexto                     (el dominio + el stack + los flujos, de una)
  bitacora-api flujos                       · bitacora-api flujo <slug>
  bitacora-api stack [flujos]               · bitacora-api pieza <slug|alias>
  bitacora-api glosario                     · bitacora-api termino <palabra>
  bitacora-api accesos                      (las direcciones de afuera, con qué se entra a cada una)

El trabajo (en el taller un tema se llama HILO; la API lo guarda como `lineas`):
  bitacora-api abrir                        (el tablero en tu navegador, sin login: enlace fresco de un solo uso)
  bitacora-api tablero                      (los hilos con su área y sus ítems, las áreas, lo pendiente por escritorio, la tríada contada)
  bitacora-api bandeja                      (sin -p: los planes entregados, en curso y encargados de TODOS los proyectos)
  bitacora-api encargados · en-curso · entregados   (el ciclo del encargo, por escritorio; cada plan con su hilo y su área)
  bitacora-api hilos                        (= lineas)
  bitacora-api hilo <slug|alias>            (= linea)
  bitacora-api areas                        (los mundos del proyecto, con sus hilos)
  bitacora-api area <slug>                  (un área con los hilos que viven ahí; `areas <slug>` es lo mismo)
  bitacora-api buscar <texto>
  bitacora-api documento <linea|seccion|flujo> <contenedor> <slug>
  bitacora-api secciones · bitacora-api horas (dueño) · bitacora-api adjuntos [linea] · bitacora-api reviews
  bitacora-api del-hilo <hilo> <tipo>       (lo que cuelga de un hilo, de un tipo)
  bitacora-api tipo <tipo> [estado]         (todos los del proyecto, cruzando hilos)
  bitacora-api item <tipo> <id>             (uno entero: su cuerpo y cómo se movió)
  bitacora-api abiertos <tipo>              (los que quedaron sin cerrar; el análisis y la decisión no tienen)
        tipo = analisis | planes | bugs | client-reports | decisiones
  bitacora-api por-traducir [idioma]        (documentos y fichas: lo que falta y lo que quedó viejo)

Escritura (el cuerpo JSON entra por stdin):
  bitacora-api analisis <hilo>              {"titulo":"…","queEs":"…","cuerpo":{"es":"# …"}}
  bitacora-api plan <hilo>                  {"titulo":"…","cierraEn":"…","cuerpo":{"es":"# …"},"flujos":["…"]}
        con "estado":"encargado" nace como ENCARGO: el cuerpo es el handoff y cierraEn el criterio de terminado
  bitacora-api bug <hilo>                   {"titulo":"…","cuerpo":{"es":"qué pasa y cómo se reproduce"},"flujos":["…"]}
        `flujos` son los recorridos que el ítem corta mientras está abierto: de ahí sale la madurez del flujo
  bitacora-api client-report <hilo>         {"titulo":"…","cuerpo":{"es":"# …"}}
  bitacora-api traducir-item <tipo> <id>    {"traduccion":{"idioma":"en","cuerpo":"…","hash":"…"}}
  bitacora-api mover <tipo> <id>            {"estado":"hecho","nota":"cómo cerró"}
                                            · {"hilo":"el-que-corresponde"} lo muda de hilo (acepta el alias)
        la decisión NO tiene escritorios: nace tomada y se corrige con corregir
  El ciclo del encargo (azúcar sobre mover planes; el estado lo pone el verbo):
  bitacora-api tomar <id> [nota]            → en-curso; la nota es el worktree o la copia que lo tiene
  bitacora-api entregar <id>                {"reporte":{"es":"## Hecho\n…"},"ficha":{"pr":"…","rama":"…"},"nota":"…"} → entregado
                                            (el servidor exige el reporte y ficha.pr; en MACS la ficha suma review y horas)
  bitacora-api firmar <id> [nota]           → hecho; la nota es la PR mergeada
  bitacora-api devolver <id>                {"cuerpo":{"es":"<entero, con su ## Ronda N>"},"nota":"…"} → encargado
  bitacora-api sacar <tipo> <id>            (el que se abrió por error — dueño)
  bitacora-api entrada <slug>               {"tipo":"hallazgo","titulo":"…","cuerpo":"…"}
  bitacora-api superar <slug> <id-entrada>  {"superadaPor":"…"}
  bitacora-api decision <slug>              se registra YA TOMADA, con su análisis entero:
                                            {"titulo":"…","veredicto":"qué se decidió",
                                             "bloquea":"qué se frenaba","opciones":[{"titulo":"…","implica":"…"},…],
                                             "recomiendo":0,"recomendacion":"por qué esa",
                                             "cierraEn":"…","cuerpo":"…","flujos":["…"]}
  bitacora-api corregir <id>                {"veredicto":"…"} · {"cuerpo":{…}} · {"lineaSlug":"…"}
  bitacora-api cerrar <id>                  {"veredicto":"qué se decidió"} — la salida del punto HEREDADO que quedó abierto
  bitacora-api abrir-hilo                   {"slug":"…","nombre":"…","area":"…","brief":"…"}
  bitacora-api editar-hilo <slug>           {"estado":"resuelta"} · {"brief":"…"} · {"area":"infra"}
  bitacora-api abrir-area                   {"nombre":"El contrato"}   (nace vacía; se llena mudando hilos)
  bitacora-api editar-area <slug>           {"nombre":"…"} (renombra) · {"orden":2} (su lugar en el menú)
  bitacora-api fusionar <slug>              {"en":"la-que-queda"}
  bitacora-api abrir-flujo                  {"nombre":"…","queEs":"…","categoria":"runtime"}
  bitacora-api editar-flujo <slug>          {"estado":"construido"} · {"sumarStack":[…]} · {"sumarGlosario":[…]}
  bitacora-api anotar-pieza                 {"nombre":"…","responsabilidad":"…","donde":"…","documentacion":"https://…","notas":"…"}
  bitacora-api editar-pieza <slug>          {"responsabilidad":"…"} · {"sumarAlias":["el CMS"]}
  bitacora-api seccion                      {"tipo":"archivo","nombre":"…","nota":"…"}
  bitacora-api editar-seccion <slug>        {"resumen":"…"} · {"tipo":"fuente"}
  bitacora-api definir                      {"termino":"…","definicion":"…"}  (o una lista)
  bitacora-api anotar-acceso                {"nombre":"Engine API","url":"https://…","nota":"staging"}
                                            · con qué se entra: {"usuario":"…","clave":"…"}
  bitacora-api review                       {"titulo":"<título del PR>","pr":"…","cuerpo":"…"}
  bitacora-api rato (dueño)                 {"tarea":"…","reloj":"1:30"}   (el banco de horas)
  bitacora-api mover-rato <id> (dueño)      {"estado":"cargado"}
  bitacora-api guardar-documento            el documento entero
  bitacora-api traducir                     {"linea":"…","slug":"…","idioma":"en","cuerpo":"…","hash":"…"}
  bitacora-api traducir                     {"tipo":"hilo","llave":"…","idioma":"en","campos":{…},"huella":"…"}
                                            (traduce desde el `escritoEn` del documento)
                                            (acepta linea|seccion|flujo, los nombres que da la cola)
  bitacora-api mudar-documento <linea|seccion|flujo> <contenedor> <slug>   {"lineaSlug":"otra"}

Archivos y bajas (borrar es del dueño):
  bitacora-api adjuntar <archivo> linea=<slug> [queEs="…"]
  bitacora-api borrar /api/lineas/<slug>     (se niega si todavía cuelga algo)
  bitacora-api borrar /api/areas/<slug>      (se niega si algún hilo vive ahí)
  bitacora-api borrar /api/enlaces/<slug>    (saca un acceso de la columna)
  bitacora-api pendientes                    (sube lo que quedó sin red)

El alta y la renovación de la llave:
  bitacora-api alta <código>                 (canjea el código del email por la llave y la guarda)
  bitacora-api renovar                       (la llave vence sola: esto manda el código nuevo a tu email)
USO
  exit 1
  ;;
esac
