const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { patch, specs } = require('./patch.cjs');
const directory = process.argv[2];
const sources = Object.fromEntries(specs.map(s => [s.file, fs.readFileSync(path.join(directory, s.file), 'utf8')]));
const patched = Object.fromEntries(Object.entries(sources).map(([file, source]) => [file, patch(file, source)]));
let count = 0;
async function test(name, fn) { await fn(); console.log('ok ' + (++count) + ' - ' + name); }
function method(source, start, end, globals = {}) {
  const from = source.indexOf(start);
  const to = source.indexOf(end, from);
  assert(from >= 0 && to > from, 'method extraction boundaries');
  const object = vm.runInNewContext('({' + source.slice(from, to) + '})', globals);
  return Object.values(object)[0];
}
(async () => {
  await test('changed upstream fails closed before patching', () => {
    for (const s of specs) assert.throws(() => patch(s.file, sources[s.file] + ' '), /Upstream source changed/);
  });
  const serviceSource = patched['collections.service.js'];
  const wrapper = method(serviceSource, 'async removeFromCollection(', '    async removeFromCollectionWithResolvedLink(');
  await test('normal cancellation preserves removal notification by default', async () => {
    let args; await wrapper.call({ removeFromCollectionInternal: async (...a) => { args = a; } }, 1, [{ mediaServerId: 'x' }]);
    assert.deepEqual(args.slice(2), [false, 'all', true]);
  });
  await test('cleanup explicitly suppresses only removal notification', async () => {
    let args; await wrapper.call({ removeFromCollectionInternal: async (...a) => { args = a; } }, 1, [], 'all', false);
    assert.deepEqual(args.slice(2), [false, 'all', false]);
  });
  const globals = {
    contracts_1: { MaintainerrEvent: { CollectionMedia_Removed: 'removed' } },
    events_dto_1: { CollectionMediaRemovedDto: class { constructor(...args) { this.args = args; } } },
  };
  const remove = method(serviceSource, 'async removeFromCollectionInternal(', '    async updateExistingCollectionMediaForAdd(', globals);
  async function removal(notify, removed = true) {
    let state = [{ mediaServerId: 'x' }]; const events = []; const actions = [];
    const collection = { id: 1, title: 'test', deleteAfterDays: 30, manualCollection: false, mediaServerId: 'collection' };
    const context = {
      getMediaServer: async () => ({ deleteCollection: async () => actions.push('delete-empty-collection') }),
      collectionRepo: { findOne: async () => collection, save: async x => { actions.push('save-collection'); return x; } },
      CollectionMediaRepo: { find: async () => state },
      checkAutomaticMediaServerLink: async x => x,
      updateExistingCollectionMediaForRemoval: async () => [],
      removeChildrenFromCollection: async () => { actions.push('remove-member'); if (removed) state = []; return removed ? ['x'] : []; },
      eventEmitter: { emit: (...a) => events.push(a) },
      updateCollectionTotalSize: async () => actions.push('update-size'),
      logger: { warn: x => { throw Error(x); }, debug: () => {} },
    };
    const result = await remove.call(context, 1, [{ mediaServerId: 'x' }], false, 'all', notify);
    return { events, actions, result };
  }
  await test('real cancellation emits one event; cleanup emits zero removal events with identical state operations', async () => {
    const normal = await removal(true); const cleanup = await removal(false);
    assert.equal(normal.events.length, 1); assert.equal(cleanup.events.length, 0);
    assert.deepEqual(normal.actions, cleanup.actions); assert.deepEqual(normal.result, cleanup.result);
  });
  await test('failed/no-op member removal emits no cancellation event', async () => {
    assert.equal((await removal(true, false)).events.length, 0);
  });
  const enumValues = { DO_NOTHING: 99, UNMONITOR: 2, UNMONITOR_SHOW_IF_EMPTY: 3, DELETE_SHOW_IF_EMPTY: 4, CHANGE_QUALITY_PROFILE: 5 };
  const handle = method(patched['collection-handler.js'], 'async handleMedia(', '\n};', { collection_interface_1: { ServarrAction: enumValues } });
  await test('successful media handling passes suppression, records success; failed action never removes collection membership', async () => {
    const calls = [];
    const context = {
      getMediaServer: async () => ({ getLibraries: async () => [{ id: '1', type: 'movie' }] }),
      radarrActionHandler: { handleAction: async () => true },
      settings: { seerrConfigured: () => false },
      collectionService: {
        removeFromCollection: async (...a) => calls.push(a),
        CollectionLogRecordForChild: async () => {}, saveCollection: async () => {},
      },
    };
    const collection = { id: 1, libraryId: 1, radarrSettingsId: 1, arrAction: 1, handledMediaAmount: 0 };
    assert.equal(await handle.call(context, collection, { mediaServerId: 'x' }), true);
    assert.equal(calls.length, 1); assert.equal(calls[0][3], false); assert.equal(collection.handledMediaAmount, 1);
    context.radarrActionHandler.handleAction = async () => false;
    assert.equal(await handle.call(context, collection, { mediaServerId: 'x' }), false); assert.equal(calls.length, 1);
  });
  let posts = [];
  const send = method(patched['telegram.js'], 'async send(', '\n}\nexports.default', {
    axios_1: { default: { post: async (url, body) => posts.push({ url, body }) } },
    notifications_service_1: { hasNotificationType: (type, types) => types.includes(type) },
    notifications_interfaces_1: { NotificationType: {} },
  });
  function agent(options, types = [32, 64]) { return {
    baseUrl: 'https://invalid.example/',
    getSettings: () => ({ types, options: { botAuthToken: 'offline-test', chatId: 'offline-chat', ...options } }),
    getNotificationPayload: () => ({ text: 'offline test' }),
    logger: { log: () => {}, error: e => { throw Error(e); } },
  }; }
  await test('failure alerts target existing status topic, ordinary route remains unchanged', async () => {
    posts = []; await send.call(agent({ messageThreadId: 22 }), 32, {});
    assert.equal(posts[0].body.message_thread_id, 22);
    await send.call(agent({}), 64, {}); assert.equal(Object.hasOwn(posts[1].body, 'message_thread_id'), false);
  });
  await test('status notifier does not receive ordinary media notifications', async () => {
    posts = []; await send.call(agent({ messageThreadId: 22 }), 16, {}); assert.equal(posts.length, 0);
  });
  console.log(count + ' offline tests passed; no network or media operations performed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
