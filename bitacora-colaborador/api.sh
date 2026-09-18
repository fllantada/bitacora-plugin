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
    # Una config sin llaves de tenant es una bandeja vacía, y eso es una respuesta.
    { grep -E '^[a-z0-9-]+=' "$CONFIG" | grep -vE '^(url|raiz)=' || true; } | while IFS='=' read -r tenant llave; do
      respuesta="$(curl -fsS --max-time 20 -H "Authorization: Bearer $llave" \
        "$BASE/api/items/planes?abiertos" 2>/dev/null)" || {
        echo "· sin respuesta de «${tenant}» (llave vencida, o sin red)" >&2
        continue
      }
      printf '%s' "$respuesta" | jq -c --arg p "$tenant" \
        '.items[] | select(.estado == "entregado" or .estado == "en-curso" or .estado == "encargado")
         | {proyecto: $p, tipo: "plan", estado, hilo, area, titulo, id, ficha}'
      # Las consultas que esperan a la persona son la mano que falta: van primero, porque solo
      # ella las destraba. La abierta cuyo resto pidió más contexto espera a la sesión y no va.
      consultas="$(curl -fsS --max-time 20 -H "Authorization: Bearer $llave" \
        "$BASE/api/items/consultas?estado=abierta" 2>/dev/null)" || continue
      printf '%s' "$consultas" | jq -c --arg p "$tenant" \
        '.items[] | select(((.faltan // []) | length) > 0)
         | {proyecto: $p, tipo: "consulta", estado, hilo, area, titulo, id, respuestas, faltan, pidenContexto}'
      # Y los chequeos visuales que esperan sus ojos, por la misma razón: lo que se aprueba
      # mirando solo lo destraba la persona, y una PR se queda esperando ese sí.
      chequeos="$(curl -fsS --max-time 20 -H "Authorization: Bearer $llave" \
        "$BASE/api/items/chequeos?estado=abierto" 2>/dev/null)" || continue
      printf '%s' "$chequeos" | jq -c --arg p "$tenant" \
        '.items[] | select(((.faltan // []) | length) > 0)
         | {proyecto: $p, tipo: "chequeo", estado, hilo, area, titulo, id, respuestas, faltan, pidenContexto}'
      # Las consultas al cliente: por preguntar es la mano de la persona —llevársela—, y va
      # con las que esperan; preguntada espera al cliente, con los días que lleva y la fecha
      # para la que hace falta, y va al final con lo que se empuja con un recordatorio.
      alcliente="$(curl -fsS --max-time 20 -H "Authorization: Bearer $llave" \
        "$BASE/api/items/consultas-cliente?abiertos" 2>/dev/null)" || continue
      printf '%s' "$alcliente" | jq -c --arg p "$tenant" \
        '.items[] | select((.estado == "por-preguntar" or .estado == "preguntada") and ((.faltan // []) | length) > 0)
         | {proyecto: $p, tipo: "consulta-cliente", estado, hilo, area, titulo, id, faltan, pidenContexto, para, diasEnElCliente}'
    done
  } | jq -s 'sort_by(if .estado == "preguntada" then 4 elif .tipo == "consulta" or .tipo == "chequeo" or .tipo == "consulta-cliente" then 0 elif .estado == "entregado" then 1 elif .estado == "en-curso" then 2 else 3 end)'
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
  # Con un destino —la ruta o el enlace entero de una pieza— el enlace cae en esa página y
  # no en el tablero: es cómo la sesión abre lo que acaba de escribir. Se reemplaza el
  # destino que el servidor ya puso (la casa del proyecto); el segundo `a=` se ignoraría.
  if [ -n "${2:-}" ]; then
    DESTINO="$(printf '%s' "$2" | sed -E 's#^https?://[^/]+##; s/[#?].*$//')"
    case "$DESTINO" in /*) ;; *) DESTINO="/$DESTINO" ;; esac
    URL_ABRIR="$(printf '%s' "$RESPUESTA" | jq -r --arg a "$DESTINO" '.url | sub("(?<s>[&?])a=[^&]*"; "\(.s)a=\($a)")')"
  else
    URL_ABRIR="$(printf '%s' "$RESPUESTA" | jq -r .url)"
  fi
  if command -v open >/dev/null 2>&1; then
    open "$URL_ABRIR"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$URL_ABRIR"
  else
    echo "Abrí esto en tu navegador (vale unos minutos, un solo uso):"
    echo "$URL_ABRIR"
    exit 0
  fi
  if [ -n "${2:-}" ]; then
    echo "«${DESTINO}» se está abriendo en tu navegador."
  else
    echo "El tablero de «${PROYECTO}» se está abriendo en tu navegador."
  fi
  exit 0
fi

# --- el transporte ------------------------------------------------------------

# Una lectura que el servidor rechaza imprime lo que el servidor DIJO: sus 404 y 400
# traen la instrucción adentro («se cargan con…», «la puerta es…»), y un `curl -f` la
# tiraba y dejaba solo el código. El mismo trato que da `escribir`.
leer() {
  local ruta="$1" respuesta codigo salida
  # El idioma viaja en la query, y algunas rutas ya traen la suya.
  if [ -n "$IDIOMA" ]; then
    case "$ruta" in
    *\?*) ruta="$ruta&idioma=$IDIOMA" ;;
    *) ruta="$ruta?idioma=$IDIOMA" ;;
    esac
  fi
  respuesta="$(curl -sS --max-time 20 -H "Authorization: Bearer $TOKEN" \
    -w $'\n%{http_code}' "$BASE$ruta" 2>/dev/null || printf '\n000')"
  codigo="${respuesta##*$'\n'}"
  salida="${respuesta%$'\n'*}"
  case "$codigo" in
  2*)
    printf '%s\n' "$salida"
    return 0
    ;;
  000)
    echo "Sin respuesta del servidor ($BASE)." >&2
    return 1
    ;;
  *)
    echo "El servidor dijo que no ($codigo): $salida" >&2
    return 1
    ;;
  esac
}

# Lo que viaja en la URL: un slug con espacios o un texto de búsqueda.
uri() { jq -rn --arg v "$1" '$v|@uri'; }

# Sube un archivo. No pasa por la cola: un binario no entra en una línea de JSONL, y
# reintentar una subida a ciegas es peor que volver a escribir el comando.
#
# La subida que el servidor rechaza imprime lo que el servidor DIJO, igual que `leer`: el 400
# de la puerta trae la razón adentro, y el rechazo de la plataforma por tamaño trae el suyo.
subir() {
  local archivo="$1" respuesta codigo salida
  shift
  # El archivo se busca antes de mandarlo: con rutas relativas, la carpeta suele ser la causa.
  { [ -f "$archivo" ] && [ -r "$archivo" ]; } || { echo "No se puede leer $archivo (buscado desde $PWD); revisá la ruta." >&2; return 1; }
  local campos=()
  for par in "$@"; do campos+=(-F "$par"); done
  respuesta="$(curl -sS --max-time 120 -H "Authorization: Bearer $TOKEN" \
    -F "archivo=@$archivo" "${campos[@]}" -w $'\n%{http_code}' "$BASE/api/adjuntos" \
    2>/dev/null || printf '\n000')"
  codigo="${respuesta##*$'\n'}"
  salida="${respuesta%$'\n'*}"
  case "$codigo" in
  2*)
    printf '%s\n' "$salida"
    ;;
  000)
    echo "Sin respuesta del servidor ($BASE) al subir $archivo." >&2
    return 1
    ;;
  *)
    echo "El servidor no aceptó $archivo ($codigo): $salida" >&2
    return 1
    ;;
  esac
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
  # Lo que a ESTE proyecto le falta adaptar cuando el modelo de la bitácora cambió. Es un
  # aviso y nunca una puerta: fuera de un proyecto, sin red o sin llave, no dice nada.
  if [ -n "${TOKEN:-}" ]; then
    leer "/api/adaptacion" 2>/dev/null | jq -r --arg n "$nombre" '
      (if $n == "bitacora-colaborador" then "en" else "es" end) as $i
      | .pendientes[]?
      | "\n⚠ Adaptación pendiente «\(.clave)» (rige desde \(.desde)):\n  \(.queCambio[$i])\n  → \(.queHacer[$i])"
        + (if (.senales.enCompartida // [] | length) > 0
           then "\n  En «compartida» siguen: \(.senales.enCompartida | join(", "))" else "" end)
    ' 2>/dev/null || true
  fi
  ;;
tablero) leer "/api/tablero" ;;
# El ciclo del encargo, leído por escritorio: lo que una sesión /coding puede tomar, lo
# que alguien tiene entre manos, y lo que espera la firma de /thinking. Cada plan trae
# su sub-área y su área; `item planes <id>` lo trae entero, con el handoff y el reporte.
encargados) leer "/api/items/planes?estado=encargado" ;;
en-curso) leer "/api/items/planes?estado=en-curso" ;;
entregados) leer "/api/items/planes?estado=entregado" ;;
# El taller dice SUB-ÁREA —antes «hilo»— y la API dice `lineas`: los tres nombres alcanzan
# lo mismo, para que la palabra que se lee y la que se tipea sean la misma.
subareas | hilos | lineas) leer "/api/lineas" ;;
subarea | hilo | linea)
  exige 1 "subarea <slug|alias>" "$@"
  leer "/api/lineas/$(uri "$1")"
  ;;
# Las adaptaciones de modelo que este proyecto todavía no hizo, con lo que su material
# dice hoy (`senales`), y las que ya cerró. El paso cero (`version`) las recuerda.
adaptacion) leer "/api/adaptacion" ;;
# Cierra una: el servidor comprueba lo comprobable y contesta 400 con lo que falta.
adaptado)
  exige 1 "adaptado <clave>   (p. ej. subareas)" "$@"
  vaciar_cola
  printf '{"clave":"%s"}' "$1" | escribir POST "/api/adaptacion"
  ;;
buscar)
  exige 1 "buscar <texto>" "$@"
  leer "/api/buscar?q=$(uri "$1")"
  ;;
# El sistema del proyecto en una llamada: el dominio, el stack, los flujos y las fuentes, MÁS las
# instrucciones del ciclo en este tenant (el markdown crudo, o null).
# Las skills NO viajan acá: la sesión ya tiene las suyas en el disco, y el catálogo es la
# vista para el humano (se lee con `skills`). /thinking y /coding la hacen en su paso 0 y
# obedecen las instrucciones.
contexto) leer "/api/contexto" ;;
# Cómo se corre el ciclo acá, solas: dónde se para cada sesión, qué gatea un commit, cómo
# sale la PR, dónde se publica la review, cómo se factura, las fuentes, los registros, las
# skills. Es material del proyecto: la lee todo miembro. Sin cargar contesta 404.
instrucciones) leer "/api/instrucciones" ;;
# De qué vive el cliente, con SUS palabras: a qué se dedica, qué vende, a quién llega y qué
# lo distingue. Es la primera lectura del proyecto — el glosario es su vocabulario, no él.
# Sin escribir contesta 404 diciendo qué va adentro.
dominio) leer "/api/dominio" ;;
# Las herramientas que esta sesión tiene a mano, con qué hace cada una: las propias del
# repo, las compartidas del perfil y las del método del plugin. El catálogo lo mantiene
# la skill /skills del plugin, a mano, con `sincronizar-skills`.
skills) leer "/api/skills" ;;
skill)
  exige 1 "skill <nombre>   (cómo se la cuenta, con qué se encadena y su SKILL.md)" "$@"
  leer "/api/skills/$(uri "${1#/}")"
  ;;
# LA NOTA: la skill contada para una persona, que es lo único del catálogo que se escribe.
#
# El resto se deriva del archivo y dice para qué la convocaría un harness; esto contesta la
# pregunta de quien abre el catálogo: para qué me sirve, cuándo la llamo, qué me deja hecho.
# Se escribe leyendo el SKILL.md, y el servidor la aparea con esa versión: cuando el archivo
# cambie, la sincronización nombra la nota que quedó vieja.
nota-skill)
  exige 1 "nota-skill <nombre>   < {\"paraQue\":\"…\",\"cuando\":\"…\",\"deja\":\"…\",\"ojo\":\"…\"}" "$@"
  vaciar_cola
  nota_dicha="$(cat)"
  if [ -z "$(printf '%s' "$nota_dicha" | jq -r '.paraQue // empty' 2>/dev/null)" ]; then
    echo "nota-skill lleva los cuatro renglones con que se cuenta una skill:" >&2
    echo '  {"paraQue":"qué resuelve, como se lo contarías a alguien que nunca la usó",' >&2
    echo '   "cuando":"en qué momento se la invoca","deja":"qué queda hecho cuando termina",' >&2
    echo '   "ojo":"lo que conviene saber antes (opcional)"}' >&2
    echo "  Se escribe leyendo su texto: bitacora-api skill <nombre>" >&2
    exit 1
  fi
  printf '%s' "$nota_dicha" | escribir PUT "/api/skills/$(uri "${1#/}")/nota"
  ;;
# La skill que se RETIRÓ: sale del catálogo con su texto y su nota.
#
# La que esta máquina dejó de ver se atenúa sola y espera, porque otro perfil puede tenerla;
# esto es decir que ya no existe en ninguno. Del dueño, como todo borrado.
sacar-skill)
  exige 1 "sacar-skill <nombre>   (la que se retiró: sale del catálogo — dueño)" "$@"
  curl -fsS --max-time 20 -X DELETE -H "Authorization: Bearer $TOKEN" \
    "$BASE/api/skills/$(uri "${1#/}")"
  ;;
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
# ── LAS FUENTES: lo que el cliente entregó, con de cuándo es cada cosa ────────
#
# El registro entero llega en el orden que ES la regla de qué manda: las vivas del cliente
# arriba, las fechadas de la más nueva a la más vieja, las superadas al pie. Antes de decidir
# algo sobre un tema, esto contesta qué material hay y cuál manda.
#
#   bitacora-api fuentes                 (todas)
#   bitacora-api fuentes algolia         (las de ese tema: el slug de un área, de una sub-área o de una pieza)
#   bitacora-api fuentes "" hoja         (solo las hojas)
fuentes)
  ruta="/api/fuentes"
  sep="?"
  if [ -n "${1:-}" ]; then
    ruta="$ruta${sep}tag=$(uri "$1")"
    sep="&"
  fi
  [ -n "${2:-}" ] && ruta="$ruta${sep}clase=$(uri "$2")"
  leer "$ruta"
  ;;
fuente)
  exige 1 "fuente <slug>" "$@"
  leer "/api/fuentes/$(uri "$1")"
  ;;
# Las vivas cuya copia quedó vieja, con lo que hace falta para refrescarla: por dónde se
# lee (`procedencia`), su handle (`ref`), la huella de lo que ya tenemos y de cuándo es.
por-sincronizar)
  leer "/api/fuentes?vigencia=viva" |
    jq '[.[] | select(.esperaRefresco) | {slug, nombre, procedencia, ref, url, hash: (.espejo.hash // null), sincronizadoAt: (.espejo.sincronizadoAt // null)}]'
  ;;
# Los accesos directos del proyecto: las direcciones de afuera a las que se entra todos
# los días — el engine, el repo, el tablero de tickets, el diseño.
accesos) leer "/api/enlaces" ;;   # con su `usuario`/`clave`, el que la pide
# Qué falta HACER: del proyecto entero, o de una sub-área si se la nombra. El segundo argumento
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
# Las áreas: los mundos del proyecto, con cuántas sub-áreas vive cada uno.
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
# El estado del área: la foto de dónde está ese mundo hoy, con su historia detrás.
#
# Contesta la vigente entera —su cuerpo con las cinco secciones, su hito, el plan que la
# produjo— más la cadena (`anterior`, `siguiente`, `fotos`) y `desde`: lo que se firmó y
# qué fuente cambió después de tomarla, que es la señal de que toca renovarla. Con
# `--version N` contesta una foto anterior. Sin ninguna foto, 404 diciendo cómo se toma.
estado)
  exige 1 "estado <area> [--version N]" "$@"
  if [ "${2:-}" = "--version" ] && [ -n "${3:-}" ]; then
    leer "/api/areas/$(uri "$1")/estado?version=$(uri "$3")"
  else
    leer "/api/areas/$(uri "$1")/estado"
  fi
  ;;
secciones) leer "/api/secciones" ;;
reviews) leer "/api/reviews" ;;
# ─────────────────────────────────────────────────────────────────────────────
# PONER UNA PIEZA AFUERA — se lee sin entrar, y nada más que esa pieza.
#
# La dirección que devuelve (`enlace`) es la que se manda: cualquiera con ella lee la
# página, sin cuenta y sin login. El resto del proyecto —el tablero, el hilo, las otras
# piezas— sigue adentro, y el espejo público no tiene navegación, así que de una pieza
# publicada no se llega a nada más.
#
# La pieza se nombra como se la lee: `<subarea> <slug>` para lo que cuelga de un hilo, y la
# sección sola para una review, que es una sección de un solo documento. Publicar abre
# también los archivos que ese texto muestra —las capturas, el PDF que un client-report
# entregó— y `privado` los cierra con ella.
#
# Es del dueño del proyecto: la llave de un colaborador recibe un 403.
# ─────────────────────────────────────────────────────────────────────────────
publicar | privado)
  exige 1 "$comando <subarea> <slug>   |   $comando <seccion>   |   $comando <linea|seccion|flujo> <contenedor> <slug>" "$@"
  vaciar_cola
  [ "$comando" = publicar ] && afuera=true || afuera=false

  # Tres formas de nombrar la pieza, y la elige la cantidad de argumentos:
  #
  #   · con TRES, la explícita: el contenedor con su nombre, igual que `documento` y
  #     `mudar-documento`. Es la que sirve cuando la sección tiene varios documentos, o
  #     archivos propios, o cuando el texto vive en un flujo.
  #   · con DOS, el hilo y el slug: la dirección de lo que cuelga de un ticket.
  #   · con UNO, la sección sola: la review, que es una sección de un solo documento.
  #
  # El cuerpo se arma ANTES del pipe: lo que se valida acá tiene que poder cortar el
  # script, y `algo | escribir` corre en un subshell — un `exit` ahí abajo deja pasar un
  # cuerpo vacío y manda el pedido igual.
  campo=hilo
  case "$#:$1" in
  3:linea | 3:hilo) contenedor="$2" pieza="$3" ;;
  3:seccion | 3:flujo) campo="$1" contenedor="$2" pieza="$3" ;;
  3:*)
    echo "El contenedor es linea, seccion o flujo (llegó «$1»)." >&2
    exit 1
    ;;
  2:linea | 2:hilo | 2:seccion | 2:flujo)
    echo "A «$comando $1 $2» le falta el slug de la pieza." >&2
    echo "  · $comando <subarea> <slug>" >&2
    echo "  · $comando <seccion>                                 (una review)" >&2
    echo "  · $comando <linea|seccion|flujo> <contenedor> <slug>" >&2
    exit 1
    ;;
  2:*) contenedor="$1" pieza="$2" ;;
  1:*) campo=seccion contenedor="$1" pieza="" ;;
  # Un argumento de más cae acá, y va al final porque un `case` resuelve en orden: puesto
  # antes tapaba la forma de la sección sola. Sin esta rama, lo que se nombraba pasaba a
  # ser la palabra `linea` y el servidor contestaba sobre una sección que nadie nombró.
  *)
    echo "Sobran argumentos. Las tres formas son:" >&2
    echo "  · $comando <subarea> <slug>" >&2
    echo "  · $comando <seccion>                                 (una review)" >&2
    echo "  · $comando <linea|seccion|flujo> <contenedor> <slug>" >&2
    exit 1
    ;;
  esac

  jq -cn --argjson p "$afuera" --arg k "$campo" --arg c "$contenedor" --arg s "$pieza" \
    '{publico:$p} + {($k): $c} + (if $s == "" then {} else {slug:$s} end)' |
    escribir PUT "/api/publicacion"
  ;;
# Qué está afuera hoy, con el enlace de cada uno: lo que se pregunta antes de mandar
# una dirección, y de un tirón el día que se quiera cerrar todo.
publicados) leer "/api/publicacion" ;;
horas) leer "/api/trabajo" ;;
adjuntos) leer "/api/adjuntos${1:+?linea=$(uri "${1:-}")}" ;;
# ─────────────────────────────────────────────────────────────────────────────
# LOS TIPOS DE UNA SUB-ÁREA — analisis · planes · bugs · client-reports · decisiones · simulaciones · consultas · chequeos
#
# Una sub-área es el lugar y adentro cuelgan cosas de tipo distinto. El tipo se nombra
# en plural y en la misma palabra que se lee en la app, así lo que se escribe y lo
# que se navega dicen igual.
# ─────────────────────────────────────────────────────────────────────────────
tipo)
  exige 1 "tipo <analisis|planes|bugs|client-reports|decisiones|simulaciones|consultas|chequeos> [estado]" "$@"
  leer "/api/items/$(uri "$1")${2:+?estado=$(uri "${2:-}")}"
  ;;
abiertos)
  exige 1 "abiertos <analisis|planes|bugs|client-reports|decisiones|simulaciones|consultas|chequeos>" "$@"
  leer "/api/items/$(uri "$1")?abiertos"
  ;;
de-la-subarea | del-hilo)
  exige 2 "de-la-subarea <subarea> <tipo>" "$@"
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
analisis | plan | bug | client-report | simulacion | consulta | consulta-cliente | chequeo)
  exige 1 "$comando <subarea>   < JSON" "$@"
  vaciar_cola
  case "$comando" in
    analisis) ruta_tipo=analisis ;;
    plan) ruta_tipo=planes ;;
    bug) ruta_tipo=bugs ;;
    client-report) ruta_tipo=client-reports ;;
    simulacion) ruta_tipo=simulaciones ;;
    consulta) ruta_tipo=consultas ;;
    consulta-cliente) ruta_tipo=consultas-cliente ;;
    chequeo) ruta_tipo=chequeos ;;
  esac
  escribir POST "/api/hilos/$(uri "$1")/$ruta_tipo"
  ;;
mover)
  exige 2 "mover <tipo> <id>   < JSON" "$@"
  vaciar_cola
  escribir PATCH "/api/items/$(uri "$1")/$(uri "$2")"
  ;;
# ─────────────────────────────────────────────────────────────────────────────
# LO QUE ABRE LA SUB-ÁREA — la pieza clavada arriba.
#
# Una sub-área ordena sus piezas por el trabajo: lo que se está haciendo arriba, lo cerrado al
# pie. Lo que ese orden no puede contestar es cuál de todas cuenta DE QUÉ SE TRATA el
# ticket —suele ser un análisis, que no tiene escritorio y cae en el medio—. Fijarla la
# pone primera en la página de la sub-área y en el menú. Azúcar sobre `mover`.
fijar)
  exige 2 "fijar <tipo> <id>" "$@"
  vaciar_cola
  printf '{"fijado":true}' | escribir PATCH "/api/items/$(uri "$1")/$(uri "$2")"
  ;;
soltar)
  exige 2 "soltar <tipo> <id>" "$@"
  vaciar_cola
  printf '{"fijado":false}' | escribir PATCH "/api/items/$(uri "$1")/$(uri "$2")"
  ;;
# ─────────────────────────────────────────────────────────────────────────────
# EL CICLO DEL ENCARGO — el plan lleva el handoff en el cuerpo y el reporte al volver.
#
# /thinking lo escribe con `plan <subarea>` y "estado":"encargado"; /coding lo toma y lo
# entrega; /thinking lo firma, o lo devuelve con la ronda siguiente en el cuerpo. Son
# azúcar sobre `mover planes <id>`: el estado lo pone el verbo, así nadie lo tipea mal.
# El servidor cobra el contrato en las dos puntas: para entrar a encargado, el cuerpo
# con sus ocho secciones (Qué cambia · Tarea · La idea · Destino · Contexto ·
# Patrón a seguir · Alcance · Fuera de alcance) y su queEs; para llegar a entregado, el reporte con las suyas
# (Hecho · Evidencia · Decisiones sobre la marcha · Fricciones · Para decidir ·
# Pendientes fuera de alcance, las tres últimas van siempre y dicen «Ninguna» cuando no
# hubo: una sección ausente o vacía rebota como olvido) y la PR en la ficha.
# Un 400 nombra todo lo que falta de una vez, con lo que cada sección afirma.
# La nota va también a `ficha.destino`: las listas —en-curso, bandeja— sirven la ficha y
# no la historia, y quién tiene un plan se pregunta desde una lista.
tomar)
  exige 1 "tomar <id> [nota: el worktree o la copia que lo tiene]" "$@"
  vaciar_cola
  jq -cn --arg n "${2:-}" \
    '{estado:"en-curso"} + (if $n == "" then {} else {nota:$n, ficha:{destino:$n}} end)' |
    escribir PATCH "/api/items/planes/$(uri "$1")"
  ;;
entregar)
  exige 1 "entregar <id>   < {\"reporte\":{\"es\":\"## Hecho\\n…\\n## Evidencia\\n…\\n## Decisiones sobre la marcha\\n…\\n## Fricciones\\n…\\n## Para decidir\\n…\\n## Pendientes fuera de alcance\\n…\"},\"ficha\":{\"pr\":\"…\",\"rama\":\"…\",\"review\":\"…\"},\"consumo\":{\"preciosDe\":\"AAAA-MM-DD\",\"modelos\":[…]},\"nota\":\"…\"}" "$@"
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
  exige 1 "devolver <id>   < {\"cuerpo\":{\"es\":\"<el cuerpo entero, con sus ocho secciones y su ## Ronda N>\"},\"nota\":\"…\"}" "$@"
  vaciar_cola
  # Devolver es agregar la ronda: un cuerpo vacío se contesta acá con la forma, porque el
  # verbo pone el estado y el servidor recibiría un movimiento sin ronda que parece válido.
  cuerpo_devuelto="$(cat)"
  if [ -z "$(printf '%s' "$cuerpo_devuelto" | jq -r '.cuerpo // empty' 2>/dev/null)" ]; then
    echo "devolver lleva el cuerpo ENTERO del plan con la ronda nueva al final:" >&2
    echo '  {"cuerpo":{"es":"# Qué cambia\n…\n# Tarea\n…\n# La idea\n…\n# Destino\n…\n# Contexto\n…\n# Patrón a seguir\n…\n# Alcance\n…\n# Fuera de alcance\n…\n\n## Ronda N\nqué → por qué → corrección propuesta"},"nota":"vuelve: <por qué, en una frase>"}' >&2
    echo "  Se lee con: bitacora-api item planes <id>   (el cuerpo actual, para agregarle la ronda)" >&2
    exit 1
  fi
  printf '%s' "$cuerpo_devuelto" | jq -c '. + {estado:"encargado"}' | escribir PATCH "/api/items/planes/$(uri "$1")"
  ;;
# ─────────────────────────────────────────────────────────────────────────────
# LA SIMULACIÓN — el experimento antes de adoptar un cambio: la sesión produce, la persona
# califica.
#
# Nace `disenada` con su hipótesis, su criterio de éxito, sus brazos, su muestra, su
# rúbrica y lo esperado. La persona aprueba el diseño EN LA WEB (fija todo eso); la
# sesión la pasa a `corriendo`, deja lo que produjo cada brazo para cada ítem (`salidas`),
# declara enlaces y costo por brazo (`brazos`) y la deja `lista` para calificar; la
# persona califica en la web —a ciegas, ítem por ítem— y concluye con su veredicto.
# Aprobar, calificar y concluir contestan 400 por esta puerta: son de la persona.
# ─────────────────────────────────────────────────────────────────────────────
simulaciones) leer "/api/items/simulaciones${1:+?estado=$(uri "${1:-}")}" ;;
# Qué falta correr y qué salidas ya están: la bandeja de la sesión que corre.
faltan)
  exige 1 "faltan <id>" "$@"
  leer "/api/items/simulaciones/$(uri "$1")" | jq '{estado, faltan, salidas: [.salidas[] | {brazo, item, enlace: (.enlace // null)}]}'
  ;;
# La calificación de la persona, para registrar la decisión que tomó: la matriz, las
# elecciones por ítem, lo esperado con su cumplido y el veredicto.
calificacion)
  exige 1 "calificacion <id>" "$@"
  leer "/api/items/simulaciones/$(uri "$1")" | jq '{estado, cumplido, veredicto, matriz, elecciones, esperados}'
  ;;
correr)
  exige 1 "correr <id> [nota]" "$@"
  vaciar_cola
  jq -cn --arg n "${2:-}" '{estado:"corriendo"} + (if $n == "" then {} else {nota:$n} end)' |
    escribir PATCH "/api/items/simulaciones/$(uri "$1")"
  ;;
# brazos <id>  ← [{"clave":"A","enlaces":{"compare":"https://…"},"consumo":{…}}]  (o {"brazos":[…]})
brazos)
  exige 1 "brazos <id>   < [{\"clave\":\"A\",\"enlaces\":{…},\"consumo\":{…}}]" "$@"
  vaciar_cola
  jq -c 'if type == "array" then {brazos: .} else . end' | escribir PATCH "/api/items/simulaciones/$(uri "$1")"
  ;;
# salidas <id>  ← [{"brazo":"A","item":"i1","texto":"…"}]  (o {"salidas":[…]}) — por brazo e ítem; el texto es lo que la persona compara
salidas)
  exige 1 "salidas <id>   < [{\"brazo\":\"A\",\"item\":\"i1\",\"texto\":\"…\",\"enlace\":\"https://…\"}]" "$@"
  vaciar_cola
  jq -c 'if type == "array" then {salidas: .} else . end' | escribir PATCH "/api/items/simulaciones/$(uri "$1")"
  ;;
# La corrida terminó: todas las salidas están y la persona puede calificar. Sin todas, 400.
lista)
  exige 1 "lista <id> [nota]" "$@"
  vaciar_cola
  jq -cn --arg n "${2:-}" '{estado:"calificando"} + (if $n == "" then {} else {nota:$n} end)' |
    escribir PATCH "/api/items/simulaciones/$(uri "$1")"
  ;;
# ─────────────────────────────────────────────────────────────────────────────
# LA CONSULTA — el human in the loop: la sesión pregunta, la persona contesta.
#
# Nace `abierta` con su queEs —de dónde salen los puntos y qué se hace con lo decidido, en
# una o dos frases— y sus puntos: cada uno con su título, qué cambia según la respuesta,
# las opciones vivas si las hay, la recomendación y su porqué breve. La persona ACEPTA,
# RECHAZA o PIDE MÁS CONTEXTO en cada recomendación EN LA WEB —rechazar dice qué va en su
# lugar; pedir contexto devuelve el punto a la sesión, que lo reescribe con `puntos` y lo
# pregunta de nuevo— y con la última decisión la consulta pasa sola a `contestada`; la
# sesión la lee con `respuestas`, aplica lo decidido —la ronda, las decisiones al libro— y
# la pasa a `aplicada`. La respuesta contesta 400 por esta puerta: es de la persona.
# ─────────────────────────────────────────────────────────────────────────────
consultas) leer "/api/items/consultas${1:+?estado=$(uri "${1:-}")}" ;;
# Las que la persona ya decidió enteras: lo que la sesión aplica.
contestadas) leer "/api/items/consultas?estado=contestada" ;;
# Lo que la persona ya dijo y espera a la sesión: las decididas enteras, para aplicar, y las
# abiertas donde pidió más contexto en algún punto, para reescribirlo. Es la tercera llamada
# del paso cero de /thinking: lo que la persona contestó mientras no había sesión.
decidido)
  {
    leer "/api/items/consultas?abiertos" | jq '[.items[] | . + {tipo: "consulta"}]'
    # El chequeo visual entra en la misma bandeja: lo que la persona aprobó mirando también
    # espera que la sesión lo tome, y leerlo en otro comando sería dejarlo sin mirar.
    leer "/api/items/chequeos?abiertos" | jq '[.items[] | . + {tipo: "chequeo"}]'
    # Y la consulta al cliente respondida entera: lo que contestó el cliente espera que la
    # sesión lo aplique, y la pregunta que pidió contexto, que la reescriba.
    leer "/api/items/consultas-cliente?abiertos" | jq '[.items[] | . + {tipo: "consulta-cliente"}]'
  } | jq -s 'add | [.[]
    | select(.estado == "contestada" or .estado == "contestado" or .estado == "respondida" or ((.pidenContexto // []) | length) > 0 or ((.delCliente // []) | length) > 0)
    | {id, tipo, estado, hilo, area, titulo, respuestas, faltan, pidenContexto, delCliente, actualizado}]
    | sort_by(if (.estado | startswith("contestad")) or .estado == "respondida" then 0 else 1 end)'
  ;;
# Lo que la persona dijo, punto por punto: aceptó o rechazó cada recomendación, pidió más
# contexto (`decision: "pide-contexto"`, con qué le faltó en `comentario`), o dijo que lo
# decide el cliente (`decision: "del-cliente"`): ese punto se lleva a una consulta al cliente
# y se enlaza con `puntos <id>` < {"puntos":[{"id":"p3","consultaCliente":"<id>"}]} — sin el
# enlace, la consulta no se aplica. `pedidos` son los pedidos de contexto que ese punto ya
# recibió y la sesión atendió reescribiéndolo; `llevadoA`, la consulta al cliente que lo tomó.
respuestas)
  exige 1 "respuestas <id>" "$@"
  leer "/api/items/consultas/$(uri "$1")" | jq '{estado, hilo, titulo, respuestas, faltan, pidenContexto, delCliente, puntos: [.puntos[] | {id, titulo, recomendacion: .propuesta, porque, decision: (.respuesta.decision // null), comentario: (.respuesta.texto // null), por: (.respuesta.autor // null), llevadoA: (.consultaCliente // null), pedidos: [(.pedidos // [])[] | .texto // ""]}]}'
  ;;
# Corregir o reescribir puntos mientras la consulta está abierta: por id el que se corrige,
# sin id el que nace entero. Es cómo se atiende un pedido de contexto: el punto reescrito
# vuelve a esperar a la persona, y su pedido queda en `pedidos`. El punto ya decidido, 400.
puntos)
  exige 1 "puntos <id>   < {\"puntos\":[{\"id\":\"p2\",\"queCambia\":\"…\",\"porque\":\"…\"}]}" "$@"
  vaciar_cola
  escribir PATCH "/api/items/consultas/$(uri "$1")"
  ;;
# La sesión tomó las respuestas: la consulta cierra. Sin contestar entera, 400.
aplicar)
  exige 1 "aplicar <id> [nota]" "$@"
  vaciar_cola
  jq -cn --arg n "${2:-}" '{estado:"aplicada"} + (if $n == "" then {} else {nota:$n} end)' |
    escribir PATCH "/api/items/consultas/$(uri "$1")"
  ;;
# ─────────────────────────────────────────────────────────────────────────────
# LA CONSULTA AL CLIENTE — lo que la persona le lleva al cliente, y lo que contestó.
#
# Para lo que decide la persona está la consulta; esto es para lo que decide el CLIENTE, con
# la persona de interlocutor. El orden es siempre el mismo:
#
#   1. `consulta-cliente <subarea>` la abre con sus `preguntas`, cada una con el mini análisis
#      con el que la persona asesora: el texto listo para mandar (`pregunta`, con las
#      palabras del cliente y en su idioma), qué frena (`bloquea`), por qué urge
#      (`urgencia`, y `para` con la fecha AAAA-MM-DD cuando la hay), las opciones con lo que
#      implica cada una, `recomiendo`, y qué recomendarle (`propuesta`) con su `porque`.
#   2. La persona se la lleva al cliente y la marca preguntada en la web —o la sesión con
#      `preguntada <id>` cuando sabe que ya salió—: pasa a «En manos del cliente».
#   3. La persona CARGA EN LA WEB lo que contestó el cliente, con sus palabras, la opción que
#      eligió y dónde lo dijo; o pide más contexto si el análisis no le alcanza para
#      asesorar. Con la última respuesta la consulta pasa sola a `respondida`.
#   4. `lo-que-contesto <id>` trae cada respuesta; la sesión la aplica —al libro del hilo,
#      al registro del cliente— y la cierra con `aplicar-cliente <id>`. La pregunta que pidió
#      contexto se reescribe con `preguntas <id>` y vuelve a la persona.
# ─────────────────────────────────────────────────────────────────────────────
consultas-cliente) leer "/api/items/consultas-cliente${1:+?estado=$(uri "${1:-}")}" ;;
# Lo que contestó el cliente, pregunta por pregunta: su texto, la opción que eligió por su
# nombre, dónde lo dijo y quién lo cargó; o el pedido de contexto con lo que faltó.
lo-que-contesto)
  exige 1 "lo-que-contesto <id>" "$@"
  leer "/api/items/consultas-cliente/$(uri "$1")" | jq '{estado, hilo, titulo, preguntadaAt, diasEnElCliente, para, respuestas, faltan, pidenContexto, preguntas: [.preguntas[] | . as $q | {id, titulo, recomendacion: .propuesta, decision: (.respuesta.decision // null), contesto: (.respuesta.texto // null), eligio: (if (.respuesta.opcion // null) == null then null else $q.opciones[.respuesta.opcion].titulo end), donde: (.respuesta.donde // null), cargo: (.respuesta.autor // null), pedidos: [(.pedidos // [])[] | .texto // ""]}]}'
  ;;
# Corregir o reescribir preguntas mientras está por preguntar: por id la que se corrige, sin
# id la que nace entera. Así se atiende un pedido de contexto. La ya contestada, 400.
preguntas)
  exige 1 "preguntas <id>   < {\"preguntas\":[{\"id\":\"p2\",\"bloquea\":\"…\",\"urgencia\":\"…\"}]}" "$@"
  vaciar_cola
  escribir PATCH "/api/items/consultas-cliente/$(uri "$1")"
  ;;
# La persona ya se la llevó al cliente: pasa a esperarlo y empieza a contar los días.
preguntada)
  exige 1 "preguntada <id> [nota]" "$@"
  vaciar_cola
  jq -cn --arg n "${2:-}" '{estado:"preguntada"} + (if $n == "" then {} else {nota:$n} end)' |
    escribir PATCH "/api/items/consultas-cliente/$(uri "$1")"
  ;;
# La sesión tomó lo que contestó el cliente: la consulta cierra. Sin respondida entera, 400.
aplicar-cliente)
  exige 1 "aplicar-cliente <id> [nota]" "$@"
  vaciar_cola
  jq -cn --arg n "${2:-}" '{estado:"aplicada"} + (if $n == "" then {} else {nota:$n} end)' |
    escribir PATCH "/api/items/consultas-cliente/$(uri "$1")"
  ;;
# ─────────────────────────────────────────────────────────────────────────────
# EL CHEQUEO VISUAL — lo que se aprueba MIRANDO, paso por paso.
#
# Para lo que se decide leyendo está la consulta; esto es para lo que se decide con los
# ojos: una PR que cambia lo que el usuario final ve. El orden es siempre el mismo:
#
#   1. `capturar <subarea> <archivo...>` sube las capturas y devuelve la RUTA de cada una.
#      Nunca se escribe una ruta a mano: la puerta del chequeo verifica que cada captura
#      nombrada exista como archivo de ese hilo, y contesta 400 con la que falta.
#   2. `chequeo <subarea>` lo abre con sus pasos, cada uno con la pantalla que se juzga
#      (`despues`), cómo se llega a ella (`origen` + `gesto`, desde el segundo paso), la
#      pantalla en la base cuando el paso cambia algo que ya existía (`antes` — vacía
#      cuando estrena), qué mirar (`queCuenta`), la recomendación y su porqué. Y de qué
#      RECORRIDO es cada pantalla: `flujos` arriba, o el `flujo` de cada paso. De qué
#      DISPOSITIVO son las capturas (`dispositivo`: escritorio | celular) lo deduce la
#      página de la imagen; se declara cuando la de escritorio es a página entera.
#   3. La persona ACEPTA, RECHAZA o PIDE MÁS CONTEXTO cada paso EN LA WEB, comparando el
#      antes con el después: lado a lado las de celular, y las de escritorio en el mismo
#      lugar con los botones «Antes» y «Después». Con la última decisión el chequeo pasa
#      solo a `contestado`.
#   4. `visto <id>` trae lo que dijo de cada paso; los rechazos son la ronda siguiente del
#      plan, sobre la misma rama. `aplicar-chequeo <id>` lo cierra.
#
# Las capturas de web se toman con Playwright y las de mobile del device o del simulador:
# de dónde salen es de la sesión, y el tipo es indiferente a eso.
# ─────────────────────────────────────────────────────────────────────────────
chequeos) leer "/api/items/chequeos${1:+?estado=$(uri "${1:-}")}" ;;
# Sube capturas al hilo y devuelve la ruta de cada una, que es con lo que el paso la nombra.
capturar)
  exige 2 "capturar <subarea> <archivo...>   (devuelve {archivo: ruta} para nombrarlas en los pasos)" "$@"
  hilo_captura="$1"
  shift
  # Cada archivo emite su par nombre → ruta y nada más: el `jq -s add` funde los pares en
  # un objeto, así que un dato suelto al lado quedaría como un archivo más cuya ruta es un
  # número — y eso es lo que el paso va a nombrar.
  for archivo in "$@"; do
    subir "$archivo" "linea=$hilo_captura" |
      jq -c --arg a "$archivo" '{(($a | split("/") | last)): .ruta}'
  done | jq -s 'add'
  ;;
# Lo que la persona dijo de cada paso: aceptó o rechazó lo que vio, o pidió más contexto
# (`decision: "pide-contexto"`, con qué le faltó en `comentario`). `pedidos` son los que ese
# paso ya recibió y la sesión atendió recapturándolo.
visto)
  exige 1 "visto <id>" "$@"
  leer "/api/items/chequeos/$(uri "$1")" | jq '{estado, hilo, titulo, flujos, respuestas, faltan, pidenContexto, pasos: [.pasos[] | {id, titulo, flujo, estrena, gesto, queCuenta, recomendacion: .propuesta, porque, decision: (.respuesta.decision // null), comentario: (.respuesta.texto // null), por: (.respuesta.autor // null), pedidos: [(.pedidos // [])[] | .texto // ""]}]}'
  ;;
# Corregir o agregar pasos mientras el chequeo está abierto: por id el que se corrige, sin
# id el que nace entero. Es cómo se atiende un pedido de contexto —el paso recapturado
# vuelve a esperar a la persona— y cómo se arregla un chequeo mal armado sin abrir otro que
# compita por la misma decisión. El paso ya decidido, 400.
pasos)
  exige 1 "pasos <id>   < {\"pasos\":[{\"id\":\"p2\",\"despues\":\"<ruta>\",\"queCuenta\":\"…\"}]}" "$@"
  vaciar_cola
  escribir PATCH "/api/items/chequeos/$(uri "$1")"
  ;;
# La sesión tomó lo aprobado: el chequeo cierra. Sin decidir entero, 400.
aplicar-chequeo)
  exige 1 "aplicar-chequeo <id> [nota]" "$@"
  vaciar_cola
  jq -cn --arg n "${2:-}" '{estado:"aplicado"} + (if $n == "" then {} else {nota:$n} end)' |
    escribir PATCH "/api/items/chequeos/$(uri "$1")"
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
  exige 1 "accion <subarea>   (cerrado: el trabajo por hacer es un plan)" "$@"
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
  echo "  bitacora-api plan <subarea> <<< '{\"titulo\":\"…\",\"cierraEn\":\"…\",\"cuerpo\":{\"es\":\"…\"}}'" >&2
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
editar-subarea | editar-hilo | editar-linea)
  exige 1 "editar-subarea <slug>   < {\"estado\":\"resuelta\"} · {\"area\":\"infra\"} · {\"piso\":true}" "$@"
  vaciar_cola
  escribir PATCH "/api/lineas/$(uri "$1")"
  ;;
fusionar)
  exige 1 "fusionar <slug-que-desaparece>   < {\"en\":\"el-que-queda\"}" "$@"
  vaciar_cola
  escribir POST "/api/lineas/$(uri "$1")/fusionar"
  ;;
# abrir-flujo  ← {"nombre":"…","queEs":"…","categoria":"runtime|editorial|ciclo-de-vida|migracion",
#                 "pasos":[{"etapa":"…","actor":"…","que":"…","pieza":"<slug del stack>","detalle":"…"}]}
# Los PASOS son el flujo: `que` es la frase que se entiende sin ser técnico y `detalle` lo que
# se abre debajo. La `etapa` agrupa los pasos seguidos que la comparten.
abrir-flujo)
  vaciar_cola
  escribir POST "/api/flujos"
  ;;
editar-flujo)
  exige 1 "editar-flujo <slug>   < {\"estado\":\"construido\"} · {\"sumarStack\":[\"algolia\"]} · {\"pasos\":[{\"que\":\"…\"}]}" "$@"
  vaciar_cola
  escribir PATCH "/api/flujos/$(uri "$1")"
  ;;
# anotar-pieza  ← {"nombre":"…","responsabilidad":"…","donde":"…","comoSeEntra":"…"}
# Anota una fuente, o corrige la ficha de la que ya estaba. Upsert por slug, como el stack:
# el espejo se conserva — lo escribe `sincronizada` y no la ficha.
#
#   bitacora-api anotar-fuente <<'JSON'
#   {"nombre":"El excel de atributos",
#    "queEs":"El registro donde el cliente fija el alcance atributo por atributo",
#    "clase":"hoja","procedencia":"google-sheets","producidaPor":"Fran McCann",
#    "lado":"cliente","fecha":"2026-09-08","vigencia":"viva",
#    "url":"https://docs.google.com/spreadsheets/d/1Qc.../edit","ref":"1Qc...",
#    "tags":["algolia","modelo"],"nota":"la hoja que importa es 1-attribute-register"}
#   JSON
#
# `clase`: documento · hoja · canal · tablero · diseno · pagina
# `procedencia`: google-sheets · google-docs · slack · jira · figma · miro · email · drive · mano
# `lado`: cliente · equipo · nuestro · proveedor   ·   `vigencia`: viva · fechada
anotar-fuente)
  vaciar_cola
  escribir POST "/api/fuentes"
  ;;
# Corrige una fuente: su `queEs`, su fecha, sus tags, la que la superó. `tags` reemplaza la
# lista entera y `sumarTags` agrega a la que había; la cadena vacía borra `superadaPor`,
# `url`, `ref` y `nota`.
#
#   bitacora-api editar-fuente attribute-register <<'JSON'
#   {"sumarTags":["plp-taxonomia"],"fecha":"2026-09-09"}
#   JSON
editar-fuente)
  exige 1 "editar-fuente <slug>   < {\"sumarTags\":[\"algolia\"]}" "$@"
  vaciar_cola
  escribir PATCH "/api/fuentes/$(uri "$1")"
  ;;
# Deja anotada la copia que se acaba de tomar: sube el archivo, calcula su huella y estampa
# el espejo. Con una fecha detrás mueve además la de la fuente, para la viva cuyo original
# se editó.
#
#   bitacora-api sincronizada attribute-register ~/Downloads/_source.xlsx 2026-09-09
sincronizada)
  exige 2 "sincronizada <slug> <archivo> [fecha AAAA-MM-DD]" "$@"
  fuente_slug="$1"
  archivo_espejo="$2"
  [ -f "$archivo_espejo" ] || { echo "No existe $archivo_espejo" >&2; exit 1; }
  ruta_espejo="$(subir "$archivo_espejo" "fuente=$fuente_slug" | jq -r '.ruta')"
  hash_espejo="$(shasum -a 1 "$archivo_espejo" | cut -d" " -f1)"
  jq -cn --arg r "$ruta_espejo" --arg h "$hash_espejo" --arg f "${3:-}" \
    '{ruta:$r, hash:$h} + (if $f == "" then {} else {fecha:$f} end)' |
    escribir POST "/api/fuentes/$(uri "$fuente_slug")/espejo"
  ;;
# Refresca las vivas: baja el original por su procedencia, compara la huella y estampa el
# espejo. Sin slug recorre las que esperan refresco (`por-sincronizar`); con slug, esa
# fuente aunque esté al día. Lo corre /thinking en su paso cero.
#
# Sheets y Docs se bajan por el export público del documento con su `ref`, sin credencial:
# la única condición es que esté compartido por enlace, y cuando Google contesta una página
# en lugar del archivo el renglón lo dice con qué pedir. La huella decide: igual a la del
# espejo, la copia está al día y se re-estampa la fecha; distinta, sube la copia con el
# nombre del espejo anterior y la fecha de la fuente pasa a la de hoy. Las demás
# procedencias las refresca la skill del perfil que tiene el acceso —/slack, /jira,
# /figma— y el renglón la nombra; una fechada se refresca cuando su autor manda otra.
#
#   bitacora-api refrescar                     # las vivas que esperan refresco
#   bitacora-api refrescar attribute-register  # esa, aunque esté al día
refrescar)
  if [ -n "${1:-}" ]; then
    lista_refresco="$(leer "/api/fuentes/$(uri "$1")" | jq -c '[.]')"
  else
    lista_refresco="$(leer "/api/fuentes?vigencia=viva" | jq -c '[.[] | select(.esperaRefresco)]')"
  fi
  al_dia=0
  cambiaron=0
  sin_acceso=0
  sin_acceso_lista=""
  por_su_skill=0
  hoy_refresco="$(date +%F)"
  carpeta_refresco="$(mktemp -d)"
  while IFS= read -r ficha_refresco; do
    slug_refresco="$(jq -r '.slug' <<<"$ficha_refresco")"
    procedencia_refresco="$(jq -r '.procedencia' <<<"$ficha_refresco")"
    ref_refresco="$(jq -r '.ref // ""' <<<"$ficha_refresco")"
    url_refresco="$(jq -r '.url // ""' <<<"$ficha_refresco")"
    hash_previo="$(jq -r '.espejo.hash // ""' <<<"$ficha_refresco")"
    adjunto_previo="$(jq -r '.espejo.adjunto // ""' <<<"$ficha_refresco")"
    # El handle sale de la ficha, o de la dirección cuando la ficha no lo trae.
    [ -z "$ref_refresco" ] && ref_refresco="$(sed -n 's|.*/d/\([^/?#]*\).*|\1|p' <<<"$url_refresco")"
    case "$procedencia_refresco" in
    google-sheets)
      export_refresco="https://docs.google.com/spreadsheets/d/$ref_refresco/export?format=xlsx"
      nombre_refresco="_source.xlsx"
      ;;
    google-docs)
      export_refresco="https://docs.google.com/document/d/$ref_refresco/export?format=txt"
      nombre_refresco="$slug_refresco.txt"
      ;;
    slack)
      por_su_skill=$((por_su_skill + 1))
      echo "  →  $slug_refresco (slack): la refresca /slack —los archivos del canal desde el último refresco— y después \`sincronizada $slug_refresco <archivo>\`"
      continue
      ;;
    jira)
      por_su_skill=$((por_su_skill + 1))
      echo "  →  $slug_refresco (jira): la refresca /jira —los adjuntos del proyecto— y después \`sincronizada $slug_refresco <archivo>\`"
      continue
      ;;
    figma)
      por_su_skill=$((por_su_skill + 1))
      echo "  →  $slug_refresco (figma): la refresca /figma con su cupo mensual y después \`sincronizada $slug_refresco <captura>\`"
      continue
      ;;
    *)
      por_su_skill=$((por_su_skill + 1))
      echo "  →  $slug_refresco ($procedencia_refresco): la refresca la persona: cuando llegue otra versión, se anota como fuente nueva que supera a esta"
      continue
      ;;
    esac
    # La copia nueva lleva el nombre de la anterior, así ocupa su misma ruta.
    [ -n "$adjunto_previo" ] && nombre_refresco="${adjunto_previo##*/}"
    archivo_refresco="$carpeta_refresco/$nombre_refresco"
    respuesta_refresco="$(curl -sSL --max-time 120 -o "$archivo_refresco" -w '%{http_code} %{content_type}' "$export_refresco" 2>/dev/null || echo "000")"
    case "$respuesta_refresco" in
    2*html* | 3* | 4* | 5* | 000*)
      sin_acceso=$((sin_acceso + 1))
      sin_acceso_lista="$sin_acceso_lista $slug_refresco"
      echo "  ✗  $slug_refresco: sin acceso al original ($export_refresco). Pedile a quien es dueño del documento que lo comparta por enlace —«Cualquier persona con el enlace», como lector— y volvé a correr \`refrescar $slug_refresco\`."
      continue
      ;;
    esac
    hash_nuevo="$(shasum -a 1 "$archivo_refresco" | cut -d" " -f1)"
    if [ "$hash_nuevo" = "$hash_previo" ] && [ -n "$adjunto_previo" ]; then
      if jq -cn --arg r "$adjunto_previo" --arg h "$hash_nuevo" '{ruta:$r, hash:$h}' |
        escribir POST "/api/fuentes/$(uri "$slug_refresco")/espejo" >/dev/null; then
        al_dia=$((al_dia + 1))
        echo "  ✓  $slug_refresco: al día — la copia coincide con el original"
      fi
    else
      if ruta_refresco="$(subir "$archivo_refresco" "fuente=$slug_refresco" | jq -r '.ruta')" &&
        jq -cn --arg r "$ruta_refresco" --arg h "$hash_nuevo" --arg f "$hoy_refresco" '{ruta:$r, hash:$h, fecha:$f}' |
        escribir POST "/api/fuentes/$(uri "$slug_refresco")/espejo" >/dev/null; then
        cambiaron=$((cambiaron + 1))
        echo "  ↻  $slug_refresco: cambió — espejo nuevo en $ruta_refresco, fecha $hoy_refresco"
      fi
    fi
  done < <(jq -c '.[]' <<<"$lista_refresco")
  rm -rf "$carpeta_refresco"
  echo "Fuentes: $al_dia al día · $cambiaron cambiaron · $sin_acceso sin acceso${sin_acceso_lista:+ (${sin_acceso_lista# })} · $por_su_skill por su skill o su autor"
  ;;
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
# abrir-area  ← {"nombre":"…"}   ·  nace vacía; la persona le abre sub-áreas en la web
abrir-area)
  vaciar_cola
  escribir POST "/api/areas"
  ;;
