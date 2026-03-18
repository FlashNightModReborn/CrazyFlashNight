import { createContext, useContext } from "react";
import type { PackerIpcApi } from "../../shared/ipc-types.js";

const PackerApiContext = createContext<PackerIpcApi | undefined>(undefined);

export function PackerApiProvider({ children }: { children: React.ReactNode }) {
  const api = window.cf7Packer;
  return (
    <PackerApiContext.Provider value={api}>
      {children}
    </PackerApiContext.Provider>
  );
}

export function usePackerApi(): PackerIpcApi | undefined {
  return useContext(PackerApiContext);
}
