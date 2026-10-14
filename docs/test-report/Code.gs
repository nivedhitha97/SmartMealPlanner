/**
 * SmartMealPlanner test report: receives test-run results from scripts/update_test_report.py and
 * records them in this spreadsheet's "Test Cases" and "Run History" tabs. "Summary" is all formulas.
 *
 * Setup (once): Extensions → Apps Script (or a new project at script.google.com), paste this file,
 * set the TOKEN script property, then Deploy → New deployment → Web app
 * (Execute as: Me, Who has access: Anyone). See the README.
 */

// Used when the script isn't opened from the sheet itself (a standalone project at script.google.com).
const SPREADSHEET_ID = '1YKWuDnbF0zmI1NbZde3dtsLhVRfhXbsNPPZ-43Ga_AE';

function spreadsheet() {
  return SpreadsheetApp.getActiveSpreadsheet() || SpreadsheetApp.openById(SPREADSHEET_ID);
}

const TEST_CASES = 'Test Cases';
const RUN_HISTORY = 'Run History';
const TC_COLUMNS = 18; // A:R
const RH_COLUMNS = 15; // A:O
const RECENT_RUNS_SHOWN = 10;
const DATE_TIME = 'yyyy-mm-dd hh:mm';

// Test Cases columns (0-based)
const C = {
  id: 0, type: 1, suite: 2, test: 3, description: 4, source: 5, cases: 6, status: 7, lastRun: 8,
  duration: 9, runs: 10, passed: 11, failed: 12, skipped: 13, passRate: 14, recent: 15, failure: 16, key: 17,
};
const STATUS_COLUMN = { Passed: C.passed, Failed: C.failed, Skipped: C.skipped };

function doPost(e) {
  try {
    const payload = JSON.parse(e.postData.contents);
    const token = PropertiesService.getScriptProperties().getProperty('TOKEN');
    if (!token || payload.token !== token) return reply({ ok: false, error: 'unauthorized' });
    if (payload.ping) return reply({ ok: true, spreadsheet: spreadsheet().getName() });

    const lock = LockService.getScriptLock();
    lock.waitLock(30000); // a run from the Mac and one from CI can arrive together
    try {
      return reply(recordRun(payload));
    } finally {
      lock.releaseLock();
    }
  } catch (err) {
    return reply({ ok: false, error: String(err) });
  }
}

function reply(object) {
  return ContentService.createTextOutput(JSON.stringify(object)).setMimeType(ContentService.MimeType.JSON);
}

