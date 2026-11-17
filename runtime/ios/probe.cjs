'use strict';

// Node-only smoke probe. This file never imports DSH or claims DSH readiness.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { pathToFileURL } = require('node:url');
const requirements = require('./requirements.json');

function satisfiesFloor(version, constraint) {
  const actual = /^v?(\d+)\.(\d+)\.(\d+)$/.exec(version);
  const floor = /^>=(\d+)\.(\d+)\.(\d+)$/.exec(constraint);
  if (!actual || !floor) return false;
  for (let i = 1; i <= 3; i += 1) {
    if (Number(actual[i]) !== Number(floor[i])) return Number(actual[i]) > Number(floor[i]);
  }
  return true;
}

function compatibility(version, constraint, capabilities) {
  const versionCompatible = satisfiesFloor(version, constraint);
  const missing = Object.keys(capabilities).filter((key) => capabilities[key] !== true);
  return { versionCompatible, runtimeCompatible: versionCompatible && missing.length === 0, missing };
}

function atomicReport(destination, report) {
  if (!path.isAbsolute(destination)) throw new Error('REPORT_PATH_INVALID');
  const parent = path.dirname(destination);
  if (!fs.statSync(parent).isDirectory()) throw new Error('REPORT_DIRECTORY_INVALID');
  const temp = path.join(parent, `.node-probe-${crypto.randomBytes(12).toString('hex')}.tmp`);
  try {
    fs.writeFileSync(temp, JSON.stringify(report, null, 2) + '\n', { flag: 'wx', mode: 0o600 });
    fs.renameSync(temp, destination);
  } finally {
    try { fs.unlinkSync(temp); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
}

function fsSmoke(reportPath) {
  const file = path.join(path.dirname(reportPath), `.node-fs-${crypto.randomBytes(12).toString('hex')}`);
  try {
    fs.writeFileSync(file, 'embedded-node-smoke', { flag: 'wx', mode: 0o600 });
    return fs.readFileSync(file, 'utf8') === 'embedded-node-smoke';
  } catch { return false; }
  finally { try { fs.unlinkSync(file); } catch {} }
}

async function collectReport(reportPath) {
  const capabilities = {
    filesystemWriteRead: fsSmoke(reportPath),
    getBuiltinModule: false,
    sqlite: false,
    sqliteFts5: false,
    intl: typeof Intl === 'object' && typeof Intl.DateTimeFormat === 'function',
    importMetaMain: false,
    importMetaFilename: false,
    importMetaDirname: false,
  };
  try {
    capabilities.getBuiltinModule = typeof process.getBuiltinModule === 'function'
      && typeof process.getBuiltinModule('node:fs').readFileSync === 'function';
  } catch {}
  let db;
  try {
    const sqlite = require('node:sqlite');
    db = new sqlite.DatabaseSync(':memory:');
    capabilities.sqlite = db.prepare('SELECT 42 AS value').get().value === 42;
    db.exec('CREATE VIRTUAL TABLE probe USING fts5(text)');
    db.prepare('INSERT INTO probe(text) VALUES (?)').run('embedded smoke');
    capabilities.sqliteFts5 = db.prepare('SELECT count(*) AS total FROM probe WHERE probe MATCH ?').get('smoke').total === 1;
  } catch {} finally { try { db?.close(); } catch {} }
  try {
    const meta = await import(pathToFileURL(path.join(__dirname, 'meta-probe.mjs')).href);
    capabilities.importMetaMain = meta.main === false;
    capabilities.importMetaFilename = typeof meta.filename === 'string';
    capabilities.importMetaDirname = typeof meta.dirname === 'string';
  } catch {}
  const gate = compatibility(process.versions.node, requirements.engine.node, capabilities);
  return {
    schemaVersion: 1,
    phase: 'probeReady',
    reportCompatible: gate.runtimeCompatible,
    probeReady: true,
    engineReady: false,
    scope: 'embedded-node-only-not-dsh-startup',
    engine: requirements.engine,
    requiredNode: requirements.engine.node,
    versions: { node: process.versions.node, mobile: process.versions.mobile ?? null,
      v8: process.versions.v8, modules: process.versions.modules, napi: process.versions.napi },
    node: { version: process.versions.node, mobile: process.versions.mobile ?? null,
      v8: process.versions.v8, modules: process.versions.modules, napi: process.versions.napi,
      platform: process.platform, arch: process.arch },
    jitless: { requested: process.execArgv.includes('--jitless'),
      recipeExpected: true, runtimeStateIndependentlyVerified: false },
    capabilities,
    ...gate,
    unverified: ['dsh-profile-startup', 'native-addon-require-builtin-ios', 'http-web-and-rpc',
      'model-request', 'native-tools', 'background-lifecycle'],
  };
}

async function main(reportPath) {
  // node_start supports one instance per app process; keep it alive, not restartable.
  setInterval(() => {}, 60_000);
  try {
    if (!reportPath || !path.isAbsolute(reportPath)) throw new Error('REPORT_PATH_INVALID');
    atomicReport(reportPath, await collectReport(reportPath));
  } catch {
    // Machine-only message: never serialize error messages, paths, tokens or argv.
    try { atomicReport(reportPath, { schemaVersion: 1, phase: 'probeFailed', probeReady: false,
      engineReady: false, runtimeCompatible: false, errorCode: 'NODE_PROBE_FAILED' }); } catch {}
    console.error('NODE_PROBE_FAILED');
  }
}

module.exports = { satisfiesFloor, compatibility, atomicReport, collectReport };
if (require.main === module) void main(process.argv[2]);
