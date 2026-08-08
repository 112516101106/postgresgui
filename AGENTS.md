<!-- CODEGRAPH_START -->
## CodeGraph

In repositories indexed by CodeGraph (a `.codegraph/` directory exists at the repo root), reach for it BEFORE grep/find or reading files when you need to understand or locate code:

- **MCP tools** (when available): `codegraph_explore` answers most code questions in one call — the relevant symbols' verbatim source plus the call paths between them. `codegraph_node` returns one symbol's source + callers, or reads a whole file with line numbers. If the tools are listed but deferred, load them by name via tool search.
- **Shell** (always works): `codegraph explore "<symbol names or question>"` and `codegraph node <symbol-or-file>` print the same output.

If there is no `.codegraph/` directory, skip CodeGraph entirely — indexing is the user's decision.
<!-- CODEGRAPH_END -->

<!-- CONTEXT7_START -->
## Context7 Documentation Fetching

Use Context7 MCP to fetch current documentation whenever the user asks about a library, framework, SDK, API, CLI tool, or cloud service -- even well-known ones like React, Next.js, Prisma, Express, Tailwind, Django, or Spring Boot. This includes API syntax, configuration, version migration, library-specific debugging, setup instructions, and CLI tool usage. Use even when you think you know the answer -- your training data may not reflect recent changes. Prefer this over web search for library docs.

Do not use for: refactoring, writing scripts from scratch, debugging business logic, code review, or general programming concepts.

### Steps
1. Always start with `resolve-library-id` using the library name and the user's question, unless the user provides an exact library ID in `/org/project` format
2. Pick the best match (ID format: `/org/project`) by: exact name match, description relevance, code snippet count, source reputation (High/Medium preferred), and benchmark score (higher is better). If results don't look right, try alternate names or queries (e.g., "next.js" not "nextjs", or rephrase the question). Use version-specific IDs when the user mentions a version
3. `query-docs` with the selected library ID and the user's full question (not single words)
4. Answer using the fetched docs
<!-- CONTEXT7_END -->

<!-- PONYTAIL_START -->
## Ponytail Code Optimization (The Efficiency Ladder)

Before writing or modifying any code, you must pass your solution through the Ponytail efficiency ladder. Be lazy about writing new code, but relentless about reading existing context. Stop at the first rung that satisfies the task:

1. **YAGNI:** Does this feature absolutely need to exist? If no, skip it entirely.
2. **Reuse:** Is this logic already in the codebase? (Check via CodeGraph). Reuse it, do not rewrite.
3. **Stdlib:** Can the language's standard library handle this? Use it.
4. **Native Platform:** Can native platform features (e.g., native HTML `<input type="date">` instead of a heavy third-party date-picker component) do the job? Use it.
5. **Dependency:** Is there an already installed dependency that achieves this? Use it.
6. **One-liner:** Can this be written cleanly in a single line? Make it one line.
7. **Minimum Viable Code:** Only write new code if rungs 1-6 fail. Write the absolute minimum that works perfectly.

*Note: Never compromise on security, trust-boundary validation, error handling, or accessibility.*
<!-- PONYTAIL_END -->

<!-- CAVEMAN_START -->
## Caveman Conversational Style

To minimize output latency and save tokens, you must drop all conversational filler, fluff, and polite prose. Talk like a caveman (fragments, tight phrases) while keeping technical content, code snippets, filenames, errors, and terminal commands 100% exact.

- **Bad (Verbose):** "Sure, I can help with that. The reason your React component is re-rendering is because you're passing an inline object..."
- **Good (Caveman):** "Inline object prop = new ref = re-render. Wrap in `useMemo`. Code:"
<!-- CAVEMAN_END -->