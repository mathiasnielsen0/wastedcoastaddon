// Skammens Hat (skammenshat.dk): viser WC4ever-addonets data.
// Henter den gzip-pakkede SavedVariables-fil fra /api/data, pakker den ud, læser Lua-tabellen
// (lua.js) og tegner siden. Alt regnes ud her i browseren, så serveren bare gemmer filen.
(function () {
  "use strict";

  var CLASS_COLORS = {
    WARRIOR: "#C69B6D", PALADIN: "#F48CBA", HUNTER: "#AAD372", ROGUE: "#FFF468", PRIEST: "#FFFFFF",
    SHAMAN: "#0070DD", MAGE: "#3FC7EB", WARLOCK: "#8788EE", DRUID: "#FF7C0A", DEATHKNIGHT: "#C41E3A",
    MONK: "#00FF98", DEMONHUNTER: "#A330C9", EVOKER: "#33937F",
  };
  var CLASS_DA = {
    WARRIOR: "Warrior", PALADIN: "Paladin", HUNTER: "Hunter", ROGUE: "Rogue", PRIEST: "Priest", SHAMAN: "Shaman",
    MAGE: "Mage", WARLOCK: "Warlock", DRUID: "Druid",
  };
  var FLAVOR_NAMES = {
    _forever_: "Forever", _classic_beta_: "Forever beta", _anniversary_: "Anniversary",
    _classic_era_: "Classic Era", _classic_: "Classic", _retail_: "Retail",
  };
  // Trofæerne fra WastedCoast.lua (id -> navn, beskrivelse, point)
  var TROPHIES = {
    first_death: ["Første blod", "Dø for første gang.", 5],
    deaths10: ["Fast gæst på kirkegården", "Dø 10 gange.", 10],
    deaths50: ["Kirkegårdsgænger", "Dø 50 gange.", 25],
    deaths100: ["Professionelt lig", "Dø 100 gange. Respekt.", 50],
    first_to_die: ["Første til at dø", "Vær den første i gruppen, der dør i en dungeon.", 10],
    pvp1: ["Ganket", "Bliv slået ihjel af en anden spiller.", 5],
    pvp10: ["Kanonføde", "Bliv slået ihjel af andre spillere 10 gange.", 15],
    fall: ["Tyngdekraften vinder", "Dø af at falde ned fra en klippe.", 10],
    lava: ["Gulvet er lava", "Dø i lava, ild eller slim.", 10],
    drown: ["Glemte at svømme", "Drukn eller dø af udmattelse.", 10],
    afk_pull: ["AFK midt i en pull", "Gå AFK, mens gruppen er i kamp, eller dø, mens du er AFK.", 15],
    nemesis: ["Ærkefjenden", "Bliv dræbt af den samme fjende 5 gange.", 15],
    triple: ["Hat-trick", "Dø 3 gange på 10 minutter.", 10],
    quick_exit: ["Hurtig exit", "Dø inden for et minut efter du er gået ind i en dungeon.", 10],
    wipe_first: ["Første wipe", "Vær med i dit første wipe.", 5],
    wipe10: ["Wipe-veteran", "Vær med i 10 wipes.", 25],
    healer_gone: ["Healeren er ikke hjemme", "Wipe 3 gange i samme dungeon-besøg.", 15],
    boss_first: ["Første boss", "Dræb din første boss.", 5],
    boss25: ["Bossjæger", "Dræb 25 bosser.", 25],
    clear_first: ["Instance klaret", "Klar en hel instance.", 10],
    clear10: ["Dungeon-diva", "Klar 10 instances.", 25],
    epic_first: ["Lilla fingre", "Vind dit første epic.", 10],
    epic10: ["Lootgoblin", "Vind 10 epics.", 25],
    legend: ["Gylden dag", "Vind et legendary item.", 50],
    need5: ["Need before greed", "Vind 5 items med Need.", 10],
    lvl60: ["Max level", "Nå level 60.", 25],
    lvl70: ["Max level", "Nå level 70.", 25],
    alts5: ["Alt-junkie", "Spil med 5 forskellige karakterer.", 15],
    gold1000: ["Rigmanden", "Eje 1000 guld på tværs af dine karakterer.", 15],
    night: ["Nattergalen", "Log ind mellem klokken 02 og 05 om natten.", 10],
  };
  var MILESTONE_NAMES = {
    lvl: "Levels tilsammen", max: "Max level-karakterer", dead: "Dødsfald", loot: "Rare loot", gold: "Guld tilsammen",
    boss: "Boss-kills", hours: "Timer spillet", rare: "Rare mobs", haan: "Prutter",
  };

  // ---------------------------------------------------------------- hjælpere
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function num(n) { return Math.round(n || 0).toLocaleString("da-DK"); }
  function ago(t) {
    if (!t) return "aldrig";
    var s = Math.max(0, Date.now() / 1000 - t);
    if (s < 90) return "lige nu";
    if (s < 3600) return Math.round(s / 60) + " min siden";
    if (s < 86400 * 1.5) return Math.round(s / 3600) + " t siden";
    if (s < 86400 * 30) return Math.round(s / 86400) + " d siden";
    return new Date(t * 1000).toLocaleDateString("da-DK", { day: "numeric", month: "short" });
  }
  function hours(sec) { return sec ? Math.round(sec / 3600) : 0; }
  function gold(copper) { return Math.floor((copper || 0) / 10000); }
  function list(x) { return Array.isArray(x) ? x : x && typeof x === "object" ? Object.keys(x).map(function (k) { return x[k]; }) : []; }
  function obj(x) { return x && typeof x === "object" && !Array.isArray(x) ? x : {}; }

  // ---------------------------------------------------------------- model
  function buildModel(db) {
    var members = obj(db.group && db.group.members);
    var kicked = obj(db.group && db.group.kicked);
    function canon(id) {
      var m = members[id];
      return m && m.dup && members[m.dup] ? m.dup : id;
    }
    function name(id) {
      var m = members[canon(id)];
      return (m && m.n) || id;
    }

    var friends = obj(db.friends);
    var ids = Object.keys(friends).filter(function (id) { return !kicked[id] && canon(id) === id; });
    var events = list(db.events).filter(function (e) { return e && !e.demo && e.friend; });
    events.sort(function (a, b) { return (b.time || 0) - (a.time || 0); });
    var loot = list(db.loot).filter(function (l) { return l && !l.demo && l.friend; });
    loot.sort(function (a, b) { return (b.time || 0) - (a.time || 0); });

    var people = ids.map(function (id) {
      var chars = obj(friends[id].chars);
      var cl = Object.keys(chars).map(function (n) { var c = chars[n]; c._n = n; return c; });
      cl.sort(function (a, b) { return (b.level || 0) - (a.level || 0) || (b.xp || 0) - (a.xp || 0) || (b.seen || 0) - (a.seen || 0); });
      var main = cl[0] || {};
      var seen = 0, goldSum = 0, played = 0, levels = 0;
      cl.forEach(function (c) {
        seen = Math.max(seen, c.seen || 0, c.hb || 0);
        // Guldet står som 0, hvis vennen loggede ud på en anden karakter; brug så den seneste måling
        var g = c.gold || 0;
        if (!g) {
          var gh = list(db.goldChar && db.goldChar[id] && db.goldChar[id][c._n]).filter(function (x) { return x && x[1] > 0; });
          if (gh.length) g = gh[gh.length - 1][1];
        }
        goldSum += g;
        played += (c.played && c.played.t) || 0;
        levels += c.level || 0;
      });
      var runs = obj(db.runs && db.runs[id]), bosses = 0, clears = 0, wipes = 0;
      Object.keys(runs).forEach(function (k) {
        var r = runs[k];
        wipes += r.wipes || 0; clears += r.clears || 0;
        var b = obj(r.boss); Object.keys(b).forEach(function (bn) { bosses += b[bn] || 0; });
      });
      var my = events.filter(function (e) { return canon(e.friend) === id; });
      var ach = obj(db.ach && db.ach[id]), pts = 0, trophies = [];
      Object.keys(ach).forEach(function (k) {
        var t = TROPHIES[k];
        if (t) { pts += t[2]; trophies.push({ id: k, name: t[0], desc: t[1], pts: t[2], t: ach[k] }); }
      });
      trophies.sort(function (a, b) { return a.t - b.t; });
      var rolls = obj(db.rolls && db.rolls[id]);
      var hist = list(db.goldHist && db.goldHist[id]).filter(function (p) { return p && p[1] > 0; });
      return {
        id: id, name: name(id), chars: cl, main: main, seen: seen, gold: goldSum, played: played, levels: levels,
        bosses: bosses, clears: clears, wipes: wipes,
        deaths: my.length, pvp: my.filter(function (e) { return e.pvp; }).length,
        loot: loot.filter(function (l) { return canon(l.friend) === id; }).length,
        wins: rolls.wins || 0, rolls: rolls.rolls || 0,
        pts: pts, trophies: trophies, goldHist: hist,
        legacy: (db.legacy && db.legacy[id] && db.legacy[id].p) || 0,
      };
    });
    people.sort(function (a, b) { return (b.main.level || 0) - (a.main.level || 0) || (b.main.xp || 0) - (a.main.xp || 0); });
    var byId = {};
    people.forEach(function (p) { byId[p.id] = p; });

    // Skammens hat: den, der døde sidst (samme regel som i addonet)
    var hatEv = events[0] || null;
    var hatHist = [];
    events.forEach(function (e) {
      var w = canon(e.friend);
      if (!hatHist.length || hatHist[hatHist.length - 1].id !== w) hatHist.push({ id: w, t: e.time });
    });

    // Spilletid i ugen (Weekly.lua): den nyeste uge, vi har tal for
    var rep = obj(db.weekly && db.weekly.rep);
    var weeks = Object.keys(rep).map(Number).sort(function (a, b) { return b - a; });
    var week = weeks.length ? obj(rep[weeks[0]]) : {};
    var weekPlay = Object.keys(week).map(function (id) { return { id: canon(id), p: week[id].p || 0, l: week[id].l || 0 }; })
      .filter(function (w) { return byId[w.id]; });
    var merged = {};
    weekPlay.forEach(function (w) { if (!merged[w.id] || merged[w.id].p < w.p) merged[w.id] = w; });
    weekPlay = Object.keys(merged).map(function (k) { return merged[k]; }).sort(function (a, b) { return b.p - a.p; });

    // Drillerier
    var farts = {}, gz = {};
    list(db.haan && db.haan.log).forEach(function (h) { if (h.from) { var k = canon(h.from); farts[k] = (farts[k] || 0) + 1; } });
    list(db.gz && db.gz.log).forEach(function (h) { if (h.from) { var k = canon(h.from); gz[k] = (gz[k] || 0) + 1; } });

    var killers = {};
    events.forEach(function (e) { if (e.killer && e.killer !== "Ukendt") killers[e.killer] = (killers[e.killer] || 0) + 1; });
    var topKillers = Object.keys(killers).map(function (k) { return { k: k, n: killers[k] }; })
      .sort(function (a, b) { return b.n - a.n; }).slice(0, 5);

    var ms = obj(db.milestones && db.milestones.hit);
    var milestones = Object.keys(ms).map(function (k) {
      var p = k.split(":"); return { cat: p[0], goal: Number(p[1]), t: ms[k].t || 0, by: ms[k].by };
    }).filter(function (m) { return MILESTONE_NAMES[m.cat]; }).sort(function (a, b) { return b.t - a.t; });

    return {
      people: people, byId: byId, name: name, canon: canon, events: events, loot: loot,
      hat: hatEv ? { id: canon(hatEv.friend), ev: hatEv, hist: hatHist.slice(0, 6) } : null,
      weekPlay: weekPlay, farts: farts, gz: gz, topKillers: topKillers, milestones: milestones,
      totals: {
        levels: people.reduce(function (s, p) { return s + p.levels; }, 0),
        deaths: events.length,
        bosses: people.reduce(function (s, p) { return s + p.bosses; }, 0),
        hours: hours(people.reduce(function (s, p) { return s + p.played; }, 0)),
        gold: gold(people.reduce(function (s, p) { return s + p.gold; }, 0)),
      },
    };
  }

  // ---------------------------------------------------------------- tegning
  function who(m, id) {
    var p = m.byId[id];
    var col = p && CLASS_COLORS[p.main.class] || "var(--ink)";
    return '<b style="color:' + col + '">' + esc(m.name(id)) + "</b>";
  }
  function charName(c) { return esc(c._n || c.name || "") + (c.surname || c.sur ? " " + esc(c.surname || c.sur) : ""); }

  function sparkline(hist) {
    if (hist.length < 2) return "";
    var pts = hist.slice(-60);
    var t0 = pts[0][0], t1 = pts[pts.length - 1][0] || t0 + 1;
    var lo = Infinity, hi = -Infinity;
    pts.forEach(function (p) { lo = Math.min(lo, p[1]); hi = Math.max(hi, p[1]); });
    if (hi === lo) hi = lo + 1;
    var W = 200, H = 30;
    var d = pts.map(function (p, i) {
      var x = ((p[0] - t0) / (t1 - t0 || 1)) * W, y = H - 2 - ((p[1] - lo) / (hi - lo)) * (H - 4);
      return (i ? "L" : "M") + x.toFixed(1) + " " + y.toFixed(1);
    }).join(" ");
    var last = pts[pts.length - 1];
    var ly = H - 2 - ((last[1] - lo) / (hi - lo)) * (H - 4);
    return '<svg viewBox="0 0 ' + W + " " + H + '" preserveAspectRatio="none" role="img" aria-label="Guld over tid">' +
      '<path d="' + d + ' L' + W + " " + H + " L0 " + H + ' Z" fill="rgba(242,182,50,.12)"/>' +
      '<path d="' + d + '" fill="none" stroke="var(--gold)" stroke-width="2" vector-effect="non-scaling-stroke" stroke-linejoin="round"/>' +
      '<circle cx="' + W + '" cy="' + ly.toFixed(1) + '" r="3" fill="var(--gold)"/></svg>';
  }

  function renderHero(m) {
    if (!m.hat) {
      return '<div class="hero"><div class="hatbox"><img src="skammens-hat.png" alt=""></div><div>' +
        '<div class="eyebrow">Skammens hat</div><h1>Ingen er døde endnu</h1><p>Hatten venter på den første.</p></div></div>';
    }
    var e = m.hat.ev;
    var dies = m.events.filter(function (x) { return m.canon(x.friend) === m.hat.id; }).length;
    var killer = e.killer && e.killer !== "Ukendt" ? "døde til <b>" + esc(e.killer) + "</b>" : "døde af ukendte årsager";
    var hist = m.hat.hist.slice(1).map(function (h) { return '<span class="chip">' + who(m, h.id) + "</span>"; }).join("");
    return '<div class="hero"><div class="hatbox"><img src="skammens-hat.png" alt="Skammens hat"></div><div>' +
      '<div class="eyebrow">Skammens hat bæres lige nu af</div>' +
      '<h1><span class="who">' + esc(m.name(m.hat.id)) + "</span></h1>" +
      "<p>" + charName(e) + " (level " + esc(e.level || "?") + ") " + killer +
      (e.zone ? " i <b>" + esc(e.zone) + "</b>" : "") + " " + ago(e.time) + ". Det er dødsfald nummer " + dies +
      ". Hatten sidder fast, til en anden dør.</p>" +
      (hist ? '<div class="hat-hist">Før det: ' + hist + "</div>" : "") +
      "</div></div>";
  }

  function renderTotals(m) {
    var t = m.totals;
    function box(n, l) { return '<div class="total"><div class="n">' + num(n) + '</div><div class="l">' + l + "</div></div>"; }
    return '<div class="totals">' + box(t.levels, "Levels tilsammen") + box(t.deaths, "Dødsfald") +
      box(t.bosses, "Boss-kills") + box(t.hours, "Timer spillet") + box(t.gold, "Guld i alt") + "</div>";
  }

  function renderCards(m, snapT) {
    var html = m.people.map(function (p) {
      var c = p.main, col = CLASS_COLORS[c.class] || "var(--ink)";
      var online = p.seen && snapT && snapT - p.seen < 300 && Date.now() / 1000 - snapT < 1800;
      var hat = m.hat && m.hat.id === p.id;
      var xp = Math.max(0, Math.min(100, c.xp || 0));
      var hist = p.goldHist;
      return '<article class="card' + (hat ? " has-hat" : "") + '">' +
        '<div class="head"><span class="dot' + (online ? " on" : "") + '" title="' + (online ? "Online" : "Offline") + '"></span>' +
        '<span class="nm" style="color:' + col + '">' + esc(p.name) + "</span>" +
        (hat ? '<img src="skammens-hat.png" alt="Bærer Skammens hat" title="Bærer Skammens hat">' : "") + "</div>" +
        '<div class="char"><b>' + charName(c) + "</b> · " + esc(CLASS_DA[c.class] || c.class || "") +
        (c.zone ? " · " + esc(c.zone) : "") + "</div>" +
        '<div class="lvl"><span>Level <b>' + (c.level || "?") + "</b></span>" +
        '<span class="bar" title="' + xp + '% XP"><i style="width:' + xp + '%"></i></span><span>' + xp + "%</span></div>" +
        '<div class="stats"><div class="d"><b>' + p.deaths + "</b>døde" + (p.pvp ? " (" + p.pvp + " PvP)" : "") + "</div>" +
        "<div><b>" + p.loot + "</b>loot</div><div><b>" + num(hours(p.played)) + "</b>timer</div></div>" +
        (hist.length > 1 ? '<div class="spark">' + sparkline(hist) + "<span>" + num(gold(hist[hist.length - 1][1])) + " g</span></div>" : "") +
        '<div class="seen">' + (online ? "Online nu" : "Sidst set " + ago(p.seen)) + " · " + p.chars.length + " karakter" +
        (p.chars.length === 1 ? "" : "er") + "</div></article>";
    }).join("");
    return '<section><h2>Banden <small>' + m.people.length + " venner, sorteret efter level</small></h2>" +
      '<div class="cards">' + html + "</div></section>";
  }

  var COLS = [
    { k: "levels", l: "Levels" }, { k: "deaths", l: "Døde" }, { k: "pvp", l: "PvP-døde" }, { k: "bosses", l: "Bosser" },
    { k: "clears", l: "Clears" }, { k: "wipes", l: "Wipes" }, { k: "loot", l: "Loot" }, { k: "wins", l: "Rolls vundet" },
    { k: "pts", l: "Trofæpoint" }, { k: "hours", l: "Timer" }, { k: "goldG", l: "Guld" },
  ];
  var sortKey = "pts", sortDir = -1;

  function renderTable(m) {
    var rows = m.people.map(function (p) {
      return { p: p, levels: p.levels, deaths: p.deaths, pvp: p.pvp, bosses: p.bosses, clears: p.clears, wipes: p.wipes,
        loot: p.loot, wins: p.wins, pts: p.pts, hours: hours(p.played), goldG: gold(p.gold) };
    });
    var best = {};
    COLS.forEach(function (c) { best[c.k] = Math.max.apply(null, rows.map(function (r) { return r[c.k]; })); });
    rows.sort(function (a, b) { return (a[sortKey] - b[sortKey]) * sortDir || a.p.name.localeCompare(b.p.name); });
    var head = '<tr><th data-k="name">Ven</th>' + COLS.map(function (c) {
      return '<th data-k="' + c.k + '"' + (c.k === sortKey ? ' aria-sort="' + (sortDir < 0 ? "descending" : "ascending") + '"' : "") + ">" + c.l + "</th>";
    }).join("") + "</tr>";
    var body = rows.map(function (r, i) {
      return "<tr><td><span class=\"rank\">" + (i + 1) + "</span>" + who(m, r.p.id) + "</td>" + COLS.map(function (c) {
        return '<td' + (r[c.k] && r[c.k] === best[c.k] ? ' class="best"' : "") + ">" + num(r[c.k]) + "</td>";
      }).join("") + "</tr>";
    }).join("");
    return '<section id="rangliste"><h2>Ranglisten <small>Klik på en kolonne for at sortere</small></h2>' +
      '<div class="tablewrap"><table><thead>' + head + "</thead><tbody>" + body + "</tbody></table></div></section>";
  }

  function hbars(items, fmt) {
    var max = Math.max.apply(null, items.map(function (x) { return x.v; }).concat([1]));
    return '<ul class="hbars">' + items.map(function (x) {
      return '<li><span class="n">' + x.label + '</span><span class="t"><i style="width:' + (100 * x.v / max).toFixed(1) +
        '%"></i></span><span class="v">' + fmt(x.v) + "</span></li>";
    }).join("") + "</ul>";
  }

  function renderCols(m) {
    var deaths = m.events.slice(0, 8).map(function (e) {
      return "<li><span class=\"what\">" + who(m, m.canon(e.friend)) + " døde" +
        (e.killer && e.killer !== "Ukendt" ? " til " + esc(e.killer) : "") + (e.pvp ? '<span class="pvp">PvP</span>' : "") + "</span>" +
        '<span class="when">' + ago(e.time) + "</span>" +
        '<span class="sub">' + charName(e) + ", level " + esc(e.level || "?") + (e.zone ? " · " + esc(e.zone) : "") + "</span></li>";
    }).join("");
    var killers = m.topKillers.length ? '<div class="minor"><h3>Farligste fjender</h3>' +
      hbars(m.topKillers.map(function (k) { return { label: esc(k.k), v: k.n }; }), function (v) { return v + "×"; }) + "</div>" : "";

    var loot = m.loot.slice(0, 8).map(function (l) {
      var q = Math.max(2, Math.min(5, l.quality || 2));
      return '<li><span class="what">' + who(m, m.canon(l.friend)) + ' fik <span class="q' + q + '">[' + esc(l.name || "?") + "]</span></span>" +
        '<span class="when">' + ago(l.time) + "</span>" +
        '<span class="sub">' + (l.how ? '<span class="how">' + esc(l.how) + "</span> · " : "") + esc(l.zone || "") + "</span></li>";
    }).join("");

    var week = m.weekPlay.length ? '<div class="minor"><h3>Ugens nolifer (timer i denne uge)</h3>' +
      hbars(m.weekPlay.slice(0, 8).map(function (w) { return { label: who(m, w.id), v: w.p / 3600 }; }),
        function (v) { return v.toFixed(1).replace(".", ","); }) + "</div>" : "";

    var fartList = Object.keys(m.farts).filter(function (id) { return m.byId[id]; })
      .map(function (id) { return { label: who(m, id), v: m.farts[id] }; }).sort(function (a, b) { return b.v - a.v; }).slice(0, 6);
    var gzList = Object.keys(m.gz).filter(function (id) { return m.byId[id]; })
      .map(function (id) { return { label: who(m, id), v: m.gz[id] }; }).sort(function (a, b) { return b.v - a.v; }).slice(0, 6);
    var ms = m.milestones.slice(0, 5).map(function (x) {
      return "<li><span class=\"what\">" + esc(MILESTONE_NAMES[x.cat]) + ": <b>" + num(x.goal) + "</b></span>" +
        '<span class="when">' + ago(x.t) + "</span>" + (x.by && m.byId[x.by] ? '<span class="sub">Rundet af ' + who(m, x.by) + "</span>" : "") + "</li>";
    }).join("");

    return '<section class="cols">' +
      '<div class="col"><h2>Kirkegården</h2><ul class="feed">' + (deaths || "<li>Ingen døde endnu.</li>") + "</ul>" + killers + "</div>" +
      '<div class="col"><h2>Loot</h2><ul class="feed">' + (loot || "<li>Intet loot endnu.</li>") + "</ul>" + week + "</div>" +
      '<div class="col"><h2>Drillerier</h2>' +
      (fartList.length ? '<div class="minor first"><h3>Flest prutter sendt</h3>' + hbars(fartList, num) + "</div>" : "") +
      (gzList.length ? '<div class="minor"><h3>Flest "Gz" sagt</h3>' + hbars(gzList, num) + "</div>" : "") +
      (ms ? '<div class="minor"><h3>Bandens milepæle</h3><ul class="feed">' + ms + "</ul></div>" : "") +
      "</div></section>";
  }

  function renderTrophies(m) {
    var people = m.people.slice().sort(function (a, b) { return b.pts - a.pts; });
    return '<section><h2>Trofæskabet <small>Point fra addonets trofæer</small></h2><div class="troph">' +
      people.map(function (p) {
        return '<div class="tro"><div class="h">' + who(m, p.id) + "<span>" + p.pts + ' p</span></div><div class="list">' +
          (p.trophies.length ? p.trophies.map(function (t) {
            return '<span title="' + esc(t.desc) + " (" + t.pts + ' p)">' + esc(t.name) + "</span>";
          }).join("") : '<span>Ingen endnu</span>') + "</div></div>";
      }).join("") + "</div></section>";
  }

  // ---------------------------------------------------------------- data og opstart
  var state = { flavors: [], flavor: null, db: null, meta: null };

  function render() {
    var app = document.getElementById("app");
    if (!state.db) return;
    var m = buildModel(state.db);
    var snapT = state.meta && (state.meta.mtime || (state.meta.t && state.meta.t / 1000)) || (state.db.session && state.db.session.last);
    var flv = state.flavors.length > 1 ? '<div class="flavors" role="group" aria-label="Spilversion">' + state.flavors.map(function (f) {
      return '<button type="button" data-flavor="' + esc(f.flavor) + '" aria-pressed="' + (f.flavor === state.flavor) + '">' +
        esc(FLAVOR_NAMES[f.flavor] || f.flavor) + "</button>";
    }).join("") + "</div>" : "";
    var meta = state.meta || {};
    app.innerHTML = '<div class="wrap">' +
      '<header class="top"><img src="wc4ever-logo.png" alt="WC4ever"><div class="brand"><b>Skammens Hat</b><span>Wasted Coast Forever</span></div>' +
      flv + '<div class="sync">Opdateret <b>' + ago(meta.t ? meta.t / 1000 : snapT) + "</b>" + (meta.navn ? " fra " + esc(meta.navn) : "") + "</div></header>" +
      renderHero(m) + renderTotals(m) + renderCards(m, snapT) + renderTable(m) + renderCols(m) + renderTrophies(m) +
      "<footer>Data kommer fra WC4ever-addonet og opdateres, når nogen logger ud eller skriver /reload.</footer>" +
      (window.WC_PREVIEW ? '<p class="demo-note">Designforslag med rigtige data fra ' + esc(meta.navn || "addonet") + "s SavedVariables.</p>" : "") +
      "</div>";
  }

  document.addEventListener("click", function (ev) {
    var th = ev.target.closest && ev.target.closest("th[data-k]");
    if (th && th.getAttribute("data-k") !== "name") {
      var k = th.getAttribute("data-k");
      if (k === sortKey) sortDir = -sortDir; else { sortKey = k; sortDir = -1; }
      render();
      return;
    }
    var b = ev.target.closest && ev.target.closest("button[data-flavor]");
    if (b) load(b.getAttribute("data-flavor"));
  });

  function showError(msg) {
    document.getElementById("app").innerHTML = '<div class="wrap"><header class="top"><img src="wc4ever-logo.png" alt="">' +
      '<div class="brand"><b>Skammens Hat</b><span>Wasted Coast Forever</span></div></header><p class="loading">' + esc(msg) + "</p></div>";
  }

  async function gunzip(buf) {
    var ds = new DecompressionStream("gzip");
    var out = new Response(new Blob([buf]).stream().pipeThrough(ds));
    return new Uint8Array(await out.arrayBuffer());
  }

  async function load(flavor) {
    if (window.WC_PREVIEW) {
      state.flavor = flavor; state.db = window.WC_PREVIEW.dbs[flavor];
      state.meta = state.flavors.filter(function (f) { return f.flavor === flavor; })[0];
      render(); return;
    }
    try {
      var r = await fetch("/api/data?flavor=" + encodeURIComponent(flavor), { cache: "no-cache" });
      if (!r.ok) throw new Error("Kunne ikke hente data (" + r.status + ")");
      var bytes = await gunzip(await r.arrayBuffer());
      var parsed = window.WCLua.parseBytes(bytes);
      if (!parsed.WastedCoastDB) throw new Error("Filen indeholder ikke WC4ever-data");
      state.flavor = flavor; state.db = parsed.WastedCoastDB;
      state.meta = state.flavors.filter(function (f) { return f.flavor === flavor; })[0] || null;
      try { localStorage.setItem("wc-flavor", flavor); } catch (e) { /* ligegyldigt */ }
      render();
    } catch (e) {
      showError(String(e.message || e));
    }
  }

  async function start() {
    if (window.WC_PREVIEW) {
      state.flavors = window.WC_PREVIEW.flavors;
      return load(state.flavors[0].flavor);
    }
    try {
      var r = await fetch("/api/list", { cache: "no-cache" });
      var j = await r.json();
      state.flavors = (j.flavors || []);
      if (!state.flavors.length) return showError("Ingen data endnu. Start sync-programmet og log ud af WoW (eller skriv /reload).");
      var want = null;
      try { want = localStorage.getItem("wc-flavor"); } catch (e) { /* ligegyldigt */ }
      var pick = state.flavors.filter(function (f) { return f.flavor === want; })[0] ||
        state.flavors.filter(function (f) { return f.flavor === "_forever_"; })[0] || state.flavors[0];
      load(pick.flavor);
    } catch (e) {
      showError("Kunne ikke kontakte serveren.");
    }
  }

  window.WCSite = { buildModel: buildModel };
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start); else start();
})();
