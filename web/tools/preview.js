// Laver én selvstændig HTML-fil af websitet med indbyggede data (til designforslag/test).
// Brug: node tools/preview.js <WastedCoast.lua> <ud.html> [navn]
const fs = require("fs"), path = require("path");
const pub = path.join(__dirname, "..", "public");
const L = require(path.join(pub, "lua.js"));
const [, , src, out, navn] = process.argv;
const db = L.parseBytes(fs.readFileSync(src)).WastedCoastDB;
for (const k of ["seen", "lootSeen", "settings"]) delete db[k];
const mtime = Math.floor(fs.statSync(src).mtimeMs / 1000);
const preview = { flavors: [{ flavor: "_forever_", t: mtime * 1000, mtime, navn: navn || "" }], dbs: { _forever_: db } };
const img = (f) => "data:image/png;base64," + fs.readFileSync(path.join(pub, f)).toString("base64");
let css = fs.readFileSync(path.join(pub, "style.css"), "utf8");
let js = fs.readFileSync(path.join(pub, "app.js"), "utf8");
js = js.replace(/"skammens-hat\.png"/g, JSON.stringify(img("skammens-hat.png"))).replace(/skammens-hat\.png/g, img("skammens-hat.png"))
       .replace(/wc4ever-logo\.png/g, img("wc4ever-logo.png"));
const html = `<title>Skammens Hat</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Cinzel:wght@600;800&family=Inter:wght@400;500;600;700&family=Pixelify+Sans:wght@500&display=swap">
<style>${css}</style>
<div id="app"><p class="loading">Henter bandens data…</p></div>
<script>window.WC_PREVIEW = ${JSON.stringify(preview).replace(/</g, "\\u003c")};</script>
<script>${js}</script>
`;
fs.writeFileSync(out, html);
console.log("skrev", out, html.length, "bytes");
