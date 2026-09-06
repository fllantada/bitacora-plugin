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
      # Las consultas abiertas son la mano que falta: van primero, porque solo la persona las destraba.
      consultas="$(curl -fsS --max-time 20 -H "Authorization: Bearer $llave" \
        "$BASE/api/items/consultas?estado=abierta" 2>/dev/null)" || continue
      printf '%s' "$consultas" | jq -c --arg p "$tenant" \
        '.items[] | {proyecto: $p, tipo: "consulta", estado, hilo, area, titulo, id, respuestas}'
    done
  } | jq -s 'sort_by(if .tipo == "consulta" then 0 elif .estado == "entregado" then 1 elif .estado == "en-curso" then 2 else 3 end)'
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
# El sistema del proyecto en una llamada: el dominio, el stack y los flujos, MÁS las
# instrucciones del ciclo en este tenant (el markdown crudo, o null).
# Las skills NO viajan acá: la sesión ya tiene las suyas en el disco, y el catálogo es la
# vista para el humano (se lee con `skills`). /thinking y /coding la hacen en su paso 0 y
# obedecen las instrucciones.
contexto) leer "/api/contexto" ;;
# Cómo se corre el ciclo acá, solas: dónde se para cada sesión, qué gatea un commit, cómo
# sale la PR, dónde se publica la review, cómo se factura, las fuentes, los registros, las
# skills. Es material del proyecto: la lee todo miembro. Sin cargar contesta 404.
instrucciones) leer "/api/instrucciones" ;;
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
# ─────────────────────────────────────────────────────────────────────────────
# PONER UNA PIEZA AFUERA — se lee sin entrar, y nada más que esa pieza.
#
# La dirección que devuelve (`enlace`) es la que se manda: cualquiera con ella lee la
# página, sin cuenta y sin login. El resto del proyecto —el tablero, el hilo, las otras
# piezas— sigue adentro, y el espejo público no tiene navegación, así que de una pieza
# publicada no se llega a nada más.
#
# La pieza se nombra como se la lee: `<hilo> <slug>` para lo que cuelga de un hilo, y la
# sección sola para una review, que es una sección de un solo documento. Publicar abre
# también los archivos que ese texto muestra —las capturas, el PDF que un client-report
# entregó— y `privado` los cierra con ella.
#
# Es del dueño del proyecto: la llave de un colaborador recibe un 403.
# ─────────────────────────────────────────────────────────────────────────────
publicar | privado)
  exige 1 "$comando <hilo> <slug>   |   $comando <seccion>   |   $comando <linea|seccion|flujo> <contenedor> <slug>" "$@"
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
    echo "  · $comando <hilo> <slug>" >&2
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
    echo "  · $comando <hilo> <slug>" >&2
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
# LOS TIPOS DE UN HILO — analisis · planes · bugs · client-reports · decisiones · simulaciones · consultas
#
# Un hilo es el ticket y adentro cuelgan cosas de tipo distinto. El tipo se nombra
# en plural y en la misma palabra que se lee en la app, así lo que se escribe y lo
# que se navega dicen igual.
# ─────────────────────────────────────────────────────────────────────────────
tipo)
  exige 1 "tipo <analisis|planes|bugs|client-reports|decisiones|simulaciones|consultas> [estado]" "$@"
  leer "/api/items/$(uri "$1")${2:+?estado=$(uri "${2:-}")}"
  ;;
