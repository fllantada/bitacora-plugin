#!/usr/bin/env node
/**
 * EL DIBUJO DE LA CASA — la compilación de los diagramas de la bitácora, con su trazo.
 *
 * La bitácora dibuja con el trazo de las propuestas de dev-fran: el modo boceto de `d2`, la
 * línea en tinta, la letra de la página en negrita, las cajas sobre el papel y el color en
 * la entrada y la salida del recorrido. Es un trazo propio, y por eso la compilación viaja
 * con el plugin: el preámbulo que declara las clases, las banderas del compilador y la marca
 * que la hoja de estilos lee (`data-boceto`). La hoja (`globals.css`, «el boceto») termina
 * de pintarlo con los tokens de la página.
 *
 * Corre donde el binario existe, que es la máquina que escribe, desde cualquier proyecto:
 * el shim `bitacora-diagramas` lo expone, `bitacora-api review` lo corre sobre la review
 * antes de subirla, y el repo de la bitácora lo usa en `npm run diagramas`, `redibujar` y
 * `migrar`. El servidor solo sirve el SVG ya compilado.
 *
 *   bitacora-diagramas < cuerpo.md > diagramas.json
 *   bitacora-diagramas --idioma en < body.md
 *
 * Imprime `diagramas[]` —la huella de cada bloque, su SVG y su pie— tal como las puertas
 * lo reciben. Un bloque que queda sin compilar —`d2` lo rechazó, o está escrito en otro
 * lenguaje— frena el comando: sale con error nombrando cada bloque y sin imprimir nada,
 * porque un `[]` con éxito se lee igual que un cuerpo sin diagramas y la pieza subía con el
 * código a la vista. Sin dependencias: solo Node y `d2`.
 */
