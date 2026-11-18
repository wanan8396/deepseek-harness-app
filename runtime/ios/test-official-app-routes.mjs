import assert from 'node:assert/strict';
import { createOfficialAppRoutePolicy } from './official-app-routes.mjs';

const workspaceId = 'workspace-private';
const owned = 'session-550e8400-e29b-41d4-a716-446655440000';
const foreign = 'session-550e8400-e29b-41d4-a716-446655440001';
const key = 'test-only-non-credential';
const policy = createOfficialAppRoutePolicy({ workspaceId, hasSession: id => id === owned,
  containsSensitiveText: value => value.includes(key) });
const wire = (method, args) => JSON.stringify({ type: 'client-request', rpcId: 'test', method, payload: { args } });
const call = (method, request) => policy.admitRequest('POST', `/api/${method}`, wire(method, { request }));
const modelPrompt = { sessionId: owned, requestId: 'test', mode: 'queue' };
assert.equal(call('session/create', { cwd: '/other' }).status, 403);
assert.equal(call('session/create', { workspaceId: 'workspace-other' }).status, 403);
assert.equal(call('session/create', { sessionId: foreign }).status, 403);
assert.equal(call('session/create', { agentPreset: 'execute-something-else' }).status, 403);
const created = call('session/create', { sessionId: owned });
assert.equal(created.ok, true);
assert.equal(JSON.parse(created.body).payload.args.request.workspaceId, workspaceId);
assert.equal(call('session/prompt', { ...modelPrompt, content: [{ type: 'text', text: '雪' }] }).ok, true);
assert.equal(call('session/prompt', { ...modelPrompt, content: [{ type: 'text', text: key }] }).status, 400);
assert.equal(call('session/prompt', { ...modelPrompt,
  content: [{ type: 'text', text: key.slice(0, 9) }, { type: 'text', text: key.slice(9) }] }).status, 415);
assert.equal(call('session/prompt', { ...modelPrompt, content: [{ type: 'file', receiptId: 'other' }] }).status, 415);
assert.equal(call('session/prompt', { ...modelPrompt, content: [{ type: 'text', text: 'x'.repeat(17000) }] }).status, 415);
assert.equal(call('session/updateQueue', { sessionId: owned, itemId: 'q', action: { kind: 'edit',
  content: [{ type: 'text', text: key }] } }).status, 400);
assert.equal(call('session/rename', { sessionId: foreign, title: 'hello' }).status, 403);
assert.equal(call('session/events', { address: { kind: 'subagent', parentSessionId: owned, childSessionId: foreign } }).status, 403);
assert.equal(policy.admitRequest('GET', '/api/file?path=opaque', '').status, 404);
assert.equal(policy.admitRequest('POST', '/api/session/list?query=y', wire('session/list', {})).status, 404);
assert.equal(policy.admitRequest('POST', '/api/terminal/open', wire('terminal/open', {})).status, 404);
assert.equal(policy.admitRequest('POST', '/api/session/rename', wire('session/list', {})).status, 400);
assert.equal(policy.admitStream('session/follow', { args: { request: { address: { kind: 'session', sessionId: foreign } } } }), false);
assert.equal(policy.admitStream('session/follow', { args: { request: { address: { kind: 'session', sessionId: owned } } } }), true);
assert.equal(policy.admitStream('$events', { args: {} }), true);
assert.equal(policy.admitStream('workspace/follow', { args: { workspaceId: 'other' } }), false);
console.log(JSON.stringify({ appRouteFenceVerified: true, canonicalWorkspaceSelectedByHost: true,
  foreignSessionBlocked: true, credentialBlockedBeforePersistence: true, attachmentsAndDesktopRoutesWithheld: true }));
