const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const { createHash } = require('node:crypto');
const { patch, specs } = require('./patch.cjs');
const directory = process.argv[2];
// Read-only for the chain tests (real notifier routing and message building); never patched or mounted.
const dispatcher = { file: 'notifications.service.js', sha256: '36e9fd450483434ccb2286f8c9d10d486b9088ec77b6311e8e5e1806a8173ddb' };
const sources = Object.fromEntries([...specs, dispatcher].map(s => [s.file, fs.readFileSync(path.join(directory, s.file), 'utf8')]));
assert.equal(createHash('sha256').update(sources[dispatcher.file]).digest('hex'), dispatcher.sha256, 'Upstream source changed: ' + dispatcher.file);
const patched = Object.fromEntries(specs.map(s => [s.file, patch(s.file, sources[s.file])]));
let count = 0;
async function test(name, fn) { await fn(); console.log('ok ' + (++count) + ' - ' + name); }
function methods(source, start, end, globals = {}) {
  const from = source.indexOf(start);
  const to = source.indexOf(end, from);
  assert(from >= 0 && to > from, 'method extraction boundaries');
  // A class body accepts several consecutive methods exactly as compiled upstream.
  const { prototype } = vm.runInNewContext('(class {' + source.slice(from, to) + '})', globals);
  return Object.fromEntries(Object.getOwnPropertyNames(prototype).filter(k => k !== 'constructor').map(k => [k, prototype[k]]));
}
function method(source, start, end, globals = {}) { return Object.values(methods(source, start, end, globals))[0]; }
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
  function handlerContext(collectionService, handled = true) { return {
    getMediaServer: async () => ({ getLibraries: async () => [{ id: '1', type: 'movie' }] }),
    radarrActionHandler: { handleAction: async () => handled },
    settings: { seerrConfigured: () => false },
    collectionService,
  }; }
  await test('successful media handling passes suppression, records success; failed action never removes collection membership', async () => {
    const calls = [];
    const context = handlerContext({
      removeFromCollection: async (...a) => calls.push(a),
      CollectionLogRecordForChild: async () => {}, saveCollection: async () => {},
    });
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

  // End-to-end chain: real rule executor -> real collection service -> real notification
  // dispatcher -> real Telegram agent. Only the database, media server, rule group lookup
  // and HTTP transport are in-memory mocks; nothing leaves the process.
  const NotificationType = { MEDIA_ADDED_TO_COLLECTION: 2, MEDIA_REMOVED_FROM_COLLECTION: 4, MEDIA_ABOUT_TO_BE_HANDLED: 8,
    MEDIA_HANDLED: 16, RULE_HANDLING_FAILED: 32, COLLECTION_HANDLING_FAILED: 64 }; // notifications-interfaces.js
  const MaintainerrEvent = { CollectionMedia_Added: 'collection_media.added', CollectionMedia_Removed: 'collection_media.removed',
    RuleHandler_Failed: 'rule_handler.failed' };
  class Dto { constructor(mediaItems, collectionName, identifier, collectionId, dayAmount) {
    Object.assign(this, { mediaItems, collectionName, identifier, collectionId, dayAmount }); } }
  class RuleHandlerFailedDto { constructor(collectionName, identifier) { Object.assign(this, { collectionName, identifier }); } }
  const entities = {
    CollectionMedia: class {},
    CollectionMediaManualMembershipSource: { LOCAL: 'local' },
    hasCollectionMediaRuleMembership: m => m.includedByRule ?? !m.isManual,
    hasCollectionMediaManualMembership: m => m.manualMembershipSource != null || m.isManual,
  };
  const chainGlobals = {
    contracts_1: { MaintainerrEvent, MediaServerFeature: { COLLECTION_VISIBILITY: 'collection-visibility' } },
    events_dto_1: { CollectionMediaAddedDto: Dto, CollectionMediaRemovedDto: Dto, RuleHandlerFailedDto },
    collection_media_entities_1: entities,
    notifications_interfaces_1: { NotificationType },
    DOMException,
  };
  function loadTelegram(source, post) {
    const module = { exports: {} };
    const modules = {
      axios: { __esModule: true, default: { post } },
      '../notifications-interfaces': { NotificationType, NotificationAgentKey: { TELEGRAM: 'telegram' } },
      '../notifications.service': { hasNotificationType: (type, value) => value.includes(type) },
    };
    vm.runInNewContext('(function (exports, require, module) {' + source + '\n})')(module.exports, name => {
      assert(Object.hasOwn(modules, name), 'unexpected require ' + name); return modules[name];
    }, module);
    return module.exports.default;
  }
  function build(files) {
    const executorSource = files['rule-executor.service.js'];
    const failureFrom = executorSource.indexOf('class RuleExecutionFailure');
    const RuleExecutionFailure = vm.runInNewContext('(' + executorSource.slice(failureFrom, executorSource.indexOf('let RuleExecutorService', failureFrom)) + ')');
    const executorGlobals = { ...chainGlobals, RuleExecutionFailure };
    const executorMethods = {
      ...methods(executorSource, 'buildRuleHandlerFailedDto(', '    async executeForRuleGroups(', executorGlobals),
      ...methods(executorSource, 'async handleCollection(', '    async getAllActiveRuleGroups(', executorGlobals),
      ...methods(executorSource, '    prepareDataAmendment(arr) {', '    async getMediaData(', executorGlobals),
    };
    const service = files['collections.service.js'];
    const serviceMethods = {
      ...methods(service, 'async getCollectionMedia(', '    async getCollectionMediaRecord(', chainGlobals),
      ...methods(service, 'async addToCollection(', '    async removeFromAllCollections(', chainGlobals),
      ...methods(service, 'async addChildrenToCollection(', '    async addCollectionToDB(', chainGlobals),
    };
    const dispatch = sources[dispatcher.file];
    const notificationMethods = {
      ...methods(dispatch, 'async sendNotification(', '    async addNotificationConfiguration(', chainGlobals),
      ...methods(dispatch, 'async handleNotification(', '    async ruleHandlerFailed(', chainGlobals),
      ...methods(dispatch, 'async ruleHandlerFailed(', '    async collectionMediaHandled(', chainGlobals),
    };
    return { executorMethods, serviceMethods, notificationMethods, RuleExecutionFailure,
      TelegramAgent: post => loadTelegram(files['telegram.js'], post),
      handleMedia: method(files['collection-handler.js'], 'async handleMedia(', '\n};', { collection_interface_1: { ServarrAction: enumValues } }) };
  }
  const titles = { s07e08: ['Mad Men', 7, 8], s07e09: ['Mad Men', 7, 9], keep: ['Mad Men', 7, 10], ironlung: 'Iron Lung', other: 'Other Movie' };
  function world(files, { rows = [], failAdd = [], failRemove = [], throwOn = {}, abortOn } = {}) {
    const built = build(files);
    const collection = { id: 3, title: 'Cleanup', deleteAfterDays: 30, manualCollection: false, mediaServerId: 'plex-3', libraryId: 1 };
    const rulegroup = { id: 3, collectionId: 3, name: 'Cleanup', notifications: [{ id: 1 }, { id: 2 }] };
    let db = rows.map((row, i) => ({ id: i + 1, collectionId: 3, includedByRule: true, manualMembershipSource: null, ...row }));
    let nextId = db.length + 1;
    const requests = []; const pending = []; const events = []; const errors = []; const controller = new AbortController();
    const mediaServer = {
      supportsFeature: () => false,
      addBatchToCollection: async (_, ids) => { if (throwOn.add) throw Error('offline add failure'); if (abortOn === 'add') controller.abort(); return ids.filter(id => failAdd.includes(id)); },
      removeBatchFromCollection: async (_, ids) => { if (throwOn.remove) throw Error('offline remove failure'); return ids.filter(id => failRemove.includes(id)); },
      removeFromCollection: async () => {}, deleteCollection: async () => {},
      getMetadata: async id => typeof titles[id] === 'string' ? { title: titles[id] }
        : { grandparentId: 'show', grandparentTitle: titles[id][0], parentId: 'season', parentIndex: titles[id][1], index: titles[id][2] },
    };
    // Errors are recorded: the dispatcher's Promise.allSettled would otherwise hide a broken send path.
    const logger = { log: () => {}, warn: () => {}, debug: () => {}, error: e => errors.push(e), setContext: () => {} };
    const eventEmitter = { emit: (name, payload) => {
      const handler = { [MaintainerrEvent.CollectionMedia_Added]: 'collectionMediaAdded', [MaintainerrEvent.CollectionMedia_Removed]: 'collectionMediaRemoved',
        [MaintainerrEvent.RuleHandler_Failed]: 'ruleHandlerFailed' }[name];
      assert(handler, 'unexpected event ' + name);
      events.push(name);
      pending.push(notifications[handler](payload)); // Nest dispatches async listeners without awaiting
    } };
    const service = { ...built.serviceMethods, logger, eventEmitter,
      getMediaServer: async () => mediaServer,
      collectionRepo: { findOne: async () => ({ ...collection }), save: async x => x },
      CollectionMediaRepo: {
        find: async ({ where }) => db.filter(r => r.collectionId === where.collectionId).map(r => ({ ...r })),
        create: x => x,
        save: async x => { db = db.filter(r => r.id !== x.id); const row = { id: x.id ?? nextId++, ...x }; db.push(row); return row; },
        delete: async ({ id }) => { db = db.filter(r => r.id !== id); },
      },
      connection: { createQueryBuilder: () => { const where = []; const q = {
        delete: () => q, from: () => q, where: w => { where.push(...w); return q; },
        execute: async () => { db = db.filter(r => !where.some(w => w.collectionId === r.collectionId && w.mediaServerId === r.mediaServerId)); },
      }; return q; } },
      getCollection: async () => ({ ...collection }), saveCollection: async x => x,
      checkAutomaticMediaServerLink: async x => x, relinkManualCollection: async x => x,
      isMediaServerCollectionShared: async () => false, resolveCollectionMediaArtwork: async () => ({}),
      updateCollectionTotalSize: async () => {}, CollectionLogRecordForChild: async () => {},
    };
    const TelegramAgent = built.TelegramAgent(async (url, body) => { requests.push({ url, body }); });
    const agents = [
      new TelegramAgent({}, { enabled: true, types: [2, 4, 8, 16], options: { botAuthToken: 'offline', chatId: 'offline-chat' } }, logger, { id: 1 }),
      new TelegramAgent({}, { enabled: true, types: [32, 64], options: { botAuthToken: 'offline', chatId: 'offline-chat', messageThreadId: 22 } }, logger, { id: 2 }),
    ];
    const notifications = { ...built.notificationMethods, logger, activeAgents: agents,
      getMediaServer: async () => mediaServer,
      // 'rulegroup' (executor) and 'collection' (service) identifiers resolve to the same group.
      ruleGroupRepo: { findOne: async ({ where }) => (where.id === 3 || where.collectionId === 3 ? rulegroup : null) },
    };
    const executor = { ...built.executorMethods, logger, eventEmitter, collectionService: service,
      rulesService: { getExclusions: async () => [] }, statisticsData: [], startTime: new Date() };
    async function settle() { while (pending.length) await Promise.all(pending.splice(0)); assert.deepEqual(errors, []); }
    return { built, rulegroup, collection, executor, service, requests, events, controller, settle,
      members: () => db.map(r => r.mediaServerId).sort(),
      async run(desired) {
        executor.resultData = desired.map(id => ({ id }));
        try { return { result: await executor.handleCollection(rulegroup, controller.signal) }; }
        catch (error) { return { error }; } finally { await settle(); }
      } };
  }
  const text = request => request.body.text.replace(/\\(.)/g, '$1');
  function media(requests, type) {
    const subject = { [NotificationType.MEDIA_ADDED_TO_COLLECTION]: 'Media Added to Collection', [NotificationType.MEDIA_REMOVED_FROM_COLLECTION]: 'Media Removed from Collection' }[type];
    return requests.filter(r => text(r).startsWith('*' + subject + '*'));
  }
  function assertOne(requests, type, items) {
    const sent = media(requests, type);
    assert.equal(sent.length, 1, 'expected one grouped Telegram POST');
    for (const item of items) assert(text(sent[0]).includes(item), 'missing ' + item);
    assert.equal(Object.hasOwn(sent[0].body, 'message_thread_id'), false, 'media notice stays on the ordinary route');
    return sent[0];
  }
  const episodes = ['Mad Men - season 7 - episode 8', 'Mad Men - season 7 - episode 9'];
  await test('unpatched upstream reproduces the duplicate (two identical POSTs for one rule add and one rule removal)', async () => {
    const add = world(sources, { rows: [{ mediaServerId: 'keep' }] });
    await add.run(['keep', 'ironlung', 'other']);
    assert.equal(media(add.requests, 2).length, 2); assert.equal(text(add.requests[0]), text(add.requests[1]));
    const rescue = world(sources, { rows: [{ mediaServerId: 's07e08' }, { mediaServerId: 's07e09' }, { mediaServerId: 'keep' }] });
    await rescue.run(['keep']);
    assert.equal(media(rescue.requests, 4).length, 2); assert.equal(text(rescue.requests[0]), text(rescue.requests[1]));
  });
  await test('rule add, resolved-link path: one grouped POST with both items', async () => {
    const w = world(patched, { rows: [{ mediaServerId: 'keep' }] });
    const { result } = await w.run(['keep', 'ironlung', 'other']);
    assert.equal(w.requests.length, 1); assertOne(w.requests, 2, ['Iron Lung', 'Other Movie']);
    assert.deepEqual([...result.addedMediaServerIds].sort(), ['ironlung', 'other']); assert.deepEqual(w.members(), ['ironlung', 'keep', 'other']);
  });
  await test('rule add, ordinary path (empty collection): one grouped POST with both items', async () => {
    const w = world(patched);
    await w.run(['ironlung', 'other']);
    assert.equal(w.requests.length, 1); assertOne(w.requests, 2, ['Iron Lung', 'Other Movie']);
  });
  await test('rule removal / viewing rescue: one grouped POST with both episodes, membership removed', async () => {
    const w = world(patched, { rows: [{ mediaServerId: 's07e08' }, { mediaServerId: 's07e09' }, { mediaServerId: 'keep' }] });
    const { result } = await w.run(['keep']);
    assert.equal(w.requests.length, 1); assertOne(w.requests, 4, episodes);
    assert.deepEqual([...result.removedMediaServerIds].sort(), ['s07e08', 's07e09']); assert.deepEqual(w.members(), ['keep']);
  });
  await test('ordinary-path rule removal call also stays silent in the service (executor owns the notice)', async () => {
    const w = world(patched, { rows: [{ mediaServerId: 's07e08' }, { mediaServerId: 'keep' }] });
    await w.service.removeFromCollection(3, [{ mediaServerId: 's07e08' }], 'rule', false); await w.settle();
    assert.equal(w.requests.length, 0); assert.deepEqual(w.events, []); assert.deepEqual(w.members(), ['keep']);
  });
  await test('add and removal in one run: exactly one POST each', async () => {
    const w = world(patched, { rows: [{ mediaServerId: 's07e08' }, { mediaServerId: 's07e09' }, { mediaServerId: 'keep' }] });
    await w.run(['keep', 'ironlung', 'other']);
    assert.equal(w.requests.length, 2); assert.deepEqual(w.events, [MaintainerrEvent.CollectionMedia_Added, MaintainerrEvent.CollectionMedia_Removed]);
    assertOne(w.requests, 2, ['Iron Lung', 'Other Movie']); assertOne(w.requests, 4, episodes);
  });
  await test('partial add / partial removal: one POST listing only verified changes', async () => {
    const add = world(patched, { rows: [{ mediaServerId: 'keep' }], failAdd: ['other'] });
    await add.run(['keep', 'ironlung', 'other']);
    const sent = assertOne(add.requests, 2, ['Iron Lung']); assert(!text(sent).includes('Other Movie'));
    const rescue = world(patched, { rows: [{ mediaServerId: 's07e08' }, { mediaServerId: 's07e09' }, { mediaServerId: 'keep' }], failRemove: ['s07e08'] });
    await rescue.run(['keep']);
    const removed = assertOne(rescue.requests, 4, [episodes[1]]); assert(!text(removed).includes(episodes[0]));
  });
  await test('no-op run sends nothing; manual+rule member losing only its rule flag sends nothing', async () => {
    const noop = world(patched, { rows: [{ mediaServerId: 'keep' }] });
    await noop.run(['keep']); assert.equal(noop.requests.length, 0); assert.deepEqual(noop.events, []);
    const kept = world(patched, { rows: [{ mediaServerId: 's07e09', manualMembershipSource: 'local' }, { mediaServerId: 'keep' }] });
    await kept.run(['keep']); assert.equal(kept.requests.length, 0); assert.deepEqual(kept.events, []); assert.deepEqual(kept.members(), ['keep', 's07e09']);
  });
  await test('failed add: no media notice, rule failure alert goes once to the status topic', async () => {
    const w = world(patched, { rows: [{ mediaServerId: 'keep' }], throwOn: { add: true } });
    const { error } = await w.run(['keep', 'ironlung']);
    assert(error instanceof w.built.RuleExecutionFailure); assert.equal(w.requests.length, 0); assert.deepEqual(w.events, []);
    w.executor.eventEmitter.emit(MaintainerrEvent.RuleHandler_Failed, error.payload); await w.settle(); // as executeForRuleGroups does
    assert.equal(w.requests.length, 1); assert.equal(w.requests[0].body.message_thread_id, 22);
  });
  await test('failed removal after a successful add: the add is still reported once, no removal notice', async () => {
    const w = world(patched, { rows: [{ mediaServerId: 's07e09' }, { mediaServerId: 'keep' }], throwOn: { remove: true } });
    const { error } = await w.run(['keep', 'ironlung']);
    assert(error instanceof w.built.RuleExecutionFailure);
    assert.equal(w.requests.length, 1); assertOne(w.requests, 2, ['Iron Lung']); assert.deepEqual(w.members(), ['ironlung', 'keep', 's07e09']);
  });
  await test('abort right after an add still reports that add once', async () => {
    const w = world(patched, { rows: [{ mediaServerId: 's07e09' }, { mediaServerId: 'keep' }], abortOn: 'add' });
    const { error } = await w.run(['keep', 'ironlung']);
    assert.equal(error.name, 'AbortError'); assert.equal(w.requests.length, 1); assertOne(w.requests, 2, ['Iron Lung']);
  });
  await test('successful cleanup through the real service: membership removed, no removal notice', async () => {
    const w = world(patched, { rows: [{ mediaServerId: 'ironlung' }, { mediaServerId: 'keep' }] });
    const collection = { id: 3, libraryId: 1, radarrSettingsId: 1, arrAction: 1, handledMediaAmount: 0 };
    const handled = await w.built.handleMedia.call(handlerContext(w.service), collection, { mediaServerId: 'ironlung' }); await w.settle();
    assert.equal(handled, true); assert.equal(w.requests.length, 0); assert.deepEqual(w.events, []); assert.deepEqual(w.members(), ['keep']);
  });
  await test('manual / media-server-sync removals keep exactly one removal notice', async () => {
    const w = world(patched, { rows: [{ mediaServerId: 'ironlung' }, { mediaServerId: 's07e09', includedByRule: false, manualMembershipSource: 'local' }, { mediaServerId: 'keep' }] });
    await w.service.removeFromCollection(3, [{ mediaServerId: 'ironlung' }]); await w.settle(); // collections controller
    assertOne(w.requests, 4, ['Iron Lung']);
    await w.service.removeFromCollection(3, [{ mediaServerId: 's07e09', reason: { type: 'media_removed_manually' } }], 'manual'); await w.settle(); // executor media-server sync
    assert.equal(w.requests.length, 2); assert(text(w.requests[1]).includes(episodes[1])); assert.deepEqual(w.members(), ['keep']);
  });
  await test('manual add keeps exactly one added notice', async () => {
    const w = world(patched, { rows: [{ mediaServerId: 'keep' }] });
    await w.service.addToCollection(3, [{ mediaServerId: 'ironlung' }], true); await w.settle();
    assert.equal(w.requests.length, 1); assertOne(w.requests, 2, ['Iron Lung']);
  });
  console.log(count + ' offline tests passed; no network or media operations performed.');
})().catch(error => { console.error(error); process.exitCode = 1; });
