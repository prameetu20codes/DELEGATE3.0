'use strict';

// Minimal smoke test so the CI "Unit Test" step produces a JUnit report.
const assert = require('assert');
const fs = require('fs');

let failures = 0;
function check(name, fn) {
  try {
    fn();
    process.stdout.write(`ok - ${name}\n`);
  } catch (err) {
    failures++;
    process.stdout.write(`not ok - ${name}: ${err.message}\n`);
  }
}

check('server.js is present', () => {
  assert.ok(fs.existsSync(`${__dirname}/server.js`));
});

check('server.js exposes a health endpoint', () => {
  const src = fs.readFileSync(`${__dirname}/server.js`, 'utf8');
  assert.ok(src.includes('/healthz'), 'expected a /healthz route');
});

const junit = `<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="sample-web" tests="2" failures="${failures}">
  <testcase name="server.js is present"/>
  <testcase name="server.js exposes a health endpoint"/>
</testsuite>
`;
fs.writeFileSync(`${__dirname}/junit.xml`, junit);

process.exit(failures === 0 ? 0 : 1);