function recordRun(p) {
  const ss = spreadsheet();
  const cases = ss.getSheetByName(TEST_CASES);
  const history = ss.getSheetByName(RUN_HISTORY);

  // ---- Skip a run that is already recorded ----
  const runs = history.getLastRow() > 1 ? history.getRange(2, 1, history.getLastRow() - 1, RH_COLUMNS).getValues() : [];
  if (p.run && runs.some(r => String(r[14]) === p.run.key)) return { ok: true, duplicate: true };

  // ---- Test Cases ----
  const rows = cases.getLastRow() > 1 ? cases.getRange(2, 1, cases.getLastRow() - 1, TC_COLUMNS).getValues() : [];
  const byKey = new Map(rows.map(r => [String(r[C.key]), r]));
  const lastNumber = { Unit: 0, UI: 0 };
  rows.forEach(r => {
    const m = String(r[C.id]).match(/^(UT|UI)-(\d+)$/);
    if (m) {
      const type = m[1] === 'UT' ? 'Unit' : 'UI';
      lastNumber[type] = Math.max(lastNumber[type], Number(m[2]));
    }
  });

  function addRow(type, identifier) {
    lastNumber[type] += 1;
    const r = new Array(TC_COLUMNS).fill('');
    r[C.id] = (type === 'Unit' ? 'UT' : 'UI') + '-' + String(lastNumber[type]).padStart(3, '0');
    r[C.type] = type;
    r[C.cases] = 1;
    r[C.status] = 'Not run';
    r[C.passed] = 0;
    r[C.failed] = 0;
    r[C.skipped] = 0;
    r[C.key] = identifier;
    rows.push(r);
    byKey.set(identifier, r);
    return r;
  }

  // Every test found in the source gets a row, so new tests show up as "Not run".
  const inSource = new Set();
  (p.tests || []).forEach(t => {
    inSource.add(t.identifier);
    const r = byKey.get(t.identifier) || addRow(t.type, t.identifier);
    r[C.type] = t.type;
    r[C.suite] = t.suite;
    r[C.test] = t.name;
    r[C.description] = t.description;
    r[C.source] = t.file;
  });
  if (inSource.size) {
    rows.forEach(r => {
      const note = ' (no longer in source)';
      if (!inSource.has(String(r[C.key])) && !String(r[C.description]).endsWith(note)) r[C.description] += note;
    });
  }

  const finished = p.run ? new Date(p.run.finished * 1000) : new Date();
  (p.results || []).forEach(res => {
    let r = byKey.get(res.identifier);
    if (!r) {
      r = addRow(res.type || 'Unit', res.identifier);
      r[C.suite] = res.identifier.split('/')[0];
      r[C.test] = res.name;
      r[C.description] = (res.description || res.name) + ' (no longer in source)';
    }
    r[C.status] = res.status;
    r[C.lastRun] = finished;
    r[C.duration] = res.duration == null ? '' : Math.round(res.duration * 100) / 100;
    r[C.cases] = res.cases || 1;
    if (STATUS_COLUMN[res.status] !== undefined) r[STATUS_COLUMN[res.status]] = Number(r[STATUS_COLUMN[res.status]] || 0) + 1;
    const recent = String(r[C.recent] || '').split(' ').filter(Boolean);
    recent.push(res.status.charAt(0));
    r[C.recent] = recent.slice(-RECENT_RUNS_SHOWN).join(' ');
    r[C.failure] = res.failure || '';
  });

  rows.sort((a, b) => (a[C.type] === 'Unit' ? 0 : 1) - (b[C.type] === 'Unit' ? 0 : 1) || String(a[C.id]).localeCompare(String(b[C.id])));
  rows.forEach((r, i) => {
    const n = i + 2;
    r[C.runs] = '=L' + n + '+M' + n + '+N' + n;
    r[C.passRate] = '=IF(K' + n + '=0,"",L' + n + '/K' + n + ')';
  });
  if (rows.length) {
    ensureRows(cases, rows.length + 1);
    cases.getRange(2, 1, rows.length, TC_COLUMNS).setValues(rows.map(r => r.map((v, c) => (c === C.runs || c === C.passRate ? v : asText(v)))));
    // Writing a Date replaces the column's date-time format with a date-only one, so set it again.
    cases.getRange(2, C.lastRun + 1, rows.length, 1).setNumberFormat(DATE_TIME);
  }

  // ---- Run History (newest first) ----
  if (p.run) {
    const run = p.run;
    runs.unshift([
      runs.length + 1,
      run.started ? new Date(run.started * 1000) : '',
      finished,
      run.source,
      run.branch,
      "'" + run.commit, // keep hashes such as 1234567 or 12e4567 as text
      run.device,
      run.total,
      run.passed,
      run.failed,
      run.skipped,
      run.duration == null ? '' : run.duration,
      run.result,
      '',
      run.key,
    ]);
    runs.forEach((r, i) => {
      const n = i + 2;
      r[13] = '=IF(H' + n + '=0,"",I' + n + '/H' + n + ')';
      if (i > 0 && typeof r[5] === 'string' && !r[5].startsWith("'")) r[5] = "'" + r[5];
    });
    ensureRows(history, runs.length + 1);
    history.getRange(2, 1, runs.length, RH_COLUMNS).setValues(runs.map(r => r.map((v, c) => (c === 13 || c === 5 ? v : asText(v)))));
    history.getRange(2, 2, runs.length, 2).setNumberFormat(DATE_TIME);
  }

  return { ok: true, tests: rows.length, run: p.run ? runs.length : null };
}

/** Text that starts like a formula is stored as text. */
function asText(value) {
  return typeof value === 'string' && /^[=+\-@]/.test(value) ? "'" + value : value;
}

/** Adds rows when a tab is full and carries its formatting, status colours and filter onto them. */
function ensureRows(sheet, needed) {
  const max = sheet.getMaxRows();
  if (needed <= max) return;
  const add = Math.max(needed - max, 100);
  sheet.insertRowsAfter(max, add);
  const cols = sheet.getMaxColumns();
  const total = sheet.getMaxRows();
  sheet.getRange(2, 1, 1, cols).copyFormatToRange(sheet, 1, cols, max + 1, total);
  const rules = sheet.getConditionalFormatRules().map(rule => {
    const ranges = rule.getRanges().map(r => (r.getRow() === 2 ? sheet.getRange(2, r.getColumn(), total - 1, r.getNumColumns()) : r));
    return rule.copy().setRanges(ranges).build();
  });
  sheet.setConditionalFormatRules(rules);
  const filter = sheet.getFilter();
  if (filter) {
    filter.remove();
    sheet.getRange(1, 1, total, cols).createFilter();
  }
}