# El renombre toca un registro y ninguna sub-área: el slug es la dirección, el nombre lo que se lee.
editar-area)
  exige 1 "editar-area <slug>   < {\"nombre\":\"…\"} · {\"orden\":2}" "$@"
  vaciar_cola
  escribir PATCH "/api/areas/$(uri "$1")"
  ;;
seccion)
  vaciar_cola
  escribir POST "/api/secciones"
  ;;
# Las instrucciones del ciclo se escriben ENTERAS y en markdown crudo por stdin: es un
# documento y se reemplaza. La primera vez crea la sección reservada `instrucciones`.
#   bitacora-api escribir-instrucciones < instrucciones.md
# Con `--json` el stdin es el JSON de la puerta ({"cuerpo":{"es":"…","en":"…"},"queEs":"…"}),
# para el proyecto que las escribe en dos idiomas.
# ─────────────────────────────────────────────────────────────────────────────
# EL CATÁLOGO DE SKILLS — se mantiene solo, con UNA llamada determinística.
#
# Recorre las carpetas de skills que esta sesión ve —las del repo, las del perfil y las
# del plugin instalado—, manda el hash de cada SKILL.md, y sube el texto SOLO de las que
# el servidor no conoce o que cambiaron. Depende únicamente de los archivos del disco: dos
# sesiones paradas en el mismo proyecto mandan lo mismo.
#
# La corre la skill /skills del plugin, invocada a mano. Su última línea dice qué cambió,
# y es su plan de trabajo: el texto crudo se actualiza solo, y lo editorial —contar la
# nueva, reescribir la nota vieja, sacar la retirada— es lo que /skills hace después.
sincronizar-skills)
  vaciar_cola
  # Las tres casas, en el orden en que el catálogo las agrupa. La del plugin sale del
  # directorio de este mismo archivo, así la versión instalada se describe a sí misma.
  # El directorio del plugin instalado, resuelto desde el shim: un symlink relativo se
  # resolvería contra el cwd y saltearía esa casa en silencio, así que se sigue entero.
  PLUGIN_SH="${BASH_SOURCE[0]}"
  while [ -L "$PLUGIN_SH" ]; do
    destino="$(readlink "$PLUGIN_SH")"
    case "$destino" in
    /*) PLUGIN_SH="$destino" ;;
    *) PLUGIN_SH="$(dirname "$PLUGIN_SH")/$destino" ;;
    esac
  done
  PLUGIN_DIR="$(cd "$(dirname "$PLUGIN_SH")" && pwd)"
  HOME_CLAUDE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  # Qué más hay en la carpeta además del instructivo: sus scripts, sus referencias, sus
  # plantillas. Es meta información de consulta —el catálogo dice si una skill es un texto o
  # un texto con herramientas colgando— y cuesta lo mismo que la lista que ya viaja.
  #
  # Solo el primer nivel, y el directorio se nombra con su barra: lo que se quiere saber es
  # qué trae, y una skill que arrastra un `node_modules` o un sitio compilado contestaría
  # esa pregunta con mil archivos que nadie va a leer.
  archivos_de() {
    (
      cd "$1" 2>/dev/null || return 0
      for entrada in *; do
        [ -e "$entrada" ] || continue
        [ "$entrada" = "SKILL.md" ] && continue
        if [ -d "$entrada" ]; then printf '%s/\n' "$entrada"; else printf '%s\n' "$entrada"; fi
      done | LC_ALL=C sort | head -24
    ) | jq -R -s -c 'split("\n") | map(select(length > 0))'
  }
  # Las casas del inventario. La del repo es donde estás parado, y un tenant cuyo trabajo
  # vive en varias carpetas suma las otras como argumentos: el catálogo es del proyecto de
  # la bitácora, y un proyecto de la bitácora puede tener más de un repo en el disco.
  casas=("repo:$PWD/.claude/skills")
  for otro in "$@"; do casas+=("repo:${otro%/}/.claude/skills"); done
  casas+=("perfil:$HOME_CLAUDE/skills" "plugin:$PLUGIN_DIR/skills")
  inventario="$(
    for casa in "${casas[@]}"; do
      procedencia="${casa%%:*}"
      raiz="${casa#*:}"
      [ -d "$raiz" ] || continue
      for md in "$raiz"/*/SKILL.md; do
        [ -f "$md" ] || continue
        jq -cn --arg n "$(basename "$(dirname "$md")")" --arg p "$procedencia" \
          --arg r "$(printf '%s' "${md%/SKILL.md}" | sed "s#^$HOME#~#")" \
          --arg h "$(shasum -a 1 "$md" | cut -c1-16)" \
          --argjson a "$(archivos_de "${md%/SKILL.md}")" \
          '{nombre:$n, procedencia:$p, ruta:$r, hash:$h, archivos:$a}'
      done
    done | jq -cs '
      # Un nombre, una skill: la primera casa gana, que es el orden en que el harness la
      # resuelve —la del proyecto le gana a la del root—. Sin esto, una skill con el mismo
      # nombre en el repo y en el perfil se guardaría con el texto de la que NO se invoca.
      reduce .[] as $s ({}; if has($s.nombre) then . else . + {($s.nombre): $s} end)
      | {skills: [.[]]}
    '
  )"
  respuesta="$(printf '%s' "$inventario" | escribir POST "/api/skills/sincronizar")" || exit 1
  # Lo que el servidor pidió sube entero, una llamada por skill: son pocas y solo cuando
  # cambian. La ruta que devolvió es la misma que se mandó, así que el archivo se reencuentra.
  printf '%s' "$respuesta" | jq -c '.subir[]?' | while IFS= read -r pendiente; do
    nombre="$(printf '%s' "$pendiente" | jq -r .nombre)"
    procedencia="$(printf '%s' "$pendiente" | jq -r .procedencia)"
    ruta="$(printf '%s' "$pendiente" | jq -r .ruta)"
    archivo="$(printf '%s' "$ruta" | sed "s#^~#$HOME#")/SKILL.md"
    [ -f "$archivo" ] || continue
    jq -n --arg p "$procedencia" --arg r "$ruta" \
      --arg h "$(shasum -a 1 "$archivo" | cut -c1-16)" --rawfile c "$archivo" \
      --argjson a "$(archivos_de "$(dirname "$archivo")")" \
      '{procedencia:$p, ruta:$r, hash:$h, cuerpo:$c, archivos:$a}' |
      escribir PUT "/api/skills/$(uri "$nombre")" >/dev/null ||
      # Una que el servidor rechaza no se lleva puesta la sincronización entera: se dice
      # cuál fue y las demás siguen subiendo.
      echo "  ✗ /$nombre quedó sin subir" >&2
  done
  # La línea que /coding pega en su reporte. La arma el servidor, así el cliente, la web y
  # el reporte dicen lo mismo con las mismas palabras.
  printf '%s' "$respuesta" | jq -r '"Skills (\(.vistas)): " + .resumen'
  ;;
