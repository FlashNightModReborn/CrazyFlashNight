import { createContext, useContext } from "react";
import type { ReactNode } from "react";
import type { AnkitApi } from "../../shared/ipc-types.js";

const AnkitApiContext = createContext<AnkitApi | undefined>(undefined);

export function AnkitApiProvider({ children }: { children: ReactNode }) {
  return <AnkitApiContext.Provider value={window.ankit}>{children}</AnkitApiContext.Provider>;
}

/** The bridge, or undefined when not running under Electron (browser preview). */
export function useAnkitApi(): AnkitApi | undefined {
  return useContext(AnkitApiContext);
}
