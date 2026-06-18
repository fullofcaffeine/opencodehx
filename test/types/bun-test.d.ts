declare module "bun:test" {
  export type UnitBody = () => void | Promise<void>;

  export interface UnitExpectation {
    toBe(expected: unknown): void;
    toEqual(expected: unknown): void;
    toContain(expected: unknown): void;
    toMatch(expected: string | RegExp): void;
  }

  export function describe(name: string, body: UnitBody): void;
  export function test(name: string, body: UnitBody): void;
  export function expect(actual: unknown): UnitExpectation;
}
