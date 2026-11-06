# How Room decides

Three layers, from strictest to most flexible. Only the first two ever decide anything.

## 1. Rules (deterministic)

A catalog of known locations (caches, build output, simulators, and so on) plus detectors for things like stale `node_modules`, installers and zip files next to an extracted copy. Each candidate gets a **tier** (safe, rebuildable, yours), a rebuild cost, and a reason. Path safety, the git guard and the confirmation rules are fixed code. Nothing below can change them.

## 2. The regret model (small, local, learns)

A logistic regression, `RegretModel` in `Sources/RoomCore/Scorer.swift`, estimating the chance you would regret deleting an item. Eleven inputs: tier, rebuild cost, size, age, git status, and how often you restored this kind of item before.

- Starts from hand-set weights. It does not ship a trained network or download a model.
- Learns only from your own choices on this Mac (deleted, declined, restored), by a few passes of gradient descent that are pulled back toward the starting weights, so a handful of examples can't make it reckless.
- **One-way safety:** learning can make Room more cautious about your own files, never less.
- Used by the planner: for a goal like "free 20 GB" it picks the set with the most guaranteed space per unit of regret, trying safe items first and widening to the next tier only if it must.
- Stored in `scorer-weights.json`. The optional decision log is anonymized (no paths or names), stays on your Mac and is off until you opt in.

## 3. The assistant (optional, explains only)

Powers the Ask screen and the "why" text. Setting: **Off** (built-in rule answers), **On-device** (Apple's built-in model, private and offline, used when available), or **Claude** (your own Anthropic API key from your Keychain).

- It sees only ids, categories, sizes and ages. Claude mode also replaces names with generic titles. Never paths or file contents.
- Anything it proposes is checked: it may only name items Room already found, and it can't include your own files unless you allowed that. It cannot run anything.
- If it is unavailable or fails, Room falls back to the rule-based answer.