# La foto nueva del estado de un área, y la corrección de la vigente.
#
# `escribir-estado` toma una foto: el cuerpo con sus cinco secciones —# Dónde estamos ·
# # El mapa · # En vuelo · # Lo que sigue · # Lo que espera de otros—, el `hito` que la
# produjo (la firma de un plan, una decisión del cliente, una fuente que movió el terreno),
# el `plan` cuya firma fue el hito cuando lo hubo, y los `diagramas` compilados con
# `npm run -s diagramas`. El servidor cobra el contrato —«Dónde estamos» sin código y en
# cuatro oraciones, «El mapa» con su dibujo— y sella las fuentes del área; la foto anterior
# queda como historia. `editar-estado` corrige la vigente sin abrir versión: una frase, un
# diagrama recompilado, el hito, o la capa traducida con la huella del original.
#   bitacora-api escribir-estado <area> < estado.json
#   bitacora-api editar-estado <area> <<< '{"hito":"…"}'
escribir-estado)
  exige 1 "escribir-estado <area>   < {\"cuerpo\":{\"es\":\"# Dónde estamos\\n…\"},\"hito\":\"…\",\"plan\":\"<id>\",\"diagramas\":[…]}" "$@"
  vaciar_cola
  escribir PUT "/api/areas/$(uri "$1")/estado"
  ;;
