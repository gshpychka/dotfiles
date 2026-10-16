// Narrow compatibility patch for the pinned Maintainerr 3.8.0 image.
// No media action, selection, schedule, or database code is changed.
const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const LOCAL = 'collection_media_entities_1.CollectionMediaManualMembershipSource.LOCAL';
// Rule-owned sync: the executor reports each step's verified database delta itself
// (rulegroup identifier) and tells the collection service not to emit the same
// change again (collection identifier). Both identifiers resolve to the same
// notifiers, so upstream otherwise sends every rule add/remove twice.
// Reporting right after each step keeps an add notice when a later removal fails
// or the run is aborted; an unreadable membership list reports nothing.
const executorBefore = [
  '                if (dataToAdd.length > 0) {',
  '                    collection =',
  '                        collMediaData.length > 0',
  '                            ? await this.collectionService.addToCollectionWithResolvedLink(collection, dataToAdd)',
  '                            : await this.collectionService.addToCollection(collection.id, dataToAdd);',
  '                }',
  '                abortSignal?.throwIfAborted();',
  '                if (collection && dataToRemove.length > 0) {',
  '                    collection =',
  '                        collMediaData.length > 0',
  "                            ? await this.collectionService.removeFromCollectionWithResolvedLink(collection, dataToRemove, 'rule')",
  "                            : await this.collectionService.removeFromCollection(collection.id, dataToRemove, 'rule');",
  '                }',
  '                if (!collection) {',
  '                    throw new Error(`Collection update failed for rule group ${rulegroup?.id} (collectionId: ${rulegroup?.collectionId})`);',
  '                }',
  '                const updatedMediaServerIds = new Set(((await this.collectionService.getCollectionMedia(collection?.id)) ??',
  '                    []).map((e) => e.mediaServerId));',
  '                const addedToCollection = dataToAdd.filter((m) => updatedMediaServerIds.has(m.mediaServerId) &&',
  '                    !currentMediaServerIds.has(m.mediaServerId));',
  '                const removedFromCollection = dataToRemove.filter((m) => !updatedMediaServerIds.has(m.mediaServerId) &&',
  '                    currentMediaServerIds.has(m.mediaServerId));',
  '                if (removedFromCollection.length > 0) {',
  '                    this.eventEmitter.emit(contracts_1.MaintainerrEvent.CollectionMedia_Removed, new events_dto_1.CollectionMediaRemovedDto(removedFromCollection, collection.title, {',
  "                        type: 'rulegroup',",
  '                        value: rulegroup.id,',
  '                    }, collection.id, collection.deleteAfterDays));',
  '                }',
  '                if (addedToCollection.length > 0) {',
  "                    this.eventEmitter.emit(contracts_1.MaintainerrEvent.CollectionMedia_Added, new events_dto_1.CollectionMediaAddedDto(addedToCollection, collection.title, { type: 'rulegroup', value: rulegroup.id }, collection.id, collection.deleteAfterDays));",
  '                }',
].join('\n');
const executorAfter = [
  '                const verifiedMembership = async (target) => {',
  '                    const media = await this.collectionService.getCollectionMedia(target.id);',
  '                    return media ? new Set(media.map((e) => e.mediaServerId)) : undefined;',
  '                };',
  '                let addedToCollection = [];',
  '                let removedFromCollection = [];',
  '                if (dataToAdd.length > 0) {',
  '                    const target = collection;',
  '                    collection =',
  '                        collMediaData.length > 0',
  `                            ? await this.collectionService.addToCollectionWithResolvedLink(collection, dataToAdd, false, ${LOCAL}, false)`,
  `                            : await this.collectionService.addToCollection(collection.id, dataToAdd, false, ${LOCAL}, false);`,
  '                    const updatedMediaServerIds = await verifiedMembership(target);',
  '                    addedToCollection = updatedMediaServerIds ? dataToAdd.filter((m) => updatedMediaServerIds.has(m.mediaServerId) &&',
  '                        !currentMediaServerIds.has(m.mediaServerId)) : [];',
  '                    if (addedToCollection.length > 0) {',
  "                        this.eventEmitter.emit(contracts_1.MaintainerrEvent.CollectionMedia_Added, new events_dto_1.CollectionMediaAddedDto(addedToCollection, target.title, { type: 'rulegroup', value: rulegroup.id }, target.id, target.deleteAfterDays));",
  '                    }',
  '                }',
  '                abortSignal?.throwIfAborted();',
  '                if (collection && dataToRemove.length > 0) {',
  '                    const target = collection;',
  '                    collection =',
  '                        collMediaData.length > 0',
  "                            ? await this.collectionService.removeFromCollectionWithResolvedLink(collection, dataToRemove, 'rule', false)",
  "                            : await this.collectionService.removeFromCollection(collection.id, dataToRemove, 'rule', false);",
  '                    const updatedMediaServerIds = await verifiedMembership(target);',
  '                    removedFromCollection = updatedMediaServerIds ? dataToRemove.filter((m) => !updatedMediaServerIds.has(m.mediaServerId) &&',
  '                        currentMediaServerIds.has(m.mediaServerId)) : [];',
  '                    if (removedFromCollection.length > 0) {',
  '                        this.eventEmitter.emit(contracts_1.MaintainerrEvent.CollectionMedia_Removed, new events_dto_1.CollectionMediaRemovedDto(removedFromCollection, target.title, {',
  "                            type: 'rulegroup',",
  '                            value: rulegroup.id,',
  '                        }, target.id, target.deleteAfterDays));',
  '                    }',
  '                }',
  '                if (!collection) {',
  '                    throw new Error(`Collection update failed for rule group ${rulegroup?.id} (collectionId: ${rulegroup?.collectionId})`);',
  '                }',
].join('\n');
const specs = [
  {
    file: 'collection-handler.js',
    sha256: '4e7d475bc260be0480ff1f397e8e5bc41f2e61f6d863106f6041b9e248f13c1e',
    replacements: [[
      'await this.collectionService.removeFromCollection(collection.id, [\n            {\n                mediaServerId: media.mediaServerId,\n            },\n        ]);',
      "await this.collectionService.removeFromCollection(collection.id, [\n            {\n                mediaServerId: media.mediaServerId,\n            },\n        ], 'all', false);",
    ]],
  },
  {
    file: 'collections.service.js',
    sha256: 'e49791c62751ff45175ede565a85e5bbb7877edc1885d3497cf5ddf16521b069',
    replacements: [
      // Default true keeps every non-rule caller (manual edits, media-server sync) notifying.
      [`async addToCollection(collectionDbId, media, manual = false, manualMembershipSource = ${LOCAL}) {\n        return this.addToCollectionInternal(collectionDbId, media, manual, false, false, manualMembershipSource);`,
        `async addToCollection(collectionDbId, media, manual = false, manualMembershipSource = ${LOCAL}, notifyAdded = true) {\n        return this.addToCollectionInternal(collectionDbId, media, manual, false, false, manualMembershipSource, notifyAdded);`],
      [`async addToCollectionWithResolvedLink(collection, media, manual = false, manualMembershipSource = ${LOCAL}) {`,
        `async addToCollectionWithResolvedLink(collection, media, manual = false, manualMembershipSource = ${LOCAL}, notifyAdded = true) {`],
      ['return this.addToCollectionInternal(collection.id, media, manual, true, false, manualMembershipSource);',
        'return this.addToCollectionInternal(collection.id, media, manual, true, false, manualMembershipSource, notifyAdded);'],
      [`async addToCollectionInternal(collectionDbId, media, manual = false, skipAutomaticLinkCheck = false, skipMediaServerAdd = false, manualMembershipSource = ${LOCAL}) {`,
        `async addToCollectionInternal(collectionDbId, media, manual = false, skipAutomaticLinkCheck = false, skipMediaServerAdd = false, manualMembershipSource = ${LOCAL}, notifyAdded = true) {`],
      ['this.eventEmitter.emit(contracts_1.MaintainerrEvent.CollectionMedia_Added,', 'if (notifyAdded) this.eventEmitter.emit(contracts_1.MaintainerrEvent.CollectionMedia_Added,'],
      ["async removeFromCollection(collectionDbId, media, removalScope = 'all') {", "async removeFromCollection(collectionDbId, media, removalScope = 'all', notifyRemoval = true) {"],
      ['return this.removeFromCollectionInternal(collectionDbId, media, false, removalScope);', 'return this.removeFromCollectionInternal(collectionDbId, media, false, removalScope, notifyRemoval);'],
      ["async removeFromCollectionWithResolvedLink(collection, media, removalScope = 'all') {", "async removeFromCollectionWithResolvedLink(collection, media, removalScope = 'all', notifyRemoval = true) {"],
      ['return this.removeFromCollectionInternal(collection.id, media, true, removalScope);', 'return this.removeFromCollectionInternal(collection.id, media, true, removalScope, notifyRemoval);'],
      ["async removeFromCollectionInternal(collectionDbId, media, skipAutomaticLinkCheck = false, removalScope = 'all') {", "async removeFromCollectionInternal(collectionDbId, media, skipAutomaticLinkCheck = false, removalScope = 'all', notifyRemoval = true) {"],
      ['if (removedItemIds.size > 0) {', 'if (removedItemIds.size > 0 && notifyRemoval) {'],
    ],
  },
  {
    file: 'rule-executor.service.js',
    sha256: '55f955bd8ced399a43b9f76044d3f7be6003c844bc587b9f59bc40f7f7b2fd0c',
    replacements: [[executorBefore, executorAfter]],
  },
  {
    file: 'telegram.js',
    sha256: 'b844987f9857fc9ca427e092f15ff8013d0ccd0896ff5b67b9912f0a7385e696',
    replacements: [[
      'chat_id: settings.options.chatId,',
      'chat_id: settings.options.chatId,\n                    ...(settings.options.messageThreadId ? { message_thread_id: settings.options.messageThreadId } : {}),',
    ]],
  },
];
function patch(file, source) {
  const spec = specs.find(s => s.file === file);
  if (!spec) throw Error('Unknown patch target: ' + file);
  if (createHash('sha256').update(source).digest('hex') !== spec.sha256) {
    throw Error('Upstream source changed; review notification patch before upgrading: ' + file);
  }
  for (const [before, after] of spec.replacements) {
    if (source.split(before).length !== 2) throw Error('Patch anchor not unique: ' + file);
    source = source.replace(before, () => after);
  }
  return source;
}
if (require.main === module) {
  const directory = process.argv[2];
  if (!directory) throw Error('Usage: node patch.cjs DIRECTORY');
  // Validate every input before writing any output.
  const outputs = specs.map(s => [s.file, patch(s.file, fs.readFileSync(path.join(directory, s.file), 'utf8'))]);
  for (const [file, source] of outputs) fs.writeFileSync(path.join(directory, file), source, { mode: 0o444 });
  console.log('Applied Maintainerr notification-only patch to ' + outputs.length + ' version-verified modules.');
}
module.exports = { patch, specs };
