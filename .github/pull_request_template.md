<!--
Optional linked context: add a visible `Closes #<issue-number>` or
`Related: #<issue-number>` line below this comment.

Write for someone who uses goplaces but has not read the code. The title and
opening problem statement should make sense without the diff or linked issue.

Name the affected task and the outcome, not just the implementation.
Illustrative title wording, not reports of current bugs:
Good: docs: explain how scripts can use place-search results
Bad: docs: document JSON response mappings
Good: docs: explain which APIs route searches need enabled
Bad: docs(routes): expand endpoint prerequisites

For internal-only work, name the actual developer or operator workflow affected.
-->

## What Problem This Solves

<!--
Describe the concrete user, product, or operational problem.
In 1–3 short, plain-language sentences, explain what someone is trying to do,
what goes wrong or is missing, and why it matters. For a fix, include the trigger
when known. For other changes, describe the need without inventing a bug.

Use the actual affected workflow: searching for places from the terminal,
consuming JSON in a script, calling the Go client, or developing goplaces.
Describe the experienced problem, not just the code change. Save function names,
missing checks, and the root-cause walkthrough for the explanation below.
-->

## User Impact

<!--
Lead with what users, operators, or developers can now do or expect, usually
in one plain-language sentence. For internal-only changes, say there is no
user-visible change; do not invent a benefit. Keep important risks, breaking
changes, migrations, and required user actions visible here.
-->

## Why This Change Was Made

<!--
Briefly explain how the change addresses the problem without repeating the impact.
Keep the body short. Leave file lists, internal acronyms, and root-cause walkthroughs
in the diff or optional <details>; include technical detail only when it explains
behavior or a material tradeoff. Do not hide risks or required actions in <details>.
-->

## Evidence

<!--
Start with the behavior checked and the result in plain language. Focused tests,
CI results, terminal output, redacted logs, screenshots, and artifact links can
help. Do not make readers decode command lists to learn what was verified.

Put exact commands, commit hashes, and long output in links or optional <details>.
Keep the useful evidence summary and meaningful gaps visible. Distinguish mocked
API checks from live Google API checks; do not include API keys in evidence.
Existing development guidance is in docs/development.md; authenticated end-to-end
tests remain optional.
-->