editar-estado)
  exige 1 "editar-estado <area>   < {\"cuerpo\":…} · {\"hito\":\"…\"} · {\"traduccion\":{\"idioma\":\"en\",\"cuerpo\":\"…\",\"hash\":\"…\"}}" "$@"
  vaciar_cola
  escribir PATCH "/api/areas/$(uri "$1")/estado"
  ;;
escribir-instrucciones)
  vaciar_cola
  if [ "${1:-}" = "--json" ]; then
    escribir PUT "/api/instrucciones"
  else
    cuerpo_md="$(cat)"
    if [ -z "$(printf '%s' "$cuerpo_md" | tr -d '[:space:]')" ]; then
      echo "escribir-instrucciones lee el markdown entero por stdin:  bitacora-api escribir-instrucciones < instrucciones.md" >&2
      echo "  Secciones que las skills esperan: Dónde se para cada sesión · La rama y la PR · Antes de commitear · La review · La facturación · Las fuentes · Los registros · Las skills" >&2
      exit 1
    fi
    printf '%s' "$cuerpo_md" | jq -Rs '{cuerpo: .}' | escribir PUT "/api/instrucciones"
  fi
  ;;
escribir-dominio)
  vaciar_cola
  if [ "${1:-}" = "--json" ]; then
    escribir PUT "/api/dominio"
  else
    cuerpo_md="$(cat)"
    if [ -z "$(printf '%s' "$cuerpo_md" | tr -d '[:space:]')" ]; then
      echo "escribir-dominio lee el markdown entero por stdin:  bitacora-api escribir-dominio < dominio.md" >&2
      echo "  Va el NEGOCIO del cliente, con su vocabulario: a qué se dedica · Qué vende · A quién · Cómo llega a sus clientes · Qué lo distingue" >&2
      exit 1
    fi
    printf '%s' "$cuerpo_md" | jq -Rs '{cuerpo: .}' | escribir PUT "/api/dominio"
  fi
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
  # rato  ← {"tarea":"…","tareaEn":"…","reloj":"1:30","epica":"…","epicaNombre":"…",
  #          "jira":{"clave":"…","url":"…"},"plan":"<id del plan>","pr":"https://…/pull/12"}
  # `tarea` y `reloj` son el piso. `tareaEn` es la fila en inglés, la que se carga;
  # `epica` y `epicaNombre` el código y el nombre bajo el que el panel lo agrupa;
  # `plan` y `pr` dicen de dónde salió: el banco los enlaza. Las instrucciones del
  # tenant dicen cuáles de estos van siempre y con qué reloj.
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
# Abrir la sub-área que falta: el lugar que ninguna de las que hay aloja. Lo hace la sesión
# que lo descubre escribiendo, y lo dice en su reporte; en la web el mismo gesto vive en la
# página del área.
abrir-subarea | abrir-hilo | abrir-linea)
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

