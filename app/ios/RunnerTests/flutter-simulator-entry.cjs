'use strict';

// CI stages this entry only into the Debug Simulator test app. Use the same
// model fixture as XCTest; the production probe still boots the actual Host
// and its official mailbox, SDK adapter, approvals, and workspace tools.
const fs = require('node:fs');
const path = require('node:path');
const { installFetchFixture } = require('./chat-ci-entry.cjs');

const report = process.argv[2];
const probe = fs.readFileSync(path.join(path.dirname(report), 'probe-path.txt'), 'utf8');
installFetchFixture();
void require(probe).main(report);
