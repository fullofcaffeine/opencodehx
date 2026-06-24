# Fixture Smoke Parity

The upstream `test/fixture/fixture.test.ts` oracle covers two behaviors for temporary fixtures:

- git-backed temp directories must persist `core.fsmonitor=false` in repo config, so later git commands do not use a developer's fsmonitor daemon by accident.
- disposing the fixture must remove its temporary directory.

OpenCodeHX covers this with `opencodehx.smoke.SmokeTmpDir` and `FixtureSmoke.tmpdir`. The smoke fixture creates a Node temp directory, initializes git through the normal `Git.run` seam, writes the local fsmonitor guard, then reads the stored config with plain `git config` to prove the value is actually in the fixture repo rather than only injected through `Git.baseArgs()`.

This remains a smoke-only helper. Product code should continue to use narrower runtime seams instead of depending on test fixture lifecycle utilities.