abiertos)
  exige 1 "abiertos <analisis|planes|bugs|client-reports|decisiones|simulaciones|consultas>" "$@"
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
analisis | plan | bug | client-report | simulacion | consulta)
  exige 1 "$comando <hilo>   < JSON" "$@"
  vaciar_cola
  case "$comando" in
    analisis) ruta_tipo=analisis ;;
    plan) ruta_tipo=planes ;;
    bug) ruta_tipo=bugs ;;
    client-report) ruta_tipo=client-reports ;;
    simulacion) ruta_tipo=simulaciones ;;
    consulta) ruta_tipo=consultas ;;
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
# El servidor cobra el contrato en las dos puntas: para entrar a encargado, el cuerpo
# con sus seis secciones (Tarea · Destino · Contexto y porqué · Patrón a seguir ·
# Alcance exacto · Lo que NO entra); para llegar a entregado, el reporte con las suyas
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
  exige 1 "devolver <id>   < {\"cuerpo\":{\"es\":\"<el cuerpo entero, con sus seis secciones y su ## Ronda N>\"},\"nota\":\"…\"}" "$@"
  vaciar_cola
  # Devolver es agregar la ronda: un cuerpo vacío se contesta acá con la forma, porque el
  # verbo pone el estado y el servidor recibiría un movimiento sin ronda que parece válido.
  cuerpo_devuelto="$(cat)"
  if [ -z "$(printf '%s' "$cuerpo_devuelto" | jq -r '.cuerpo // empty' 2>/dev/null)" ]; then
    echo "devolver lleva el cuerpo ENTERO del plan con la ronda nueva al final:" >&2
    echo '  {"cuerpo":{"es":"# Tarea\n…\n# Destino\n…\n# Contexto y porqué\n…\n# Patrón a seguir\n…\n# Alcance exacto\n…\n# Lo que NO entra\n…\n\n## Ronda N\nqué → por qué → corrección propuesta"},"nota":"vuelve: <por qué, en una frase>"}' >&2
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
# las opciones vivas si las hay, la recomendación y su porqué breve. La persona ACEPTA o
# RECHAZA cada recomendación EN LA WEB —rechazar dice qué va en su lugar— y con la última
# la consulta pasa sola a `contestada`; la sesión la lee con `respuestas`, aplica lo
# decidido —la ronda, las decisiones al libro— y la pasa a `aplicada`. La respuesta
# contesta 400 por esta puerta: es de la persona.
# ─────────────────────────────────────────────────────────────────────────────
consultas) leer "/api/items/consultas${1:+?estado=$(uri "${1:-}")}" ;;
# Las que la persona ya contestó enteras: la bandeja de la sesión que preguntó.
contestadas) leer "/api/items/consultas?estado=contestada" ;;
# Lo que la persona decidió, punto por punto: aceptó o rechazó cada recomendación, y su comentario.
respuestas)
  exige 1 "respuestas <id>" "$@"
  leer "/api/items/consultas/$(uri "$1")" | jq '{estado, hilo, titulo, respuestas, faltan, puntos: [.puntos[] | {id, titulo, recomendacion: .propuesta, porque, decision: (.respuesta.decision // null), comentario: (.respuesta.texto // null), por: (.respuesta.autor // null)}]}'
  ;;
# La sesión tomó las respuestas: la consulta cierra. Sin contestar entera, 400.
aplicar)
  exige 1 "aplicar <id> [nota]" "$@"
  vaciar_cola
  jq -cn --arg n "${2:-}" '{estado:"aplicada"} + (if $n == "" then {} else {nota:$n} end)' |
    escribir PATCH "/api/items/consultas/$(uri "$1")"
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

El sistema del proyecto — la tríada, las instrucciones y las skills. Primera lectura al llegar:
  bitacora-api contexto                     (el dominio + el stack + los flujos + las instrucciones, de una)
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

El trabajo (en el taller un tema se llama HILO; la API lo guarda como `lineas`):
  bitacora-api abrir                        (el tablero en tu navegador, sin login: enlace fresco de un solo uso)
  bitacora-api tablero                      (los hilos con su área y sus ítems, las áreas, lo pendiente por escritorio, la tríada contada)
  bitacora-api bandeja                      (sin -p: las consultas que esperan tu respuesta y los planes entregados, en curso y encargados de TODOS los proyectos)
  bitacora-api encargados · en-curso · entregados   (el ciclo del encargo, por escritorio; cada plan con su hilo y su área)
  bitacora-api hilos                        (= lineas)
  bitacora-api hilo <slug|alias>            (= linea)
  bitacora-api areas                        (los mundos del proyecto, con sus hilos)
  bitacora-api area <slug>                  (un área con los hilos que viven ahí; `areas <slug>` es lo mismo)
  bitacora-api buscar <texto>
  bitacora-api documento <linea|seccion|flujo> <contenedor> <slug>
  bitacora-api secciones · bitacora-api horas (dueño) · bitacora-api adjuntos [linea] · bitacora-api reviews
  bitacora-api publicados                   (lo que está afuera hoy, con el enlace de cada uno)
  bitacora-api del-hilo <hilo> <tipo>       (lo que cuelga de un hilo, de un tipo)
  bitacora-api tipo <tipo> [estado]         (todos los del proyecto, cruzando hilos)
  bitacora-api item <tipo> <id>             (uno entero: su cuerpo y cómo se movió)
  bitacora-api abiertos <tipo>              (los que quedaron sin cerrar; el análisis y la decisión no tienen)
        tipo = analisis | planes | bugs | client-reports | decisiones | simulaciones | consultas
  bitacora-api simulaciones [estado]        (los experimentos del proyecto; `calificando` son los que esperan a la persona)
  bitacora-api consultas [estado]           (lo que la sesión le preguntó a la persona; `abierta` espera respuestas)
  bitacora-api contestadas                  (las que la persona ya contestó enteras: lo que la sesión tiene que aplicar)
  bitacora-api respuestas <id>              (punto por punto: la recomendación, si la persona la aceptó o la rechazó, y su comentario)
  bitacora-api por-traducir [idioma]        (documentos y fichas: lo que falta y lo que quedó viejo)