import { createHash } from "node:crypto";
import { execFileSync, spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

/**
 * El ancho que el papel le deja a un diagrama.
 *
 * El papel ancho de un documento llega a 1280px con 68 de aire a cada lado
 * (`globals.css`, `.md.ancho`), así que esto es lo que queda entre los dos márgenes.
 */
export const PAPEL = 1144;

/**
 * El hash con el que un diagrama se aparea con su bloque en el cuerpo: el mismo que el
 * servidor calcula al leer (`src/server/shared/hash.ts`).
 *
 * @param {string} codigo
 * @returns {string}
 */
export function hashDe(codigo) {
  return createHash("sha1").update(codigo.trim()).digest("hex").slice(0, 16);
}

/**
 * Si la máquina puede compilar diagramas ahora mismo.
 *
 * @returns {boolean}
 */
export function hayCompilador() {
  try {
    execFileSync("which", ["d2"], { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

/**
 * Los bloques de diagrama de un markdown, con su lenguaje y su pie.
 *
 * @param {string} markdown
 * @returns {{ lenguaje: "d2" | "mermaid"; codigo: string; caption?: string }[]}
 */
export function bloquesDeDiagrama(markdown) {
  const bloques = [];
  for (const encontrado of markdown.matchAll(/```(d2|mermaid)[ \t]*\r?\n([\s\S]*?)```/g)) {
    const codigo = encontrado[2];
    const caption = codigo.match(/^#\s*caption:\s*(.+)$/m)?.[1]?.trim();
    bloques.push({
      lenguaje: /** @type {"d2" | "mermaid"} */ (encontrado[1]),
      codigo,
      ...(caption ? { caption } : {}),
    });
  }
  return bloques;
}

/**
 * Las clases que un diagrama usa para organizar, declaradas para que `d2` las mida.
 *
 * - `entrada` y `salida`: dónde empieza el recorrido y dónde aterriza, en el ámbar y el
 *   turquesa de la casa. Es lo único con relleno de color en un recorrido.
 * - `carril`: agrupa por quién, con el marco punteado y su rótulo arriba a la izquierda.
 * - `principal`: el camino que importa; `lateral`: lo que se aparta de él.
 * - `a1`..`a4` y `l1`..`l4`: los acentos de forma y de conexión que los diagramas ya
 *   escritos usan, y que la hoja sigue pintando.
 *
 * Los colores de acá son los que `d2` usa para medir y para el SVG suelto; la página los
 * reemplaza por sus tokens.
 */
const PREAMBULO = `classes: {
  entrada: { style: { fill: "#f8ecd9"; stroke: "#0b0b0c" } }
  salida: { style: { fill: "#daf3f0"; stroke: "#0b0b0c" } }
  carril: { style.font-size: 12
    style.stroke-dash: 5
    style.fill: transparent
    label.near: top-left }
  principal: { style.stroke-width: 2 }
  lateral: { style.stroke-dash: 4 }
  a1: { style: { fill: "#eafbf9"; stroke: "#20988f"; stroke-width: 1 } }
  l1: { style: { stroke: "#20988f"; stroke-width: 2 } }
  a2: { style: { fill: "#f0efff"; stroke: "#6d5bff"; stroke-width: 1 } }
  l2: { style: { stroke: "#6d5bff"; stroke-width: 2 } }
  a3: { style: { fill: "#fff0f5"; stroke: "#da5f86"; stroke-width: 1 } }
  l3: { style: { stroke: "#da5f86"; stroke-width: 2 } }
  a4: { style: { fill: "#ebebec"; stroke: "#6e6e78"; stroke-width: 1 } }
  l4: { style: { stroke: "#6e6e78"; stroke-width: 2 } }
}
`;

/** Un fondo o unas clases declaradas a nivel raíz mandan: se reconocen sin indentación. */
const FONDO_RAIZ = /^(style\.fill\b|style:\s*\{)/m;
const CLASES_RAIZ = /^classes:\s*\{/m;

/** Las directivas de cabecera: `# caption: …` y `# layout: elk`. No llegan al compilador. */
const DIRECTIVA = /^#[ \t]*(caption|layout):[ \t]*(.+?)[ \t]*$/i;
const LAYOUTS = new Set(["dagre", "elk"]);

/**
 * La letra de la página, cuando la máquina la tiene instalada; sin ella, `d2` usa la suya.
 *
 * La etiqueta de una flecha es la itálica de d2, y la hoja la pinta derecha en la letra de la
 * página: d2 la mide con esa misma letra (`--font-italic` apunta a la regular), así la
 * etiqueta ocupa lo que se midió y entra entera en el dibujo.
 *
 * @returns {string[]}
 */
function banderasDeLetra() {
  const fuentes = path.join(os.homedir(), "Library", "Fonts");
  const variantes = [
    ["--font-regular", "Geist-Regular.ttf"],
    ["--font-italic", "Geist-Regular.ttf"],
    ["--font-bold", "Geist-Bold.ttf"],
    ["--font-semibold", "Geist-SemiBold.ttf"],
  ];
  return variantes.flatMap(([bandera, archivo]) => {
    const ruta = path.join(fuentes, archivo);
    return fs.existsSync(ruta) ? [bandera, ruta] : [];
  });
}

/**
 * Separa las directivas de cabecera del código que compila.
 *
 * @param {string} codigo
 * @returns {{ fuente: string; layout: string }}
 */
function separarDirectivas(codigo) {
  const renglones = codigo.split("\n");
  let layout = "dagre";
  let i = 0;
  while (i < renglones.length) {
    const directiva = DIRECTIVA.exec(renglones[i]);
    if (!directiva) break;
    if (directiva[1].toLowerCase() === "layout" && LAYOUTS.has(directiva[2].toLowerCase())) {
      layout = directiva[2].toLowerCase();
    }
    i++;
  }
  return { fuente: renglones.slice(i).join("\n"), layout };
}

/**
 * Del error de `d2` queda lo que sirve para arreglar el bloque: sin progreso y sin la ruta temporal.
 *
 * @param {string} stderr
 * @returns {string}
 */
function errorLimpio(stderr) {
  return stderr
    .split("\n")
    .filter((renglon) => renglon.trim() && !/^(info|success):/i.test(renglon.trim()))
    .map((renglon) => renglon.replace(/(\.\.\/)*\/?[^\s:]*\/d\.d2:?/g, "").replace(/^err:\s*/i, "").trim())
    .join(" · ");
}

/**
 * Compila un bloque `d2` con el trazo de la casa.
 *
 * @param {string} codigo
 * @returns {string}
 */
function compilarBloque(codigo) {
  const { fuente, layout } = separarDirectivas(codigo);
  const conFondo = FONDO_RAIZ.test(fuente) ? fuente : `style.fill: transparent\n${fuente}`;
  const conClases = CLASES_RAIZ.test(conFondo) ? conFondo : PREAMBULO + conFondo;

  const carpeta = fs.mkdtempSync(path.join(os.tmpdir(), "bitacora-d2-"));
  try {
    const origen = path.join(carpeta, "d.d2");
    const destino = path.join(carpeta, "d.svg");
    fs.writeFileSync(origen, conClases, "utf8");
    const corrida = spawnSync(
      "d2",
      ["--sketch", "--theme=1", `--layout=${layout}`, "--pad=8", ...banderasDeLetra(), origen, destino],
      { encoding: "utf8" },
    );
    if (corrida.status !== 0 || !fs.existsSync(destino)) {
      throw new Error(errorLimpio(corrida.stderr ?? "") || "d2 falló sin mensaje");
    }
    const svg = fs.readFileSync(destino, "utf8").match(/<svg[\s\S]*<\/svg>/)?.[0];
    if (!svg) throw new Error("d2 no devolvió SVG");
    /** La marca con la que la hoja reconoce el trazo de la casa. */
    return svg.replace("<svg", '<svg data-boceto=""');
  } finally {
    fs.rmSync(carpeta, { recursive: true, force: true });
  }
}

/**
 * Compila los diagramas de un cuerpo.
 *
 * Cada bloque se pasa solo, y no el documento entero, para poder guardar el SVG por
 * separado: así el cuerpo que se edita conserva su código fuente y el render no tiene que
 * volver a compilar nada. La huella es la del bloque entero, directivas incluidas, que es
 * lo que la página lee al aparear.
 *
 * Un bloque que `d2` rechaza no rompe la corrida — se avisa y ese diagrama queda sin SVG,
 * que la vista muestra como el código que es. El bloque escrito en otro lenguaje se avisa
 * con la regla y sin llamar al compilador: la bitácora compila `d2`, que es el que la
 * página pinta con las clases de la casa.
 *
 * @param {string} markdown
 * @param {(mensaje: string) => void} avisar
 * @returns {{ hash: string; svg: string; caption?: string }[]}
 */
export function compilarDiagramas(markdown, avisar) {
  const compilados = [];

  for (const bloque of bloquesDeDiagrama(markdown)) {
    if (bloque.lenguaje !== "d2") {
      avisar(`un bloque ${bloque.lenguaje} queda como código: el diagrama se escribe en d2, que es lo que la bitácora compila`);
      continue;
    }
    try {
      compilados.push({
        hash: hashDe(bloque.codigo),
        svg: compilarBloque(bloque.codigo),
        ...(bloque.caption ? { caption: bloque.caption } : {}),
      });
    } catch (error) {
      avisar(`no compiló un bloque d2: ${error instanceof Error ? error.message : "error desconocido"}`);
    }
  }

  return compilados;
}

/** El comando: el markdown por stdin, `diagramas[]` por stdout. */
function main() {
  const argumentos = process.argv.slice(2);
  const enIdioma = argumentos.indexOf("--idioma");
  const idioma = enIdioma >= 0 ? argumentos[enIdioma + 1] : "es";
  if (!/^[a-z]{2}$/.test(idioma ?? "")) {
    console.error("--idioma lleva el código de dos letras de la capa: es, en");
    process.exit(1);
  }
  if (!hayCompilador()) {
    console.error("sin compilador de diagramas en esta máquina: hace falta `d2` (brew install d2)");
    process.exit(1);
  }

  const markdown = fs.readFileSync(0, "utf8");
  const sinCompilar = [];
  const diagramas = compilarDiagramas(markdown, (mensaje) => sinCompilar.push(mensaje)).map(
    (diagrama) => ({ idioma, ...diagrama }),
  );

  /**
   * El diagrama que se pasa del papel se avisa con la medida de ESTA casa: un diagrama más
   * ancho que el papel se reduce para entrar, y pasado cierto punto su letra deja de leerse
   * — que es el problema real, y por eso el aviso dice cuánto se pasa y qué lo achica.
   */
  for (const diagrama of diagramas) {
    const ancho = Number(/width="([0-9.]+)"/.exec(diagrama.svg)?.[1] ?? 0);
    if (ancho > PAPEL) {
      console.error(
        `ancho: un diagrama mide ${Math.round(ancho)}px y el papel da ${PAPEL}px —se achica al ` +
          `${Math.round((PAPEL / ancho) * 100)}% para entrar—. Lo ancho lo fija el renglón más largo de ` +
          "una caja y la fila más poblada: acortá ese renglón, o encadená las cajas que hoy salen en abanico.",
      );
    }
  }
  if (sinCompilar.length) {
    for (const motivo of sinCompilar) console.error(`sin compilar: ${motivo}`);
    console.error(
      `${sinCompilar.length} de ${sinCompilar.length + diagramas.length} bloques sin compilar: ` +
        "la pieza se escribe cuando compilan todos",
    );
    process.exit(1);
  }
  process.stdout.write(JSON.stringify(diagramas));
  console.error(`diagramas compilados: ${diagramas.length}`);
}

/** Corre como comando cuando se lo llama directo —o por el shim—, y como módulo cuando se lo importa. */
const esteArchivo = fs.realpathSync(fileURLToPath(import.meta.url));
const llamado = process.argv[1] ? fs.realpathSync(path.resolve(process.argv[1])) : "";
if (esteArchivo === llamado) main();