El sistema del proyecto — la tríada, las instrucciones y las skills. Primera lectura al llegar:
  bitacora-api contexto                     (el dominio + el glosario + el stack + los flujos + las fuentes + las instrucciones, de una)
  bitacora-api dominio                      (de qué vive el cliente, con sus palabras; 404 si no está escrito)
  bitacora-api instrucciones                (cómo se corre el ciclo del encargo acá, en markdown crudo; 404 si no están cargadas)
  bitacora-api skills                       (las herramientas a mano: las del repo, las del perfil y las del plugin, con qué hace cada una)
  bitacora-api skill <nombre>               (una entera: cómo se la cuenta, con qué se encadena y su SKILL.md)
  bitacora-api nota-skill <nombre>          {"paraQue":"…","cuando":"…","deja":"…","ojo":"…"}
        la skill contada para una persona: lo único del catálogo que se escribe
  bitacora-api sacar-skill <nombre>         (la que se retiró de verdad: sale del catálogo — dueño)
  bitacora-api flujos                       · bitacora-api flujo <slug>
  bitacora-api stack [flujos]               · bitacora-api pieza <slug|alias>
  bitacora-api glosario                     · bitacora-api termino <palabra>
  bitacora-api accesos                      (las direcciones de afuera, con qué se entra a cada una)
  bitacora-api fuentes [tema] [clase]       (lo que el cliente entregó, en el orden que dice cuál MANDA:
                                             las vivas del cliente arriba, las fechadas por fecha, las superadas al pie)
  bitacora-api fuente <slug>                (una entera, con su espejo y de cuándo es)
  bitacora-api por-sincronizar              (las vivas cuya copia quedó vieja, con su handle y su huella)
  bitacora-api refrescar [slug]             (baja las vivas por su procedencia, compara la huella y estampa el espejo;
                                             la que quedó sin acceso la dice con qué pedir — lo corre /thinking al arrancar)

