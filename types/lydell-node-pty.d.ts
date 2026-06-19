declare module "@lydell/node-pty" {
  export type IDisposable = {
    dispose(): void;
  };

  export type IPtyForkOptions = {
    name?: string;
    cols?: number;
    rows?: number;
    cwd?: string;
    env?: { [key: string]: string | undefined };
  };

  export type IPty = {
    readonly pid: number;
    onData(listener: (data: string) => void): IDisposable;
    onExit(listener: (event: { exitCode: number; signal?: number }) => void): IDisposable;
    write(data: string): void;
    resize(cols: number, rows: number): void;
    kill(signal?: string): void;
  };

  export function spawn(file: string, args: string[] | string, options: IPtyForkOptions): IPty;
}
