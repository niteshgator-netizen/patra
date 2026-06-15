/* eslint-env node */
/* eslint-disable no-console */
/**
 * Sidebar route-resolvability audit (runnable with plain `node`).
 *
 * Why not a vitest spec: vitest 4.1.0 cannot start against the installed vite 5.4.21
 * (ERR_PACKAGE_PATH_NOT_EXPORTED: vite has no './module-runner' export) — a project-wide
 * env/dep mismatch, not this code. This is the prompt's sanctioned FALLBACK: a runnable node
 * audit that enumerates EVERY sidebar destination and FAILS if any named route the menu links
 * to requires a `:param` (a `:x` not followed by `?`) that the menu call does not supply — i.e.
 * the exact "Missing required param navigationPath" class of crash.
 *
 * Run: node app/javascript/dashboard/components-next/sidebar/specs/sidebarRouteResolvability.audit.mjs
 * Exit 0 = pass; exit 1 = a sidebar item would crash the router.
 */
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const sidebarPath = join(here, '..', 'Sidebar.vue');
const routesDir = join(here, '..', '..', '..', 'routes'); // app/javascript/dashboard/routes

const sidebar = readFileSync(sidebarPath, 'utf-8');

// 1) Enumerate EVERY menu destination from Sidebar.vue (do not hand-pick a subset).
//    accountScopedRoute('NAME', { key: ... }) -> { name, suppliedKeys }
const named = [
  ...sidebar.matchAll(/accountScopedRoute\(\s*'([^']+)'\s*(?:,\s*\{([^}]*)\})?/g),
].map(m => ({
  name: m[1],
  suppliedKeys: [...(m[2] || '').matchAll(/(\w+)\s*:/g)].map(x => x[1]),
}));
//    accountScopedUrl('PATH')
const urls = [...sidebar.matchAll(/accountScopedUrl\(\s*'([^']+)'\s*\)/g)].map(
  m => m[1]
);

// 2) Read every route file so we can map a route NAME to its declared path.
const walk = dir =>
  readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    const p = join(dir, entry.name);
    if (entry.isDirectory()) return walk(p);
    return entry.name.endsWith('.js') || entry.name.endsWith('.ts') ? [p] : [];
  });
const routeSrc = walk(routesDir)
  .map(f => readFileSync(f, 'utf-8'))
  .join('\n/* ---- file boundary ---- */\n');

// 3) For a route NAME, find the `path:` nearest its `name:` declaration and extract the
//    REQUIRED params (`:x` not followed by `?`). Returns null if the name is not declared.
const escapeRe = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const requiredParamsForName = name => {
  const decls = [
    ...routeSrc.matchAll(new RegExp(`name:\\s*'${escapeRe(name)}'`, 'g')),
  ];
  if (decls.length === 0) return null;
  const candidates = decls.flatMap(decl => {
    const winStart = Math.max(0, decl.index - 400);
    const win = routeSrc.slice(winStart, Math.min(routeSrc.length, decl.index + 400));
    return [...win.matchAll(/path:\s*([^\n]+)/g)].map(pm => ({
      value: pm[1],
      dist: Math.abs(winStart + pm.index - decl.index),
    }));
  });
  if (candidates.length === 0) return null;
  const best = candidates.reduce((a, b) => (b.dist < a.dist ? b : a));
  return [...best.value.matchAll(/:(\w+)(\??)/g)]
    .filter(x => x[2] !== '?')
    .map(x => x[1]);
};

// 4) Run the checks.
const failures = [];
named.forEach(dest => {
  const required = requiredParamsForName(dest.name);
  if (required === null) {
    failures.push(`menu route '${dest.name}' is not declared in any route file`);
    return;
  }
  const supplied = new Set(['accountId', ...dest.suppliedKeys]);
  const missing = required.filter(p => !supplied.has(p));
  if (missing.length > 0) {
    failures.push(
      `menu route '${dest.name}' requires param(s) [${missing.join(', ')}] that accountScopedRoute does not supply`
    );
  }
});

// Explicit regression guards for THIS bug.
if (sidebar.includes("accountScopedRoute('portals_index')")) {
  failures.push(
    "Sidebar still uses accountScopedRoute('portals_index') — the param-requiring form that throws 'Missing required param navigationPath'"
  );
}
if (!sidebar.includes("accountScopedUrl('portals')")) {
  failures.push(
    "Help Center is not pointed at the resolvable accountScopedUrl('portals') target"
  );
}

// 5) Report + exit.
console.log(
  `Sidebar destinations enumerated: ${named.length} named route(s), ${urls.length} url(s).`
);
console.log(`Named routes: ${named.map(d => d.name).join(', ')}`);
console.log(`Url paths: ${urls.join(', ')}`);
if (failures.length > 0) {
  console.error(`\nAUDIT FAILED (${failures.length}):`);
  failures.forEach(f => console.error(`  - ${f}`));
  process.exit(1);
}
console.log(
  '\nAUDIT PASSED: every sidebar named route resolves with the params the menu supplies; Help Center no longer uses the param-requiring portals_index form.'
);
process.exit(0);