El trabajo (en el taller el lugar se llama SUB-ÁREA —antes «hilo»—; la API lo guarda como `lineas`):
  bitacora-api abrir [destino]              (el tablero en tu navegador, sin login: enlace fresco de un solo uso;
                                             con la ruta o el enlace de una pieza, abre esa página)
  bitacora-api tablero                      (las sub-áreas con su área y sus ítems, las áreas, lo pendiente por escritorio, la tríada contada)
  bitacora-api bandeja                      (sin -p: las consultas que esperan tu respuesta y los planes entregados, en curso y encargados de TODOS los proyectos)
  bitacora-api encargados · en-curso · entregados   (el ciclo del encargo, por escritorio; cada plan con su sub-área y su área)
  bitacora-api subareas                     (= hilos = lineas: los tres nombres llegan al mismo lugar)
  bitacora-api subarea <slug|alias>         (= hilo = linea)
  bitacora-api adaptacion                   (lo que a este proyecto le falta adaptar cuando el modelo cambió, con sus señales)
  bitacora-api adaptado <clave>             (cierra la adaptación; 400 con lo que falta si el material todavía no está)
  bitacora-api areas                        (los mundos del proyecto, con sus sub-áreas)
  bitacora-api area <slug>                  (un área con las sub-áreas que viven ahí y su `estado` resumido —la foto vigente,
                                             su panorama y lo que se firmó y cambió desde que se tomó—; `areas <slug>` es lo mismo)
  bitacora-api estado <area> [--version N]  (el estado del área entero: la foto vigente —o una anterior— con sus cinco secciones,
                                             su hito, su cadena de anteriores y `desde`: la señal de que toca renovarla)
  bitacora-api buscar <texto>
  bitacora-api documento <linea|seccion|flujo> <contenedor> <slug>
  bitacora-api secciones · bitacora-api horas (dueño) · bitacora-api adjuntos [linea] · bitacora-api reviews
  bitacora-api publicados                   (lo que está afuera hoy, con el enlace de cada uno)
  bitacora-api de-la-subarea <subarea> <tipo>  (= del-hilo: lo que cuelga de una sub-área, de un tipo)
  bitacora-api tipo <tipo> [estado]         (todos los del proyecto, cruzando sub-áreas)
  bitacora-api item <tipo> <id>             (uno entero: su cuerpo y cómo se movió)
  bitacora-api abiertos <tipo>              (los que quedaron sin cerrar; el análisis y la decisión no tienen)
        tipo = analisis | planes | bugs | client-reports | decisiones | simulaciones | consultas | consultas-cliente | chequeos
  bitacora-api simulaciones [estado]        (los experimentos del proyecto; `calificando` son los que esperan a la persona)
  bitacora-api consultas [estado]           (lo que la sesión le preguntó a la persona; `abierta` espera respuestas)
  bitacora-api chequeos [estado]            (lo que se aprueba MIRANDO; `abierto` espera los ojos de la persona)
  bitacora-api capturar <subarea> <archivo...> (sube las capturas y devuelve la ruta de cada una)
  bitacora-api consultas-cliente [estado]   (lo que se le lleva al cliente; `por-preguntar` espera que se lo lleves, `preguntada` espera al cliente)
  bitacora-api lo-que-contesto <id>         (lo que contestó el cliente, pregunta por pregunta: su texto, la opción que eligió y dónde lo dijo)
  bitacora-api preguntas <id>               < {"preguntas":[{"id":"p1","urgencia":"…"}]}   (corregir o reescribir mientras está por preguntar)
  bitacora-api preguntada <id> [nota]       (ya se la llevaste al cliente: pasa a esperarlo)
  bitacora-api aplicar-cliente <id> [nota]  (la sesión tomó lo que contestó el cliente: la consulta cierra)
  bitacora-api visto <id>                   (lo que la persona dijo de cada paso del chequeo)
  bitacora-api pasos <id>                   < {"pasos":[{"id":"p2","despues":"<ruta>","queCuenta":"…"}]}
  bitacora-api aplicar-chequeo <id> [nota]  (la sesión tomó lo aprobado: el chequeo cierra)
  bitacora-api decidido                     (lo que la persona ya dijo y espera a la sesión: las decididas enteras, y las abiertas con puntos que pidieron más contexto)
  bitacora-api contestadas                  (las que la persona ya decidió enteras: lo que la sesión tiene que aplicar)
  bitacora-api respuestas <id>              (punto por punto: la recomendación, si la persona la aceptó, la rechazó o pidió más contexto, y su comentario)
  bitacora-api por-traducir [idioma]        (documentos, ítems, fichas y el estado vigente de cada área: lo que falta y lo que quedó viejo,
                                             cada lista con su puerta de vuelta — el estado vuelve por editar-estado con `traduccion`)

