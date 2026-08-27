# Global context

## Investigation before action
- Verify a hypothesis against code, logs, or metrics before claiming a fix works.
- Find the root cause of a failure. A workaround ships only when framed explicitly as one.
- Match claim strength to evidence, and say which claims are guesses.

## Writing
Applies to comments, docstrings, commit messages, PR bodies, and docs.
- A comment states a constraint or root cause the code cannot express: a property that stays true as the code evolves. Runtime narration, change history, and defaults get no words.
- State each fact at the site that enforces it, on the narrowest construct it is about.
- A docstring states the caller-facing contract in domain terms; the mechanism behind it stays inline beside the code.
- Describe current state in positive present tense. Skip "rather than X", "instead of Y", "previously", and ALL CAPS.
- One line by default; a second line earns its place with a second load-bearing fact. Link the canonical source rather than summarizing it.

## Structure
- Each component owns one concern, and the boundary is obvious from the structure.
- Consumers depend on a contract; implementation details stay behind it in code, types, naming, and prose.
- A comment speaks about its own component at its own abstraction level, and never describes a sibling's internals.
