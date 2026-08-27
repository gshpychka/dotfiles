---
description: Review uncommitted changes
argument-hint: "[focus]"
---
Review the uncommitted changes: `git diff HEAD` plus anything untracked.

${@:-Look for correctness first, then for comments that narrate runtime events instead of stating stable properties.}

Report each finding as `file:line` with a one-sentence claim. Say which claims you verified by running something and which are unverified.
