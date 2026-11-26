// Læser WoW's SavedVariables-format (Lua-tabeller) og laver det om til almindelige JS-objekter.
// Tabeller, der kun har nøglerne 1..n, bliver til arrays; resten bliver til objekter.
(function (root) {
  "use strict";

  function parseSavedVariables(text) {
    var i = 0, n = text.length;
    var out = {};

    function fail(msg) { throw new Error("Lua-fejl ved tegn " + i + ": " + msg); }

    function skip() {
      for (;;) {
        var c = text.charCodeAt(i);
        if (c === 32 || c === 9 || c === 10 || c === 13 || c === 0xFEFF) { i++; continue; }
        if (c === 45 && text.charCodeAt(i + 1) === 45) { // -- kommentar
          i += 2;
          if (text[i] === "[" && /^\[=*\[/.test(text.slice(i, i + 10))) {
            var m = /^\[(=*)\[/.exec(text.slice(i, i + 10));
            var end = text.indexOf("]" + m[1] + "]", i);
            i = end < 0 ? n : end + m[1].length + 2;
          } else {
            while (i < n && text[i] !== "\n") i++;
          }
          continue;
        }
        return;
      }
    }

    function parseString() {
      var q = text[i++], s = "", start = i;
      for (;;) {
        if (i >= n) fail("ufærdig tekst");
        var ch = text[i];
        if (ch === q) { s += text.slice(start, i); i++; return s; }
        if (ch === "\\") {
          s += text.slice(start, i);
          i++;
          var e = text[i++];
          if (e === "n") s += "\n";
          else if (e === "t") s += "\t";
          else if (e === "r") s += "\r";
          else if (e === "a") s += "\x07";
          else if (e === "b") s += "\b";
          else if (e === "f") s += "\f";
          else if (e === "v") s += "\v";
          else if (e === "\n") s += "\n";
          else if (e === "\r") { s += "\n"; if (text[i] === "\n") i++; }
          else if (e >= "0" && e <= "9") {
            var d = e;
            while (d.length < 3 && text[i] >= "0" && text[i] <= "9") d += text[i++];
            s += String.fromCharCode(parseInt(d, 10));
          } else s += e;
          start = i;
          continue;
        }
        i++;
      }
    }

    function parseLongString() {
      var m = /^\[(=*)\[/.exec(text.slice(i, i + 20));
      i += m[0].length;
      if (text[i] === "\r") i++;
      if (text[i] === "\n") i++;
      var close = "]" + m[1] + "]";
      var end = text.indexOf(close, i);
      if (end < 0) fail("ufærdig lang tekst");
      var s = text.slice(i, end);
      i = end + close.length;
      return s;
    }

    function parseNumber() {
      var m = /^-?(0[xX][0-9a-fA-F]+|(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?|inf|nan)/.exec(text.slice(i, i + 64));
      if (!m) fail("ugyldigt tal");
      i += m[0].length;
      var t = m[0];
      if (/inf$/.test(t)) return t[0] === "-" ? -Infinity : Infinity;
      if (/nan$/.test(t)) return NaN;
      if (/0[xX]/.test(t)) return (t[0] === "-" ? -1 : 1) * parseInt(t.replace("-", ""), 16);
      return parseFloat(t);
    }

    // Lua-strenge er bytes. WoW skriver UTF-8, så vi afkoder dem til sidst.
    function parseValue() {
      skip();
      var c = text[i];
      if (c === "{") return parseTable();
      if (c === '"' || c === "'") return parseString();
      if (c === "[" && /^\[=*\[/.test(text.slice(i, i + 10))) return parseLongString();
      if (text.startsWith("true", i)) { i += 4; return true; }
      if (text.startsWith("false", i)) { i += 5; return false; }
      if (text.startsWith("nil", i)) { i += 3; return null; }
      return parseNumber();
    }

    function parseTable() {
      i++; // {
      var arr = [], obj = null, next = 1;
      for (;;) {
        skip();
        if (text[i] === "}") { i++; break; }
        var key, val;
        if (text[i] === "[" && !/^\[=*\[/.test(text.slice(i, i + 10))) {
          i++;
          key = parseValue();
          skip();
          if (text[i] !== "]") fail("mangler ]");
          i++; skip();
          if (text[i] !== "=") fail("mangler =");
          i++;
          val = parseValue();
        } else {
          var save = i;
          var m = /^[A-Za-z_][A-Za-z0-9_]*/.exec(text.slice(i, i + 200));
          if (m && m[0] !== "true" && m[0] !== "false" && m[0] !== "nil") {
            i += m[0].length; skip();
            if (text[i] === "=") { i++; key = m[0]; val = parseValue(); }
            else { i = save; key = next; val = parseValue(); }
          } else {
            key = next;
            val = parseValue();
          }
        }
        if (typeof key === "number" && key === next && obj === null) {
          arr.push(val); next++;
        } else {
          if (obj === null) {
            obj = {};
            for (var k = 0; k < arr.length; k++) obj[k + 1] = arr[k];
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
      var m = /^[A-Za-z_][A-Za-z0-9_]*/.exec(text.slice(i, i + 200));
      if (!m) fail("forventede et navn");
      i += m[0].length; skip();
      if (text[i] !== "=") fail("mangler = efter " + m[0]);
      i++;
      out[m[0]] = parseValue();
    }
    return out;
  }

  // Læs bytes (Uint8Array) som latin1, så hver byte er ét tegn, og afkod strenge som UTF-8 bagefter.
  function fixUtf8(v) {
    if (typeof v === "string") {
      if (!/[\x80-\xff]/.test(v)) return v;
      try {
        var b = new Uint8Array(v.length);
        for (var k = 0; k < v.length; k++) b[k] = v.charCodeAt(k) & 255;
        return new TextDecoder("utf-8", { fatal: true }).decode(b);
      } catch (e) { return v; }
    }
    if (Array.isArray(v)) { for (var a = 0; a < v.length; a++) v[a] = fixUtf8(v[a]); return v; }
    if (v && typeof v === "object") {
      var o = {};
      for (var key in v) o[fixUtf8(key)] = fixUtf8(v[key]);
      return o;
    }
    return v;
  }

  function parseBytes(bytes) {
    var s = "";
    for (var k = 0; k < bytes.length; k += 0x8000) {
      s += String.fromCharCode.apply(null, bytes.subarray(k, k + 0x8000));
    }
    return fixUtf8(parseSavedVariables(s));
  }

  var api = { parseSavedVariables: parseSavedVariables, parseBytes: parseBytes };
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  else root.WCLua = api;
})(this);
