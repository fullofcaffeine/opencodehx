import { transformAsync } from "@babel/core";
import ts from "@babel/preset-typescript";
import solid from "babel-preset-solid";
import { plugin as registerBunPlugin } from "bun";

function sourcePath(input) {
  const searchIndex = input.indexOf("?");
  const hashIndex = input.indexOf("#");
  const end = [searchIndex, hashIndex].filter((index) => index >= 0).sort((a, b) => a - b)[0];
  return end === undefined ? input : input.slice(0, end);
}

registerBunPlugin({
  name: "opencodehx-opentui-solid",
  setup(build) {
    build.onLoad({ filter: /[/\\]node_modules[/\\]solid-js[/\\]dist[/\\]server\.js(?:[?#].*)?$/ }, async (args) => {
      const path = sourcePath(args.path).replace("server.js", "solid.js");
      return { contents: await Bun.file(path).text(), loader: "js" };
    });

    build.onLoad(
      { filter: /[/\\]node_modules[/\\]solid-js[/\\]store[/\\]dist[/\\]server\.js(?:[?#].*)?$/ },
      async (args) => {
        const path = sourcePath(args.path).replace("server.js", "store.js");
        return { contents: await Bun.file(path).text(), loader: "js" };
      }
    );

    build.onLoad({ filter: /\.(js|ts)x(?:[?#].*)?$/ }, async (args) => {
      const path = sourcePath(args.path);
      const code = await Bun.file(path).text();
      const transformed = await transformAsync(code, {
        filename: path,
        configFile: false,
        babelrc: false,
        presets: [
          [
            solid,
            {
              moduleName: "@opentui/solid",
              generate: "universal",
            },
          ],
          [ts, { allowDeclareFields: true }],
        ],
      });

      return {
        contents: transformed?.code ?? "",
        loader: "js",
      };
    });
  },
});