Escritura (el cuerpo JSON entra por stdin):
  bitacora-api analisis <subarea>              {"titulo":"…","queEs":"…","cuerpo":{"es":"# …"}}
  bitacora-api plan <subarea>                  {"titulo":"…","cierraEn":"…","cuerpo":{"es":"# …"},"flujos":["…"]}
        con "estado":"encargado" nace como ENCARGO: el cuerpo es el handoff y cierraEn el criterio de terminado;
        el servidor exige ocho secciones en el cuerpo —# Qué cambia (el TL;DR para la persona: de dos a cuatro oraciones, sin código) · # Tarea · # La idea · # Destino · # Contexto · # Patrón a seguir · # Alcance · # Fuera de alcance— y el queEs, la bajada en una línea
  bitacora-api bug <subarea>                   {"titulo":"…","cuerpo":{"es":"# Qué se observa\n…\n\n# Dónde\n…\n\n# Cómo se reproduce\n…"},"flujos":["…"]}
        `flujos` son los recorridos que el ítem corta mientras está abierto: de ahí sale la madurez del flujo
  bitacora-api client-report <subarea>         {"titulo":"…","cuerpo":{"es":"# …"}}
  bitacora-api simulacion <subarea>            {"titulo":"…","hipotesis":"…","criterioExito":"…",
                                             "brazos":[{"clave":"A","nombre":"…","comoCorre":"…"},{"clave":"B","nombre":"…"}],
                                             "muestra":[{"clave":"i1","nombre":"…","queEs":"…"}],
                                             "rubrica":[{"clave":"fidelidad","nombre":"…","escala":{"min":1,"max":5},"mejor":"alto","ancla":"…"}],
                                             "esperados":[{"texto":"…"}],"cuerpo":{"es":"# El diseño\n…"}}
        nace `disenada`; la persona APRUEBA en la web (fija el diseño); después la sesión corre
  La simulación — lo de la sesión (azúcar sobre mover simulaciones; el servidor cobra en cada puerta):
  bitacora-api correr <id> [nota]           → corriendo (sin aprobar, 400)
  bitacora-api brazos <id>                  [{"clave":"A","enlaces":{"compare":"https://…"},"consumo":{"preciosDe":"AAAA-MM-DD","modelos":[…]}}]
                                            (por clave: los enlaces se funden, el consumo se suma como tanda)
  bitacora-api salidas <id>                 [{"brazo":"A","item":"i1","texto":"lo que produjo","enlace":"https://…"}]
                                            (por brazo e ítem; el texto es lo que la persona compara a ciegas en la web)
  bitacora-api faltan <id>                  (qué pares brazo/ítem siguen sin salida)
  bitacora-api lista <id> [nota]            → calificando: la corrida terminó y la persona puede calificar (faltan salidas, 400)
  bitacora-api calificacion <id>            (lo que la persona decidió: matriz, elecciones, esperados con su cumplido, veredicto)
        calificar, elegir, marcar esperados y concluir son DE LA PERSONA y se hacen en la web: por esta puerta, 400
  bitacora-api consulta <subarea>              {"titulo":"…","queEs":"de dónde salen los puntos y qué se hace con lo decidido, en una o dos frases",
                                             "puntos":[{"titulo":"…","queCambia":"qué se decide y qué cambia con cada respuesta",
                                                        "opciones":[{"titulo":"…","implica":"…"}],
                                                        "propuesta":"la recomendación: lo que la sesión haría","porque":"su porqué, en una o dos frases"}]}
        el human in the loop: nace `abierta`; la persona ACEPTA, RECHAZA, PIDE MÁS CONTEXTO o dice que LO DECIDE EL CLIENTE en cada recomendación EN LA WEB y pasa sola a `contestada`; el punto `del-cliente` se lleva a una consulta al cliente y se enlaza con `puntos <id>` < {"puntos":[{"id":"p3","consultaCliente":"<id>"}]}
  bitacora-api consulta-cliente <subarea>      {"titulo":"…","queEs":"de dónde salen las preguntas y qué se hace con lo que conteste, en una o dos frases",
                                             "preguntas":[{"titulo":"la pregunta en una línea","pregunta":"el texto listo para mandarle, con sus palabras y en su idioma",
                                                           "bloquea":"qué trabajo queda frenado mientras no conteste","urgencia":"por qué urge","para":"AAAA-MM-DD",
                                                           "opciones":[{"titulo":"…","implica":"qué implica elegirla"}],"recomiendo":0,
                                                           "propuesta":"qué le recomendarías al cliente","porque":"su porqué, en una o dos frases"}]}
        lo que decide el CLIENTE, con la persona de interlocutor: nace `por-preguntar`; la persona se la lleva, la marca preguntada
        y CARGA EN LA WEB lo que contestó el cliente, con sus palabras; pasa sola a `respondida` con la última respuesta
  bitacora-api chequeo <subarea>               {"titulo":"…","queEs":"qué cambió y qué se le pide al que aprueba","flujos":["<slug-del-recorrido>"],
                                             "pasos":[{"titulo":"la pantalla o el momento","queCuenta":"qué mirar, desde el usuario que usa la pantalla",
                                                       "despues":"<ruta de la captura como queda>","antes":"<ruta en la base — vacía cuando estrena>",
                                                       "origen":"<ruta de la pantalla desde la que se viene>","gesto":"qué se tocó para llegar acá",
                                                       "flujo":"<slug — cuando el chequeo cruza más de un recorrido>",
                                                       "propuesta":"la recomendación","porque":"su porqué, en una frase"}]}
        lo que se aprueba MIRANDO: las capturas suben antes con `capturar` y el paso las nombra por su ruta, que la puerta verifica;
        `origen` y `gesto` van desde el segundo paso, y la persona aprueba cada uno EN LA WEB comparando el antes con el después
  bitacora-api puntos <id>                  {"puntos":[{"id":"p2","queCambia":"…","porque":"…"},{"titulo":"…","queCambia":"…","propuesta":"…","porque":"…"}]}
        corregir por id o sumar sin id mientras está abierta; reescribir el punto que pidió contexto lo devuelve a la persona. El ya decidido, 400
  bitacora-api aplicar <id> [nota]          → aplicada: la sesión tomó lo decidido (la ronda, las decisiones al libro); sin decidir entera, 400
        la respuesta es DE LA PERSONA y se escribe en la web: por esta puerta, 400
  bitacora-api traducir-item <tipo> <id>    {"traduccion":{"idioma":"en","cuerpo":"…","hash":"…"}}
  bitacora-api mover <tipo> <id>            {"estado":"hecho","nota":"cómo cerró"}
                                            · {"hilo":"el-que-corresponde"} lo muda de hilo (acepta el alias)
                                            · {"tambienEn":["mobile"]} la muestra además desde esas sub-áreas (la lista entera; [] la deja en un solo lugar)
        la decisión NO tiene escritorios: nace tomada y se corrige con corregir
  bitacora-api fijar <tipo> <id>            la clava arriba de su sub-área: es la pieza por la que la sub-área abre, en su página y en el menú
  bitacora-api soltar <tipo> <id>           la devuelve al orden del trabajo (azúcar sobre mover con {"fijado":true|false})
  El ciclo del encargo (azúcar sobre mover planes; el estado lo pone el verbo):
  bitacora-api tomar <id> [nota]            → en-curso; la nota (y ficha.destino) es el worktree o la copia que lo tiene
  bitacora-api entregar <id>                {"reporte":{"es":"## Hecho\n…"},"ficha":{"pr":"…","rama":"…","review":"…"},"consumo":{…},"nota":"…"} → entregado
                                            (el consumo son los tokens de cada motor con su precio de ese día: se suma a las tandas anteriores)
                                            (el servidor exige ficha.pr y el reporte con sus seis secciones: ## Hecho · ## Evidencia ·
                                             ## Decisiones sobre la marcha · ## Fricciones · ## Para decidir · ## Pendientes fuera de alcance —
                                             las tres últimas van siempre y dicen «Ninguna» cuando no hubo, porque ausente o vacía rebota;
                                             la review publicada en la bitácora va en ficha.review)
  bitacora-api firmar <id> [nota]           → hecho; la nota es la PR mergeada
  bitacora-api devolver <id>                {"cuerpo":{"es":"<entero, con sus ocho secciones y su ## Ronda N>"},"nota":"…"} → encargado
                                            (entrar a encargado cobra las ocho secciones del cuerpo y el queEs; sin cuerpo, imprime la forma)
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
  bitacora-api abrir-subarea                {"slug":"el-alta","nombre":"El alta, pantalla por pantalla","area":"producto","brief":"…"}
        el lugar que ninguna de las que hay aloja — se abre acá y se dice en el reporte (= abrir-hilo = abrir-linea)
  (lo suelto que todavía no merece lugar propio cuelga del PISO: nombrá el área en lugar de la sub-área —`plan <area>`— y el servidor lo crea si falta.)
  bitacora-api editar-subarea <slug>        {"estado":"resuelta"} · {"brief":"…"} · {"area":"infra"} · {"piso":true}   (= editar-hilo)
  bitacora-api abrir-area                   {"nombre":"El contrato"}   (nace vacía; se llena con sub-áreas nuevas o mudando las que ya existen)
  bitacora-api editar-area <slug>           {"nombre":"…"} (renombra) · {"orden":2} (su lugar en el menú)
  bitacora-api fusionar <slug>              {"en":"la-que-queda"}
  bitacora-api abrir-flujo                  {"nombre":"…","queEs":"…","categoria":"runtime",
                                             "pasos":[{"etapa":"…","actor":"…","que":"…","pieza":"algolia","detalle":"…"}]}
  bitacora-api editar-flujo <slug>          {"estado":"construido"} · {"sumarStack":[…]} · {"sumarGlosario":[…]}
                                            · {"pasos":[…]} reemplaza el recorrido entero (un paso no se parchea solo)
  bitacora-api anotar-pieza                 {"nombre":"…","responsabilidad":"…","nivel":"contenedor","tecnologia":"Node · GraphQL · Fargate",
                                             "donde":"…","documentacion":"https://…","notas":"…"}
        nivel = sistema | contenedor | componente | libreria   (sin declararlo, contenedor)
        `dentroDe` es el slug del contenedor: una librería o un componente cuelga de él
  bitacora-api editar-pieza <slug>          {"responsabilidad":"…"} · {"sumarAlias":["el CMS"]}
                                            · {"nivel":"libreria","dentroDe":"engine"} la mete adentro
                                            · {"dentroDe":""} la saca (la cadena vacía borra el campo)
  bitacora-api anotar-fuente                {"nombre":"…","queEs":"…","clase":"hoja","procedencia":"google-sheets",
                                             "producidaPor":"Fran McCann","lado":"cliente","fecha":"2026-09-08",
                                             "vigencia":"viva","url":"https://…","ref":"<doc-id>","tags":["algolia"],"nota":"…"}
        clase = documento | hoja | canal | tablero | diseno | pagina
        procedencia = google-sheets | google-docs | slack | jira | figma | miro | email | drive | mano
        lado = cliente | equipo | nuestro | proveedor      vigencia = viva | fechada
        `fecha` es la DE la fuente: cuándo la produjo su autor, no cuándo la anotaste
  bitacora-api editar-fuente <slug>         {"fecha":"2026-09-09"} · {"sumarTags":["plp-taxonomia"]}
                                            · {"superadaPor":"attribute-register"} la marca reemplazada
                                            · {"superadaPor":""} la desmarca (la cadena vacía borra el campo)
  bitacora-api sincronizada <slug> <archivo> [fecha]
        sube la copia, calcula su huella y estampa el espejo — con la fecha, mueve la de la fuente
  bitacora-api refrescar [slug]             sin slug las que esperan refresco; con slug esa. Sheets y Docs por su export
                                            público (sin credencial: compartido por enlace); las demás, por su skill
  bitacora-api seccion                      {"tipo":"archivo","nombre":"…","nota":"…"}
  bitacora-api editar-seccion <slug>        {"resumen":"…"} · {"tipo":"fuente"}
  bitacora-api sincronizar-skills [<repo>…] (UNA llamada: manda los hashes de los SKILL.md que ve y sube solo lo que cambió;
                                             su última línea nombra lo nuevo, lo que cambió, las notas que quedaron viejas
                                             y cuántas siguen sin contar; los <repo> extra son otras carpetas del mismo tenant)
                                            la corre la skill /skills, a mano; su última línea dice qué cambió y es su plan de trabajo
  bitacora-api escribir-estado <area>       {"cuerpo":{"es":"# Dónde estamos\n…\n# El mapa\n…\n# En vuelo\n…\n# Lo que sigue\n…\n# Lo que espera de otros\n…"},
                                             "hito":"…","plan":"<id>","diagramas":[…]}
        toma la FOTO nueva del estado del área, al cierre de un cambio importante: cinco secciones de lo amplio a lo específico
        («Dónde estamos» sin código y en cuatro oraciones; «El mapa» con su dibujo d2), el hito que la produjo y el plan firmado
        cuando fue uno; la foto anterior queda como historia y se recorre con «Anterior»
  bitacora-api editar-estado <area>         {"cuerpo":…} · {"hito":"…"} · {"traduccion":{"idioma":"en","cuerpo":"…","hash":"…"}}
        corrige la foto vigente sin abrir versión
  bitacora-api escribir-instrucciones       < instrucciones.md   (el markdown entero por stdin; reemplaza; crea la sección la primera vez)
  bitacora-api escribir-dominio             < dominio.md          (el negocio del cliente, con sus palabras; reemplaza)
        las dos aceptan · --json < {"cuerpo":{"es":"…","en":"…"},"queEs":"…"}   (en dos idiomas)
  bitacora-api definir                      {"termino":"…","definicion":"…"}  (o una lista)
  bitacora-api anotar-acceso                {"nombre":"Engine API","url":"https://…","nota":"staging"}
                                            · con qué se entra: {"usuario":"…","clave":"…"}
  bitacora-api review                       {"titulo":"<título del PR>","pr":"…","cuerpo":"…"}
  bitacora-api rato (dueño)                 {"tarea":"…","reloj":"1:30"}   (el banco de horas)
                                            · la fila entera: {"tareaEn":"la fila en inglés, la que se carga","epica":"<código de la épica>","epicaNombre":"<su nombre>",
                                              "jira":{"clave":"<clave del ticket>","url":"…"}} — las instrucciones del tenant dicen cuáles van siempre
                                            · de dónde salió: {"plan":"<id del plan>","pr":"https://…/pull/12"} — el banco lo enlaza
                                              con su PR, su plan y su review (el plan presta a su rato la PR y la review de su ficha)
  bitacora-api mover-rato <id> (dueño)      {"estado":"cargado"} · {"plan":"<id>","pr":"…"} (null lo saca)
  bitacora-api guardar-documento            el documento entero
  bitacora-api traducir                     {"linea":"…","slug":"…","idioma":"en","cuerpo":"…","hash":"…"}
  bitacora-api traducir                     {"tipo":"hilo","llave":"…","idioma":"en","campos":{…},"huella":"…"}
                                            (traduce desde el `escritoEn` del documento)
                                            (acepta linea|seccion|flujo, los nombres que da la cola)
  bitacora-api mudar-documento <linea|seccion|flujo> <contenedor> <slug>   {"lineaSlug":"otra"}

