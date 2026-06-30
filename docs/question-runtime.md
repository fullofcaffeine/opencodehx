# Question Runtime

**Beads:** `opencodehx-e9p`, `opencodehx-do7x`

## Upstream Oracle

- `../opencode/packages/opencode/src/question/index.ts`
- `../opencode/packages/opencode/src/question/schema.ts`
- `../opencode/packages/opencode/test/question/question.test.ts`

## Current Surface

OpenCodeHX now has a typed Haxe-owned question service seam:

- `QuestionID`
- `QuestionOption`
- `QuestionInfo`
- `QuestionTool`
- `QuestionAnswer`
- `QuestionRequest`
- `QuestionService.ask`
- `QuestionService.list`
- `QuestionService.reply`
- `QuestionService.reject`

`QuestionRuntime.forContext(context)` scopes a `QuestionService` to an `InstanceRuntime` directory. Pending requests are isolated per context and are rejected when the owning instance is disposed or reloaded.

`OpenCodeServer` exposes the first upstream-shaped question route surface for the routed instance directory:

- `GET /question`
- `POST /question/:requestID/reply`
- `POST /question/:requestID/reject`

`QuestionSmoke` covers the core upstream behavior:

- `ask` returns a pending Promise and adds a request to `list`
- `reply` resolves the pending Promise and removes the request
- `reject` rejects the pending Promise with `QuestionRejectedError` and removes the request
- unknown `reply` and `reject` calls no-op
- multiple questions and multiple pending requests preserve order
- optional tool metadata is preserved on pending requests
- question state is isolated across directories
- pending questions reject on instance dispose and reload

`ServerSmoke` covers question route list/reply/reject behavior, invalid reply body rejection, unknown reply/reject no-op behavior, optional tool metadata preservation through the list response, and `x-opencode-directory` isolation.

## Boundaries

This is not the full upstream Effect service yet. The current runtime does not claim:

- `Question.defaultLayer` / Effect `Deferred` wiring
- the `question` tool wrapper and formatted tool output
- UI/TUI question prompts
- OpenAPI/HTTP schema generation

The only loose boundary in the smoke is Promise rejection inspection: JavaScript rejection reasons can be arbitrary host values, so `QuestionSmoke.rejectionKind` narrows the caught value with `Std.isOfType` before asserting `QuestionRejectedError`.