Escritura (el cuerpo JSON entra por stdin):
  bitacora-api analisis <hilo>              {"titulo":"…","queEs":"…","cuerpo":{"es":"# …"}}
  bitacora-api plan <hilo>                  {"titulo":"…","cierraEn":"…","cuerpo":{"es":"# …"},"flujos":["…"]}
        con "estado":"encargado" nace como ENCARGO: el cuerpo es el handoff y cierraEn el criterio de terminado;
        el servidor exige seis secciones en el cuerpo: # Tarea · # Destino · # Contexto y porqué · # Patrón a seguir · # Alcance exacto · # Lo que NO entra
  bitacora-api bug <hilo>                   {"titulo":"…","cuerpo":{"es":"# Qué se observa\n…\n\n# Dónde\n…\n\n# Cómo se reproduce\n…"},"flujos":["…"]}
        `flujos` son los recorridos que el ítem corta mientras está abierto: de ahí sale la madurez del flujo
  bitacora-api client-report <hilo>         {"titulo":"…","cuerpo":{"es":"# …"}}
  bitacora-api simulacion <hilo>            {"titulo":"…","hipotesis":"…","criterioExito":"…",
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
  bitacora-api consulta <hilo>              {"titulo":"…","queEs":"de dónde salen los puntos y qué se hace con lo decidido, en una o dos frases",
                                             "puntos":[{"titulo":"…","queCambia":"qué se decide y qué cambia con cada respuesta",
                                                        "opciones":[{"titulo":"…","implica":"…"}],
                                                        "propuesta":"la recomendación: lo que la sesión haría","porque":"su porqué, en una o dos frases"}]}
        el human in the loop: nace `abierta`; la persona ACEPTA o RECHAZA cada recomendación EN LA WEB y pasa sola a `contestada`
  bitacora-api aplicar <id> [nota]          → aplicada: la sesión tomó lo decidido (la ronda, las decisiones al libro); sin decidir entera, 400
        la respuesta es DE LA PERSONA y se escribe en la web: por esta puerta, 400
  bitacora-api traducir-item <tipo> <id>    {"traduccion":{"idioma":"en","cuerpo":"…","hash":"…"}}
  bitacora-api mover <tipo> <id>            {"estado":"hecho","nota":"cómo cerró"}
                                            · {"hilo":"el-que-corresponde"} lo muda de hilo (acepta el alias)
        la decisión NO tiene escritorios: nace tomada y se corrige con corregir
  El ciclo del encargo (azúcar sobre mover planes; el estado lo pone el verbo):
  bitacora-api tomar <id> [nota]            → en-curso; la nota (y ficha.destino) es el worktree o la copia que lo tiene
  bitacora-api entregar <id>                {"reporte":{"es":"## Hecho\n…"},"ficha":{"pr":"…","rama":"…","review":"…"},"consumo":{…},"nota":"…"} → entregado
                                            (el consumo son los tokens de cada motor con su precio de ese día: se suma a las tandas anteriores)
                                            (el servidor exige ficha.pr y el reporte con sus seis secciones: ## Hecho · ## Evidencia ·
                                             ## Decisiones sobre la marcha · ## Fricciones · ## Para decidir · ## Pendientes fuera de alcance —
                                             las tres últimas van siempre y dicen «Ninguna» cuando no hubo, porque ausente o vacía rebota;
                                             la review publicada en la bitácora va en ficha.review)
  bitacora-api firmar <id> [nota]           → hecho; la nota es la PR mergeada
  bitacora-api devolver <id>                {"cuerpo":{"es":"<entero, con sus seis secciones y su ## Ronda N>"},"nota":"…"} → encargado
                                            (entrar a encargado cobra las seis secciones del cuerpo; sin cuerpo, imprime la forma)
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
  bitacora-api sincronizar-skills [<repo>…] (UNA llamada: manda los hashes de los SKILL.md que ve y sube solo lo que cambió;
                                             su última línea nombra lo nuevo, lo que cambió, las notas que quedaron viejas
                                             y cuántas siguen sin contar; los <repo> extra son otras carpetas del mismo tenant)
                                            la corre la skill /skills, a mano; su última línea dice qué cambió y es su plan de trabajo
  bitacora-api escribir-instrucciones       < instrucciones.md   (el markdown entero por stdin; reemplaza; crea la sección la primera vez)
                                            · --json < {"cuerpo":{"es":"…","en":"…"},"queEs":"…"}   (en dos idiomas)
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
  bitacora-api publicar <hilo> <slug>       → devuelve el `enlace` para mandar
  bitacora-api publicar <seccion>           (una review: es una sección de un solo documento)
  bitacora-api publicar <linea|seccion|flujo> <contenedor> <slug>
                                            (la forma explícita: la sección con varios documentos
                                             o con archivos propios, y el texto de un flujo)
  bitacora-api privado <hilo> <slug>        (la trae de vuelta adentro, con las mismas tres formas)
                                            publicar abre también los archivos que ese texto muestra
                                            —las capturas, el PDF que un client-report entregó—, y privado los cierra

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