Poner una pieza afuera — se lee sin entrar, y nada más que esa pieza (dueño):
  bitacora-api publicar <subarea> <slug>       → devuelve el `enlace` para mandar
  bitacora-api publicar <seccion>           (una review: es una sección de un solo documento)
  bitacora-api publicar <linea|seccion|flujo> <contenedor> <slug>
                                            (la forma explícita: la sección con varios documentos
                                             o con archivos propios, y el texto de un flujo)
  bitacora-api privado <subarea> <slug>        (la trae de vuelta adentro, con las mismas tres formas)
                                            publicar abre también los archivos que ese texto muestra
                                            —las capturas, el PDF que un client-report entregó—, y privado los cierra

Archivos y bajas (borrar es del dueño):
  bitacora-api adjuntar <archivo> linea=<slug> [queEs="…"]
  bitacora-api borrar /api/lineas/<slug>     (se niega si todavía cuelga algo)
  bitacora-api borrar /api/areas/<slug>      (se niega si alguna sub-área vive ahí)
  bitacora-api borrar /api/enlaces/<slug>    (saca un acceso de la columna)
  bitacora-api pendientes                    (sube lo que quedó sin red)

El alta y la renovación de la llave:
  bitacora-api alta <código>                 (canjea el código del email por la llave y la guarda)
  bitacora-api renovar                       (la llave vence sola: esto manda el código nuevo a tu email)
USO
  exit 1
  ;;
esac
