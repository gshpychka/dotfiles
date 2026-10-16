// Reconcile only our failure notifier through Maintainerr's supported API.
// Existing credential is read at runtime from the private DB, never Nix store/logs.
const fs = require('node:fs');
const { DatabaseSync } = require('node:sqlite');
const { isDeepStrictEqual } = require('node:util');
async function main() {
  const desired = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
  const db = new DatabaseSync('/var/lib/maintainerr/maintainerr.sqlite', { readOnly: true });
  const settings = db.prepare('SELECT apikey FROM settings LIMIT 1').get();
  const groupIds = db.prepare('SELECT id FROM rule_group WHERE isActive = 1 ORDER BY id').all().map(x => x.id);
  const headers = { 'content-type': 'application/json', 'x-api-key': settings.apikey || '' };
  const base = desired.baseUrl;
  async function api(route, body) {
    const response = await fetch(base + route, { method: body ? 'POST' : 'GET', headers,
      ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(5000) });
    if (!response.ok) throw Error('Maintainerr settings API HTTP ' + response.status);
    const result = await response.json();
    if (result && result.code !== undefined && result.code !== 1) throw Error('Maintainerr rejected settings update');
    return result;
  }
  let configurations;
  // Readiness checks only. Never retry a potentially successful POST.
  for (let attempt = 0; attempt < 30; attempt++) {
    try { configurations = await api('/notifications/configurations'); break; }
    catch (error) { if (attempt === 29) throw error; await new Promise(resolve => setTimeout(resolve, 1000)); }
  }
  const sources = configurations.filter(x => x.name === desired.credentialSourceName && x.agent === 'telegram');
  if (sources.length !== 1 || !sources[0].options.botAuthToken || !sources[0].options.chatId) {
    throw Error('Expected one existing Telegram credential source; preserve state and review manually');
  }
  const options = { ...sources[0].options, messageThreadId: desired.messageThreadId };
  const matches = configurations.filter(x => x.name === desired.name);
  if (matches.length > 1) throw Error('Ambiguous failure notifier name; refusing to modify');
  const current = matches[0];
  const target = { ...(current ? { id: current.id } : {}), name: desired.name, agent: 'telegram',
    enabled: true, types: desired.types, options, aboutScale: 1 };
  let changed = false;
  if (!current || !isDeepStrictEqual(Object.fromEntries(Object.keys(target).map(k => [k, current[k]])), target)) {
    await api('/notifications/configuration/add', target);
    changed = true;
  }
  const after = await api('/notifications/configurations');
  const saved = after.find(x => x.name === desired.name);
  if (!saved || saved.agent !== 'telegram' || !saved.enabled || !isDeepStrictEqual(saved.types, desired.types) ||
      !isDeepStrictEqual(saved.options, options)) throw Error('Failure notifier readback mismatch');
  const bound = db.prepare('SELECT rulegroupId FROM notification_rulegroup WHERE notificationId = ?').all(saved.id).map(x => x.rulegroupId);
  for (const rulegroupId of groupIds.filter(id => !bound.includes(id))) {
    await api('/notifications/configuration/connect', { rulegroupId, notificationId: saved.id });
    changed = true;
  }
  const verifiedBindings = db.prepare('SELECT rulegroupId FROM notification_rulegroup WHERE notificationId = ?').all(saved.id).map(x => x.rulegroupId);
  if (groupIds.some(id => !verifiedBindings.includes(id))) throw Error('Failure notifier rule-group binding readback mismatch');
  console.log('Maintainerr failure notifier verified: types32/64 -> existing status topic; ' +
    (changed ? 'updated' : 'already converged') + '. Ordinary notifications, rules and media untouched.');
  db.close();
}
main().catch(() => { console.error('Maintainerr notification reconciliation failed; inspect locally (credentials not logged).'); process.exitCode = 1; });
