# Raw TypeScript Type Override Audit

Raw `@:ts.type("...")` is a last-resort interop escape hatch. Prefer ordinary
Haxe types, `DynamicAccess<T>`, narrow externs, typed decoders, or reusable
`genes.ts` helpers such as `Unknown` and `Undefinable<T>`.

Current approved overrides:

| File | Declaration | Raw type | Why it remains | Replacement direction |
| --- | --- | --- | --- | --- |
| `src/opencodehx/config/ConfigLoader.hx` | `ConfigEnv` | `{[key: string]: string \| null \| undefined}` | Process/config substitution must currently preserve three distinct host states: present string, explicit null overlay, and JavaScript undefined. | Split into a process-env facade using `genes.ts.Undefinable<String>` and a separate null-capable overlay type. |
| `src/opencodehx/resource/Resources.hx` | `ResourceUrl` | `URL` | Resource helpers pass Node URL instances, but the port does not yet have a stable cross-runtime resource/import abstraction for text/file/WASM assets. | Replace with a real URL extern or host resource facade once resource imports are generalized in `genes-ts`. |
| `src/opencodehx/externs/node/Fs.hx` | `NodeBufferData` | `import('node:buffer').Buffer` | `fs.readFileSync` returns Node Buffer instances. The current inline import type avoids pretending this is a Haxe-owned value. | Use the existing Node Buffer extern as the instance type and rely on `genes-ts` type-only/value import planning. |
| `src/opencodehx/externs/hono/NodeServer.hx` | `NodeServerType` | `import('@hono/node-server').ServerType` | The Node/Hono adapter uses a package-owned server return type with overload-heavy methods. | Replace with a narrow structural extern covering `listen`, `once`, `off`, `close`, `address`, and optional close helpers. |
| `src/opencodehx/externs/hono/Hono.hx` | `HonoHandler` | `import('hono').Handler<any, string, any, any> \| import('hono').MiddlewareHandler<any, string, any, any>` | Hono's handler/middleware overload surface is library-specific and currently needed for route and websocket adapter assignment. | Hide behind a route adapter and narrow `HonoContext`/handler facades; keep `genes-ts` free of Hono-specific knowledge. |
