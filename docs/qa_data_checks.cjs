// Structural content checks only; not linguistic/source certification.
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '..');
const directory = path.join(root, 'om_sai_ram/assets/content');
const files = fs.readdirSync(directory).filter(name => /^satcharita_.*\.json$/.test(name));
const results = [];
for (const file of files) {
  const language = file.match(/^satcharita_(.*)\.json$/)[1];
  const rows = JSON.parse(fs.readFileSync(path.join(directory, file), 'utf8'));
  function check(caseId, checkName, actual, expected) {
    results.push({case_id: caseId, language, check_name: checkName,
      status: JSON.stringify(actual) === JSON.stringify(expected) ? 'Pass' : 'Fail',
      actual, expected, scope: 'Bundled JSON structure only'});
  }
  check('COM-03', 'Entry count', rows.length, language === 'mr' ? 53 : 47);
  const excluded = language === 'mr' ? [] : [17, 19, 44, 50, 52, 53];
  const expectedNumbers = Array.from({length: 53}, (_, i) => i + 1).filter(n => !excluded.includes(n));
  check('COM-03', 'Unique ordered original-number mapping', rows.map(row => row.number), expectedNumbers);
  check('READ-01', 'All chapter bodies and titles nonempty and language matches',
    rows.every(row => row.content?.trim() && row.title?.trim() && row.language === language), true);
  check('LANG-06', 'No Unicode replacement characters (not an OCR quality verdict)',
    rows.filter(row => (row.content + row.title).includes('\uFFFD')).map(row => row.number), []);
  for (const [start, end] of [[16, 17], [18, 19], [43, 44], [51, 53]]) {
    const row = rows.find(row => row.number === start);
    const label = row?.chapterLabel?.replace(/[–—]/g, '-');
    check('COM-03', `Range ${start}-${end} metadata`, label,
      language === 'mr' ? String(start) : `${start}-${end}`);
  }
}
const source = fs.readFileSync(path.join(root, 'om_sai_ram/lib/core/providers/language_provider.dart'), 'utf8');
const codes = [...source.matchAll(/^\s+\w+\('([a-z]+)',/gm)].map(match => match[1]).sort();
const assetCodes = files.map(name => name.match(/^satcharita_(.*)\.json$/)[1]).sort();
results.push({case_id: 'LANG-01', check_name: 'All 18 enum codes have bundled books',
  status: JSON.stringify(codes) === JSON.stringify(assetCodes) ? 'Pass' : 'Fail', actual: assetCodes, expected: codes,
  scope: 'Source/asset consistency, not chooser interaction'});
const analysis = fs.readFileSync('/tmp/omsairam-flutter-analyze.log', 'utf8');
const severities = {};
for (const severity of ['error', 'warning', 'info']) {
  severities[severity] = (analysis.match(new RegExp(`^\\s*${severity} •`, 'gm')) || []).length;
}
console.log(JSON.stringify({executed_at_utc: new Date().toISOString(),
  scope: 'Structural asset checks only; all scripts/fonts/OCR/source comparison remain uncertified',
  languages: files.length, chapters: files.reduce((sum, file) => sum + JSON.parse(fs.readFileSync(path.join(directory, file))).length, 0),
  summary: {checks: results.length, passed: results.filter(row => row.status === 'Pass').length,
    failed: results.filter(row => row.status === 'Fail').length}, analyzer: severities, results}, null, 2));
process.exitCode = results.some(row => row.status === 'Fail') ? 1 : 0;