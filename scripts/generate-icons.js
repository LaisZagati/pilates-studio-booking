// Regenerates every app/store icon and splash from assets/brand-mark.svg.
// Replace that SVG with the studio logo, then run: node scripts/generate-icons.js (needs `sharp`).
const sharp = require("sharp"); const fs = require("fs");
const svg = fs.readFileSync("assets/brand-mark.svg");
// maskable: mark scaled to 72% inside full-bleed background (Android safe zone)
const inner = svg.toString().replace('<rect width="1024" height="1024" fill="#f4eee3"/>', "");
const maskable = Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><rect width="1024" height="1024" fill="#f4eee3"/><g>${inner.replace(/<\/?svg[^>]*>/g,"")}</g></svg>`);
const splash = (w,h) => Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h}"><rect width="${w}" height="${h}" fill="#fbf8f2"/><g transform="translate(${(w-600)/2} ${(h-600)/2}) scale(${600/1024})">${inner.replace(/<\/?svg[^>]*>/g,"")}</g></svg>`);
const feature = Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 500"><rect width="1024" height="500" fill="#f4eee3"/><circle cx="820" cy="250" r="190" fill="#e7dccb"/><path d="M700 330 C750 190 880 180 940 290" fill="none" stroke="#8c7457" stroke-width="26" stroke-linecap="round"/><circle cx="950" cy="273" r="26" fill="#8c7457"/><path d="M90 250 H520" stroke="#2f2a24" stroke-width="3" opacity=".2"/></svg>`);
(async () => {
  const out = [
    [svg, 192, "public/icons/icon-192.png"], [svg, 512, "public/icons/icon-512.png"],
    [maskable, 512, "public/icons/maskable-512.png"], [maskable, 192, "public/icons/maskable-192.png"],
    [svg, 180, "src/app/apple-icon.png"], [svg, 48, "src/app/icon.png"],
    [svg, 1024, "assets/store/app-store-icon-1024.png"], [svg, 512, "assets/store/play-icon-512.png"],
    [maskable, 1024, "assets/icon-only.png"], // source for @capacitor/assets
  ];
  for (const [src, size, file] of out) await sharp(src).resize(size, size).flatten({ background: "#f4eee3" }).png().toFile(file);
  await sharp(splash(2732,2732)).png().toFile("assets/splash.png");
  await sharp(splash(2732,2732)).png().toFile("assets/splash-dark.png");
  await sharp(feature).png().toFile("assets/store/play-feature-graphic-1024x500.png");
  console.log("icons ok");
})();
