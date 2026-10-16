// Narrow compatibility patch for the pinned Maintainerr 3.8.0 image.
// No media action, selection, schedule, or database code is changed.
const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
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
      ["async removeFromCollection(collectionDbId, media, removalScope = 'all') {", "async removeFromCollection(collectionDbId, media, removalScope = 'all', notifyRemoval = true) {"],
      ['return this.removeFromCollectionInternal(collectionDbId, media, false, removalScope);', 'return this.removeFromCollectionInternal(collectionDbId, media, false, removalScope, notifyRemoval);'],
      ["async removeFromCollectionInternal(collectionDbId, media, skipAutomaticLinkCheck = false, removalScope = 'all') {", "async removeFromCollectionInternal(collectionDbId, media, skipAutomaticLinkCheck = false, removalScope = 'all', notifyRemoval = true) {"],
      ['if (removedItemIds.size > 0) {', 'if (removedItemIds.size > 0 && notifyRemoval) {'],
    ],
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
    source = source.replace(before, after);
  }
  return source;
}
if (require.main === module) {
  const directory = process.argv[2];
  if (!directory) throw Error('Usage: node patch.cjs DIRECTORY');
  // Validate every input before writing any output.
  const outputs = specs.map(s => [s.file, patch(s.file, fs.readFileSync(path.join(directory, s.file), 'utf8'))]);
  for (const [file, source] of outputs) fs.writeFileSync(path.join(directory, file), source, { mode: 0o444 });
  console.log('Applied Maintainerr notification-only patch to three version-verified modules.');
}
module.exports = { patch, specs };
