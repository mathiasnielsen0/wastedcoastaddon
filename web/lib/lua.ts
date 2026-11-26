// Læser WoW's SavedVariables-format (Lua-tabeller) og laver det om til almindelige JS-objekter.
// Tabeller, der kun har nøglerne 1..n, bliver til arrays; resten bliver til objekter.
// Lua-strenge er bytes. Vi læser filen som latin1 (én byte = ét tegn) og afkoder UTF-8 til sidst.

export type LuaValue = string | number | boolean | null | LuaValue[] | { [k: string]: LuaValue };

const IDENT = /^[A-Za-z_][A-Za-z0-9_]*/;
const LONG = /^\[(=*)\[/;

export function parseSavedVariables(text: string): Record<string, LuaValue> {
  let i = 0;
  const n = text.length;
  const out: Record<string, LuaValue> = {};
  if (text.startsWith("\xef\xbb\xbf")) i = 3; // UTF-8-BOM læst som latin1

  const fail = (msg: string): never => {
    throw new Error(`Lua-fejl ved tegn ${i}: ${msg}`);
  };

  function skip() {
    for (;;) {
      const c = text.charCodeAt(i);
      if (c === 32 || c === 9 || c === 10 || c === 13 || c === 0xfeff) {
        i++;
        continue;
      }
      if (c === 45 && text.charCodeAt(i + 1) === 45) {
        i += 2;
        const m = LONG.exec(text.slice(i, i + 10));
        if (m) {
          const end = text.indexOf("]" + m[1] + "]", i);
          i = end < 0 ? n : end + m[1].length + 2;
        } else {
          while (i < n && text[i] !== "\n") i++;
        }
        continue;
      }
      return;
    }
  }

  function parseString(): string {
    const q = text[i++];
    let s = "";
    let start = i;
    for (;;) {
      if (i >= n) fail("ufærdig tekst");
      const ch = text[i];
      if (ch === q) {
        s += text.slice(start, i);
        i++;
        return s;
      }
      if (ch === "\\") {
        s += text.slice(start, i);
        i++;
        const e = text[i++];
        if (e === "n") s += "\n";
        else if (e === "t") s += "\t";
        else if (e === "r") s += "\r";
        else if (e === "a") s += "\x07";
        else if (e === "b") s += "\b";
        else if (e === "f") s += "\f";
        else if (e === "v") s += "\v";
        else if (e === "\n") s += "\n";
        else if (e === "\r") {
          s += "\n";
          if (text[i] === "\n") i++;
        } else if (e >= "0" && e <= "9") {
          let d = e;
          while (d.length < 3 && text[i] >= "0" && text[i] <= "9") d += text[i++];
          s += String.fromCharCode(parseInt(d, 10) & 255);
        } else s += e;
        start = i;
        continue;
      }
      i++;
    }
  }

  function parseLongString(): string {
    const m = LONG.exec(text.slice(i, i + 20))!;
    i += m[0].length;
    if (text[i] === "\r") i++;
    if (text[i] === "\n") i++;
    const close = "]" + m[1] + "]";
    const end = text.indexOf(close, i);
    if (end < 0) fail("ufærdig lang tekst");
    const s = text.slice(i, end);
    i = end + close.length;
    return s;
  }

  function parseNumber(): number {
    const m = /^-?(0[xX][0-9a-fA-F]+|(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?|inf|nan)/.exec(text.slice(i, i + 64));
    if (!m) fail("ugyldigt tal");
    i += m![0].length;
    const t = m![0];
    if (t.endsWith("inf")) return t[0] === "-" ? -Infinity : Infinity;
    if (t.endsWith("nan")) return NaN;
    if (/0[xX]/.test(t)) return (t[0] === "-" ? -1 : 1) * parseInt(t.replace("-", ""), 16);
    return parseFloat(t);
  }

  function parseValue(): LuaValue {
    skip();
    const c = text[i];
    if (c === "{") return parseTable();
    if (c === '"' || c === "'") return parseString();
    if (c === "[" && LONG.test(text.slice(i, i + 10))) return parseLongString();
    if (text.startsWith("true", i)) { i += 4; return true; }
    if (text.startsWith("false", i)) { i += 5; return false; }
    if (text.startsWith("nil", i)) { i += 3; return null; }
    return parseNumber();
  }

  function parseTable(): LuaValue {
    i++; // {
    const arr: LuaValue[] = [];
    let obj: Record<string, LuaValue> | null = null;
    let next = 1;
    for (;;) {
      skip();
      if (i >= n) fail("ufærdig tabel");
      if (text[i] === "}") { i++; break; }
      let key: LuaValue;
      let val: LuaValue;
      if (text[i] === "[" && !LONG.test(text.slice(i, i + 10))) {
        i++;
        key = parseValue();
        skip();
        if (text[i] !== "]") fail("mangler ]");
        i++;
        skip();
        if (text[i] !== "=") fail("mangler =");
        i++;
        val = parseValue();
      } else {
        const save = i;
        const m = IDENT.exec(text.slice(i, i + 200));
        if (m && m[0] !== "true" && m[0] !== "false" && m[0] !== "nil") {
          i += m[0].length;
          skip();
          if (text[i] === "=") { i++; key = m[0]; val = parseValue(); }
          else { i = save; key = next; val = parseValue(); }
        } else {
          key = next;
          val = parseValue();
        }
      }
      if (typeof key === "number" && key === next && obj === null) {
        arr.push(val);
        next++;
      } else {
        if (obj === null) {
          obj = {};
          arr.forEach((v, k) => { obj![String(k + 1)] = v; });
        }
        if (typeof key === "number" && key === next) next++;
        if (val !== null) obj[String(key)] = val;
      }
      skip();
      if (text[i] === "," || text[i] === ";") i++;
    }
    return obj === null ? arr : obj;
  }

  for (;;) {
    skip();
    if (i >= n) break;
    const m = IDENT.exec(text.slice(i, i + 200));
    if (!m) fail("forventede et navn");
    i += m![0].length;
    skip();
    if (text[i] !== "=") fail("mangler = efter " + m![0]);
    i++;
    out[m![0]] = parseValue();
  }
  return out;
}

const utf8 = new TextDecoder("utf-8", { fatal: true });

function fixUtf8(v: LuaValue): LuaValue {
  if (typeof v === "string") {
    if (!/[\x80-\xff]/.test(v)) return v;
    try {
      const b = new Uint8Array(v.length);
      for (let k = 0; k < v.length; k++) b[k] = v.charCodeAt(k) & 255;
      return utf8.decode(b);
    } catch {
      return v;
    }
  }
  if (Array.isArray(v)) return v.map(fixUtf8);
  if (v && typeof v === "object") {
    const o: Record<string, LuaValue> = {};
    for (const key of Object.keys(v)) o[fixUtf8(key) as string] = fixUtf8(v[key]);
    return o;
  }
  return v;
}

/** Læs en SavedVariables-fil (rå bytes) */
export function parseBytes(bytes: Uint8Array): Record<string, LuaValue> {
  let s = "";
  for (let k = 0; k < bytes.length; k += 0x8000) {
    s += String.fromCharCode.apply(null, Array.from(bytes.subarray(k, k + 0x8000)));
  }
  return fixUtf8(parseSavedVariables(s)) as Record<string, LuaValue>;
}
