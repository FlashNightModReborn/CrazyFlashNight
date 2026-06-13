/**
 * Renderer entry. Mounts <App/> into #root.
 *
 * NOTE: this file (and everything under src/) runs in the CEP *renderer* (CEF).
 * Per the SHARED CONTEXT, never import @cf7-animate-kit/an-host here — it is
 * Node-only and belongs to an Electron MAIN process, which a CEP panel does
 * not have. The panel reaches the host exclusively through src/bridge.ts.
 */
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './App.js';
import './styles.css';

const el = document.getElementById('root');
if (!el) throw new Error('#root not found');
createRoot(el).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
