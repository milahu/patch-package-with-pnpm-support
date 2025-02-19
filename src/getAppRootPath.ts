import { join, resolve } from "./path"
import { existsSync } from "fs-extra"
import { realpathCwd } from "./realpathCwd"

export const getAppRootPath = (): string => {
  let cwd = realpathCwd().replace(/\\/g, "/")
  while (!existsSync(join(cwd, "package.json"))) {
    const up = resolve(cwd, "../").replace(/\\/g, "/")
    if (up === cwd) {
      throw new Error("no package.json found for this project")
    }
    cwd = up
  }
  return cwd
}
