// preview/host.js
// The page side of the preview: draws what wow.lua describes on a canvas, measures text,
// loads the addon's .tga images and sounds, and sends mouse/keyboard to Lua.
"use strict";

(function () {
  const canvas = document.getElementById("screen");
  const ctx = canvas.getContext("2d");
  const measureCtx = document.createElement("canvas").getContext("2d");
  let handler = null;

  // ---------------------------------------------------------------- fonts
  const FONT_CSS = {
    Cinzel: "'YCinzel', serif",
    PatrickHand: "'YPatrick', cursive",
    Friz: "'Friz Quadrata TT', 'Friz Quadrata', Georgia, serif",
    Morpheus: "'YCinzel', serif",
    ArialN: "'Arial Narrow', Arial, sans-serif",
    Skurri: "Georgia, serif",
  };
  const FONT_WEIGHT = { Morpheus: "700 " };
  function cssFont(key, px) { return (FONT_WEIGHT[key] || "") + px + "px " + (FONT_CSS[key] || FONT_CSS.Friz); }

  // |cAARRGGBB ... |r  -> runs of { text, color }
  function parseRuns(text, base) {
    const runs = [];
    let color = base, i = 0, cur = "";
    while (i < text.length) {
      if (text[i] === "|" && i + 1 < text.length) {
        const n = text[i + 1];
        if ((n === "c" || n === "C") && /^[0-9a-fA-F]{8}$/.test(text.substr(i + 2, 8))) {
          if (cur) { runs.push({ text: cur, color }); cur = ""; }
          const h = text.substr(i + 2, 8);
          color = "rgb(" + parseInt(h.substr(2, 2), 16) + "," + parseInt(h.substr(4, 2), 16) + "," + parseInt(h.substr(6, 2), 16) + ")";
          i += 10; continue;
        }
        if (n === "r" || n === "R") { if (cur) { runs.push({ text: cur, color }); cur = ""; } color = base; i += 2; continue; }
        if (n === "|") { cur += "|"; i += 2; continue; }
        if (n === "T") { const e = text.indexOf("|t", i); if (e > 0) { cur += "  "; i = e + 2; continue; } }
        if (n === "n") { cur += "\n"; i += 2; continue; }
      }
      cur += text[i]; i++;
    }
    if (cur) runs.push({ text: cur, color });
    return runs;
  }
  function plain(text) { return parseRuns(String(text), null).map(r => r.text).join(""); }

  function emWidth(key, s) {
    measureCtx.font = cssFont(key, 100);
    return measureCtx.measureText(s).width / 100;
  }

  // Break text into lines no wider than maxW (in em * size units)
  function wrap(key, size, text, maxW) {
    const out = [];
    for (const para of text.split("\n")) {
      const words = para.split(/(\s+)/);
      let line = "";
      for (const w of words) {
        if (w === "") continue;
        const test = line + w;
        if (line !== "" && emWidth(key, test.trimEnd()) * size > maxW + 0.5 && !/^\s+$/.test(w)) {
          out.push(line.trimEnd());
          line = w.trimStart();
        } else {
          line = test;
        }
      }
      out.push(line.trimEnd());
    }
    return out;
  }

  // ---------------------------------------------------------------- textures
  const textures = new Map();
  const missing = new Set();

  function decodeTGA(buf) {
    const d = new Uint8Array(buf);
    const idLen = d[0], type = d[2], w = d[12] | (d[13] << 8), h = d[14] | (d[15] << 8), bpp = d[16], desc = d[17];
    if (type !== 2 && type !== 10) throw new Error("TGA type " + type + " not supported");
    const bytes = bpp / 8;
    const c = document.createElement("canvas"); c.width = w; c.height = h;
    const cx = c.getContext("2d");
    const img = cx.createImageData(w, h);
    const px = img.data;
    let p = 18 + idLen;
    const topDown = (desc & 0x20) !== 0;
    const pixels = new Uint8Array(w * h * 4);
    let n = 0;
    function put(b, g, r, a) { pixels[n++] = r; pixels[n++] = g; pixels[n++] = b; pixels[n++] = a; }
    if (type === 2) {
      for (let i = 0; i < w * h; i++) {
        put(d[p], d[p + 1], d[p + 2], bytes === 4 ? d[p + 3] : 255); p += bytes;
      }
    } else {
      while (n < w * h * 4) {
        const hdr = d[p++], count = (hdr & 0x7f) + 1;
        if (hdr & 0x80) { const b = d[p], g = d[p + 1], r = d[p + 2], a = bytes === 4 ? d[p + 3] : 255; p += bytes; for (let k = 0; k < count; k++) put(b, g, r, a); }
        else for (let k = 0; k < count; k++) { put(d[p], d[p + 1], d[p + 2], bytes === 4 ? d[p + 3] : 255); p += bytes; }
      }
    }
    for (let y = 0; y < h; y++) {
      const src = topDown ? y : h - 1 - y;
      px.set(pixels.subarray(src * w * 4, (src + 1) * w * 4), y * w * 4);
    }
    cx.putImageData(img, 0, 0);
    return c;
  }

  function special(name, draw, size) {
    const c = document.createElement("canvas"); c.width = c.height = size || 64;
    draw(c.getContext("2d"), c.width);
    textures.set(name, { img: c, w: c.width, h: c.height, ok: true });
  }
  special("special:white", (g, s) => { g.fillStyle = "#fff"; g.fillRect(0, 0, s, s); }, 8);
  special("special:minimap", (g, s) => {
    const r = s / 2;
    const grd = g.createRadialGradient(r * 0.8, r * 0.7, 4, r, r, r);
    grd.addColorStop(0, "#5d6b3a"); grd.addColorStop(0.7, "#3c4a2a"); grd.addColorStop(1, "#22291a");
    g.fillStyle = grd; g.beginPath(); g.arc(r, r, r - 6, 0, Math.PI * 2); g.fill();
    g.strokeStyle = "#7a6338"; g.lineWidth = 7; g.beginPath(); g.arc(r, r, r - 4, 0, Math.PI * 2); g.stroke();
    g.strokeStyle = "#c9a85e"; g.lineWidth = 2; g.beginPath(); g.arc(r, r, r - 7, 0, Math.PI * 2); g.stroke();
    g.fillStyle = "#ffd200"; g.beginPath(); g.moveTo(r, r - 7); g.lineTo(r + 5, r + 6); g.lineTo(r, r + 3); g.lineTo(r - 5, r + 6); g.fill();
  }, 280);
  special("special:trackingborder", (g, s) => {
    const cx = s * 0.33, r = s * 0.29;
    g.strokeStyle = "#8a6d2f"; g.lineWidth = s * 0.07; g.beginPath(); g.arc(cx, cx, r, 0, Math.PI * 2); g.stroke();
    g.strokeStyle = "#e4c374"; g.lineWidth = s * 0.025; g.beginPath(); g.arc(cx, cx, r, 0, Math.PI * 2); g.stroke();
  }, 108);
  special("special:minimapbg", (g, s) => { g.fillStyle = "rgba(10,10,10,0.9)"; g.beginPath(); g.arc(s / 2, s / 2, s / 2, 0, Math.PI * 2); g.fill(); }, 64);
  special("special:highlightdisc", (g, s) => {
    const grd = g.createRadialGradient(s / 2, s / 2, 0, s / 2, s / 2, s / 2);
    grd.addColorStop(0, "rgba(255,240,200,0.7)"); grd.addColorStop(1, "rgba(255,240,200,0)");
    g.fillStyle = grd; g.fillRect(0, 0, s, s);
  }, 64);
  special("special:grip", (g, s) => {
    g.strokeStyle = "rgba(230,200,140,0.9)"; g.lineWidth = s * 0.06;
    for (const k of [0.35, 0.6, 0.85]) { g.beginPath(); g.moveTo(s * k, s * 0.95); g.lineTo(s * 0.95, s * k); g.stroke(); }
  }, 32);
  special("special:portrait", (g, s) => {
    g.fillStyle = "#2a3346"; g.beginPath(); g.arc(s / 2, s / 2, s / 2, 0, Math.PI * 2); g.fill();
    g.fillStyle = "#c9a27e"; g.beginPath(); g.arc(s / 2, s * 0.42, s * 0.2, 0, Math.PI * 2); g.fill();
    g.beginPath(); g.ellipse(s / 2, s * 0.92, s * 0.32, s * 0.25, 0, 0, Math.PI * 2); g.fill();
  }, 64);

  const BLIZZARD = {
    "interface/buttons/white8x8": "special:white",
    "interface/minimap/minimap-trackingborder": "special:trackingborder",
    "interface/minimap/ui-minimap-background": "special:minimapbg",
    "interface/minimap/ui-minimap-zoombutton-highlight": "special:highlightdisc",
    "interface/chatframe/ui-chatim-sizegrabber-up": "special:grip",
    "interface/chatframe/ui-chatim-sizegrabber-down": "special:grip",
    "interface/chatframe/ui-chatim-sizegrabber-highlight": "special:grip",
    "interface/icons/inv_misc_dice_01": "../Yatzy/Media/Textures/UI/Die5.tga",
  };

  function resolvePath(file) {
    let f = String(file).replace(/\\/g, "/");
    if (f.startsWith("special:portrait")) return "special:portrait";
    if (f.startsWith("special:")) return f;
    const low = f.toLowerCase().replace(/\.(tga|blp)$/, "");
    if (BLIZZARD[low]) return BLIZZARD[low];
    if (low.startsWith("interface/addons/yatzy/")) {
      let rest = f.substr("interface/addons/yatzy/".length);
      if (!/\.(tga|blp)$/i.test(rest)) rest += ".tga";
      return "../Yatzy/" + rest.replace(/\.blp$/i, ".tga");
    }
    return null;
  }

  function getTexture(file) {
    const url = resolvePath(file);
    if (!url) {
      if (!missing.has(file)) { missing.add(file); console.warn("No stand-in for texture", file); }
      return null;
    }
    let t = textures.get(url);
    if (!t) {
      t = { ok: false };
      textures.set(url, t);
      fetch(url).then(r => { if (!r.ok) throw new Error(r.status); return r.arrayBuffer(); })
        .then(buf => { t.img = decodeTGA(buf); t.w = t.img.width; t.h = t.img.height; t.ok = true; redraw = true; })
        .catch(e => { t.failed = true; console.warn("Texture not found:", url, e.message); });
    }
    return t.ok ? t : null;
  }

  const tintCache = new Map();
  function tinted(t, key, r, g, b) {
    r = Math.round(r * 50) / 50; g = Math.round(g * 50) / 50; b = Math.round(b * 50) / 50;
    if (r >= 0.99 && g >= 0.99 && b >= 0.99) return t.img;
    const k = key + "|" + r + "|" + g + "|" + b;
    let c = tintCache.get(k);
    if (!c) {
      c = document.createElement("canvas"); c.width = t.w; c.height = t.h;
      const x = c.getContext("2d");
      x.drawImage(t.img, 0, 0);
      x.globalCompositeOperation = "multiply";
      x.fillStyle = "rgb(" + Math.round(r * 255) + "," + Math.round(g * 255) + "," + Math.round(b * 255) + ")";
      x.fillRect(0, 0, t.w, t.h);
      x.globalCompositeOperation = "destination-in";
      x.drawImage(t.img, 0, 0);
      if (tintCache.size > 400) tintCache.clear();
      tintCache.set(k, c);
    }
    return c;
  }

  // ---------------------------------------------------------------- world background
  let world = null;
  function drawWorld() {
    if (!world || world.width !== canvas.width || world.height !== canvas.height) {
      world = document.createElement("canvas"); world.width = canvas.width; world.height = canvas.height;
      const g = world.getContext("2d");
      const grd = g.createLinearGradient(0, 0, 0, world.height);
      grd.addColorStop(0, "#56607a"); grd.addColorStop(0.45, "#7d7a5e"); grd.addColorStop(0.5, "#5a5a3a"); grd.addColorStop(1, "#2f3320");
      g.fillStyle = grd; g.fillRect(0, 0, world.width, world.height);
      for (let i = 0; i < 2500; i++) {
        g.fillStyle = "rgba(" + (Math.random() < 0.5 ? "0,0,0" : "255,255,220") + "," + (Math.random() * 0.06) + ")";
        const x = Math.random() * world.width, y = world.height * 0.5 + Math.random() * world.height * 0.5;
        g.fillRect(x, y, 2 + Math.random() * 30, 1 + Math.random() * 6);
      }
    }
    ctx.drawImage(world, 0, 0);
  }

  // ---------------------------------------------------------------- the host API (called from Lua)
  const sounds = new Map();
  let redraw = true;
  const host = {
    consumeRedraw() { const r = redraw; redraw = false; return r; },
    setHandler(fn) { handler = fn; },
    fetchText(url) {
      const x = new XMLHttpRequest();
      x.open("GET", url + (url.includes("?") ? "&" : "?") + "t=" + Date.now(), false);
      x.overrideMimeType("text/plain; charset=utf-8");
      x.send();
      return x.status === 200 ? x.responseText : undefined;
    },
    fileExists(url) {
      if (sounds.has(url)) return sounds.get(url);
      const x = new XMLHttpRequest();
      x.open("HEAD", url, false);
      try { x.send(); } catch (e) { sounds.set(url, false); return false; }
      const ok = x.status === 200;
      sounds.set(url, ok);
      return ok;
    },
    textWidth(key, text) { return emWidth(key, plain(text)); },
    wrapLines(key, size, text, width) { return wrap(key, size, plain(text), width).length; },

    beginFrame() {
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.globalAlpha = 1; ctx.globalCompositeOperation = "source-over"; ctx.filter = "none";
      drawWorld();
    },
    endFrame() {},
    clip(x, y, w, h) { ctx.save(); ctx.beginPath(); ctx.rect(x, y, w, h); ctx.clip(); },
    unclip() { ctx.restore(); },

    rect(x, y, w, h, r, g, b, a, blend, rot) {
      ctx.save();
      ctx.globalAlpha = Math.max(0, Math.min(1, a));
      if (blend === "ADD") ctx.globalCompositeOperation = "lighter";
      ctx.fillStyle = "rgb(" + Math.round(r * 255) + "," + Math.round(g * 255) + "," + Math.round(b * 255) + ")";
      if (rot) { ctx.translate(x + w / 2, y + h / 2); ctx.rotate(-rot); ctx.fillRect(-w / 2, -h / 2, w, h); }
      else ctx.fillRect(x, y, w, h);
      ctx.restore();
    },
    gradient(x, y, w, h, orient, r1, g1, b1, a1, r2, g2, b2, a2) {
      // WoW: HORIZONTAL goes left -> right, VERTICAL bottom -> top
      const grd = orient === "VERTICAL" ? ctx.createLinearGradient(0, y + h, 0, y) : ctx.createLinearGradient(x, 0, x + w, 0);
      const col = (r, g, b, a) => "rgba(" + Math.round(r * 255) + "," + Math.round(g * 255) + "," + Math.round(b * 255) + "," + Math.max(0, Math.min(1, a)) + ")";
      grd.addColorStop(0, col(r1, g1, b1, a1)); grd.addColorStop(1, col(r2, g2, b2, a2));
      ctx.save(); ctx.fillStyle = grd; ctx.fillRect(x, y, w, h); ctx.restore();
    },
    texture(file, x, y, w, h, l, r, t, b, cr, cg, cb, ca, blend, rot, desat, tileX, tileY, sx, sy, sw, sh) {
      const tex = getTexture(file);
      if (!tex) return;
      const img = tinted(tex, resolvePath(file), cr, cg, cb);
      ctx.save();
      ctx.globalAlpha = Math.max(0, Math.min(1, ca));
      if (blend === "ADD") ctx.globalCompositeOperation = "lighter";
      if (desat) ctx.filter = "grayscale(1)";
      if (tileX > 0 || tileY > 0) {
        const pat = ctx.createPattern(img, "repeat");
        const scale = tileX > 0 ? tileX : tileY;
        pat.setTransform(new DOMMatrix([scale, 0, 0, scale, sx, sy]));
        ctx.fillStyle = pat;
        ctx.fillRect(sx, sy, sw, sh);
        ctx.restore();
        return;
      }
      const iw = tex.w, ih = tex.h;
      const flipX = l > r, flipY = t > b;
      let u0 = Math.min(l, r) * iw, u1 = Math.max(l, r) * iw;
      let v0 = Math.min(t, b) * ih, v1 = Math.max(t, b) * ih;
      u0 = Math.max(0, u0); v0 = Math.max(0, v0); u1 = Math.min(iw, u1); v1 = Math.min(ih, v1);
      if (u1 - u0 < 0.01 || v1 - v0 < 0.01) { ctx.restore(); return; }
      if (rot || flipX || flipY) {
        const cx = rot ? x + w / 2 : sx + sw / 2, cy = rot ? y + h / 2 : sy + sh / 2;
        const dw = rot ? w : sw, dh = rot ? h : sh;
        ctx.translate(cx, cy);
        if (rot) ctx.rotate(-rot);
        ctx.scale(flipX ? -1 : 1, flipY ? -1 : 1);
        ctx.drawImage(img, u0, v0, u1 - u0, v1 - v0, -dw / 2, -dh / 2, dw, dh);
      } else {
        ctx.drawImage(img, u0, v0, u1 - u0, v1 - v0, sx, sy, sw, sh);
      }
      ctx.restore();
    },
    text(text, key, px, x, y, w, h, r, g, b, a, jh, jv, wrapOn, flags, sr, sg, sb, sa, sdx, sdy, lineH, maxLines) {
      if (px < 1) return;
      const base = "rgb(" + Math.round(r * 255) + "," + Math.round(g * 255) + "," + Math.round(b * 255) + ")";
      ctx.save();
      ctx.font = cssFont(key, px);
      ctx.textBaseline = "middle";
      ctx.globalAlpha = Math.max(0, Math.min(1, a));
      // lines (word wrap, or cut with "..." when it doesn't fit)
      const size = px;
      let lines;
      const raw = String(text);
      if (wrapOn && w > 0) {
        lines = wrapRuns(raw, key, size, w);
      } else {
        lines = raw.split(/\n|\|n/);
      }
      let maxL = maxLines > 0 ? maxLines : Infinity;
      if (h > 0 && lineH > 0 && wrapOn) maxL = Math.min(maxL, Math.max(1, Math.floor((h + 1) / lineH)));
      if (lines.length > maxL) { lines = lines.slice(0, maxL); lines[maxL - 1] = ellipsize(lines[maxL - 1] + "...", key, size, w); }
      if (!wrapOn && w > 0) lines = lines.map(l => ellipsize(l, key, size, w));
      const total = lines.length * lineH;
      let top = y;
      if (jv === "MIDDLE") top = y + (h - total) / 2; else if (jv === "BOTTOM") top = y + h - total;
      let color = base;
      for (let i = 0; i < lines.length; i++) {
        const runs = parseRuns(lines[i], color);
        const lw = runs.reduce((s, rr) => s + ctx.measureText(rr.text).width, 0);
        let lx = x;
        if (jh === "CENTER") lx = x + (w - lw) / 2; else if (jh === "RIGHT") lx = x + w - lw;
        const ly = top + i * lineH + lineH / 2 + px * 0.06;
        let cx = lx;
        for (const rr of runs) {
          if (sa > 0.01 && (sdx || sdy)) {
            ctx.fillStyle = "rgba(" + Math.round(sr * 255) + "," + Math.round(sg * 255) + "," + Math.round(sb * 255) + "," + Math.min(1, sa / Math.max(a, 0.001)) + ")";
            ctx.fillText(rr.text, cx + sdx, ly + sdy);
          }
          if (flags && flags.indexOf("OUTLINE") >= 0) {
            ctx.strokeStyle = "rgba(0,0,0,0.9)"; ctx.lineWidth = flags.indexOf("THICK") >= 0 ? 3 : 1.6; ctx.lineJoin = "round";
            ctx.strokeText(rr.text, cx, ly);
          }
          ctx.fillStyle = rr.color;
          ctx.fillText(rr.text, cx, ly);
          cx += ctx.measureText(rr.text).width;
          color = rr.color;
        }
      }
      ctx.restore();
    },

    error(text, count) { showError(text, count); },
    playSound(url) {
      if (document.getElementById("mute").checked) return;
      try { const au = new Audio(url); au.volume = Number(document.getElementById("volume").value); au.play().catch(() => {}); } catch (e) {}
    },
    chat(text, r, g, b) { addChat(text, r, g, b); },
    chatReset() { document.getElementById("chatlines").innerHTML = ""; },
    notice(text, r, g, b) { showNotice(text, r, g, b); },
    store(key, val) { try { if (val) localStorage.setItem(key, val); else localStorage.removeItem(key); } catch (e) {} },
    load(key) { try { const v = localStorage.getItem(key); return v === null ? undefined : v; } catch (e) { return undefined; } },
    panel(json) { renderPanel(JSON.parse(json)); },
    log(t) { console.log(t); },
  };

  function wrapRuns(raw, key, size, w) {
    // wrap on the plain text, then put the color codes back by walking both strings
    const lines = [];
    for (const para of raw.split(/\n|\|n/)) {
      const words = para.split(/(\s+)/);
      let line = "", lineW = "";
      for (const word of words) {
        if (word === "") continue;
        const test = lineW + plain(word);
        if (lineW !== "" && emWidth(key, test.trimEnd()) * size > w + 0.5 && !/^\s+$/.test(word)) {
          lines.push(line.trimEnd()); line = word.trimStart(); lineW = plain(word).trimStart();
        } else { line += word; lineW = test; }
      }
      lines.push(line.trimEnd());
    }
    return lines;
  }
  function ellipsize(line, key, size, w) {
    if (!(w > 0)) return line;
    const p = plain(line);
    if (emWidth(key, p) * size <= w + 1) return line;
    let s = p;
    while (s.length > 0 && emWidth(key, s + "...") * size > w + 1) s = s.slice(0, -1);
    return s + "...";
  }

  window.host = host;

  // ---------------------------------------------------------------- page bits: chat, notices, errors, panel
  function addChat(text, r, g, b) {
    const box = document.getElementById("chatlines");
    const div = document.createElement("div");
    const base = "rgb(" + Math.round(r * 255) + "," + Math.round(g * 255) + "," + Math.round(b * 255) + ")";
    for (const run of parseRuns(String(text), base)) {
      const span = document.createElement("span");
      span.style.color = run.color; span.textContent = run.text; div.appendChild(span);
    }
    box.appendChild(div);
    while (box.childNodes.length > 200) box.removeChild(box.firstChild);
    box.scrollTop = box.scrollHeight;
  }
  function showNotice(text, r, g, b) {
    const n = document.getElementById("notice");
    const div = document.createElement("div");
    div.className = "notice";
    div.style.color = "rgb(" + Math.round(r * 255) + "," + Math.round(g * 255) + "," + Math.round(b * 255) + ")";
    div.textContent = plain(text);
    n.appendChild(div);
    setTimeout(() => div.classList.add("fade"), 3000);
    setTimeout(() => div.remove(), 4500);
  }
  function showError(text, count) {
    const box = document.getElementById("errors");
    box.parentElement.hidden = false;
    let el = [...box.children].find(e => e.dataset.text === text);
    if (!el) {
      el = document.createElement("pre"); el.dataset.text = text; box.prepend(el);
    }
    el.textContent = (count > 1 ? "(" + count + "x) " : "") + text;
    document.getElementById("errcount").textContent = box.children.length;
  }

  function renderPanel(members) {
    const box = document.getElementById("members");
    box.innerHTML = "";
    for (const m of members) {
      const row = document.createElement("div");
      row.className = "member" + (m.viewing ? " viewing" : "") + (m.online ? "" : " offline");
      const games = m.online && m.addon ? `<span class="tag">${m.games} spel</span>` : "";
      row.innerHTML = `
        <div class="mtop">
          <span class="name">${m.full}${m.me ? " <em>(du)</em>" : ""}</span>
          <span class="meta">${m.level} ${m.class}${m.addon ? "" : " · utan addon"}</span>
        </div>
        <div class="mctl">
          ${m.addon ? `<button data-act="view" ${m.viewing || !m.online ? "disabled" : ""}>${m.viewing ? "Visas" : "Se som"}</button>` : ""}
          ${m.me ? "" : `<label><input type="checkbox" data-act="online" ${m.online ? "checked" : ""}> Online</label>`}
          ${m.me || !m.addon ? "" : `<label title="Spelar sina drag själv"><input type="checkbox" data-act="auto" ${m.auto ? "checked" : ""}> Spelar själv</label>`}
          ${m.me || !m.addon ? "" : `<select data-act="answer" title="Svar på inbjudningar">
              <option value="accept" ${m.answer === "accept" ? "selected" : ""}>Tackar ja</option>
              <option value="decline" ${m.answer === "decline" ? "selected" : ""}>Tackar nej</option>
              <option value="wait" ${m.answer === "wait" ? "selected" : ""}>Svarar inte</option></select>`}
          ${games}
        </div>`;
      row.querySelectorAll("[data-act]").forEach(el => {
        const act = el.dataset.act;
        const ev = el.tagName === "BUTTON" ? "click" : "change";
        el.addEventListener(ev, () => {
          if (act === "view") call("view", m.short);
          else if (act === "online") call("online", m.short, el.checked);
          else if (act === "auto") call("bot", m.short, "auto", el.checked);
          else if (act === "answer") call("bot", m.short, "answer", el.value);
        });
      });
      box.appendChild(row);
    }
  }

  // ---------------------------------------------------------------- talking to Lua
  function call(cmd, a, b, c, d) {
    if (!handler) return;
    try { return handler(cmd, a, b, c, d); }
    catch (e) { showError(String(e && e.message || e), 1); }
  }
  window.previewCall = call;

  function toPixels(e) {
    const r = canvas.getBoundingClientRect();
    return [(e.clientX - r.left) * canvas.width / r.width, (e.clientY - r.top) * canvas.height / r.height];
  }
  function mods(e) { call("mods", e.ctrlKey, e.shiftKey, e.altKey); }
  const BUTTONS = ["LeftButton", "MiddleButton", "RightButton"];
  canvas.addEventListener("mousemove", e => { mods(e); call("mousemove", ...toPixels(e)); });
  canvas.addEventListener("mousedown", e => { canvas.focus({ preventScroll: true }); mods(e); call("mousedown", ...toPixels(e), BUTTONS[e.button] || "LeftButton"); e.preventDefault(); });
  window.addEventListener("mouseup", e => { mods(e); call("mouseup", ...toPixels(e), BUTTONS[e.button] || "LeftButton"); });
  canvas.addEventListener("wheel", e => { mods(e); call("wheel", ...toPixels(e), e.deltaY < 0 ? 1 : -1); e.preventDefault(); }, { passive: false });
  canvas.addEventListener("contextmenu", e => e.preventDefault());
  canvas.addEventListener("mouseleave", () => call("mousemove", -100, -100));

  const KEYS = { Escape: "ESCAPE", Enter: "ENTER", " ": "SPACE", Tab: "TAB", Backspace: "BACKSPACE",
                 ArrowUp: "UP", ArrowDown: "DOWN", ArrowLeft: "LEFT", ArrowRight: "RIGHT" };
  const chatInput = document.getElementById("chatinput");
  window.addEventListener("keydown", e => {
    if (document.activeElement === chatInput) {
      if (e.key === "Enter") {
        const t = chatInput.value.trim(); chatInput.value = ""; chatInput.blur();
        if (t) call("slash", t);
      } else if (e.key === "Escape") { chatInput.value = ""; chatInput.blur(); }
      return;
    }
    if (["INPUT", "SELECT", "TEXTAREA"].includes(document.activeElement && document.activeElement.tagName)) return;
    mods(e);
    if (e.key === "Enter" || e.key === "/") {
      chatInput.focus();
      if (e.key === "/") { chatInput.value = "/"; e.preventDefault(); }
      return;
    }
    const k = KEYS[e.key] || (e.key.length === 1 ? e.key.toUpperCase() : e.key.toUpperCase());
    call("key", k);
    if (e.key === "Escape") e.preventDefault();
  });
  window.addEventListener("keyup", mods);
  window.addEventListener("beforeunload", () => call("save"));

  // ---------------------------------------------------------------- screen size
  function applyScreen() {
    const [w, h] = document.getElementById("res").value.split("x").map(Number);
    const scale = Number(document.getElementById("uiscale").value);
    document.getElementById("uiscaleval").textContent = Math.round(scale * 100) + "%";
    canvas.width = w; canvas.height = h;
    redraw = true;
    fitCanvas();
    call("screen", w, h, scale);
  }
  function fitCanvas() {
    const wrapEl = document.getElementById("stage");
    const r = wrapEl.getBoundingClientRect();
    // "#native" in the address: show the game screen at 1:1 pixels (scroll to look around)
    const native = location.hash.includes("native");
    document.body.classList.toggle("native", native);
    const s = native ? 1 : Math.min(r.width / canvas.width, r.height / canvas.height);
    const frame = document.getElementById("frame");
    frame.style.width = Math.floor(canvas.width * s) + "px";
    frame.style.height = Math.floor(canvas.height * s) + "px";
  }
  window.addEventListener("resize", fitCanvas);
  document.getElementById("res").addEventListener("change", applyScreen);
  document.getElementById("uiscale").addEventListener("input", applyScreen);
  // sound on/off and volume are remembered in this browser (they only affect the preview page)
  for (const id of ["mute", "volume"]) {
    const el = document.getElementById(id);
    try {
      const v = localStorage.getItem("yatzy-preview-ui/" + id);
      if (v !== null) { if (el.type === "checkbox") el.checked = v === "1"; else el.value = v; }
    } catch (e) {}
    el.addEventListener("change", () => {
      try { localStorage.setItem("yatzy-preview-ui/" + id, el.type === "checkbox" ? (el.checked ? "1" : "0") : el.value); } catch (e) {}
    });
  }
  for (const id of ["combat", "moving", "taxi", "secrets"]) {
    document.getElementById(id).addEventListener("change", e => call("state", id, e.target.checked));
  }
  document.getElementById("btn-reload").addEventListener("click", () => call("reload"));
  document.getElementById("btn-toggle").addEventListener("click", () => call("slash", "/yatzy"));
  document.getElementById("btn-reset").addEventListener("click", () => {
    if (confirm("Ta bort alla sparade spel och inställningar i förhandsvisningen?")) call("reset");
  });
  document.getElementById("btn-clearerr").addEventListener("click", () => {
    document.getElementById("errors").innerHTML = ""; document.getElementById("errcount").textContent = "0";
    document.getElementById("errors").parentElement.hidden = true;
  });

  // ---------------------------------------------------------------- start
  async function start() {
    const status = document.getElementById("loading");
    try {
      const fonts = [new FontFace("YCinzel", "url(../Yatzy/Media/Fonts/Cinzel.ttf)"),
                     new FontFace("YPatrick", "url(../Yatzy/Media/Fonts/PatrickHand.ttf)")];
      for (const f of fonts) { await f.load(); document.fonts.add(f); }
    } catch (e) { console.warn("font load", e); }
    status.textContent = "Startar addonet…";
    await new Promise(r => setTimeout(r, 30));
    const main = host.fetchText("main.lua");
    try {
      fengari.load(main, "@preview/main.lua")();
    } catch (e) {
      showError("main.lua: " + (e && e.message || e), 1);
    }
    status.remove();
    applyScreen();
    let last = performance.now();
    function frame(t) {
      const dt = Math.min(0.25, (t - last) / 1000); last = t;
      call("tick", dt);
      requestAnimationFrame(frame);
    }
    requestAnimationFrame(frame);
  }
  start();
})();
