import { loadPrimeMagicSeed, loadPrimeMagicSeedBank } from "../src/binary-seed.js";
import { PrimeMagicOrbitEngine } from "../src/engine.js";
import { PrimeMagicSeedBankOrbitEngine } from "../src/seed-bank-engine.js";
import { PrimeMagicGridRenderer } from "./renderer.js";

const canvas = document.querySelector<HTMLCanvasElement>("#matrix");
const rateInput = document.querySelector<HTMLInputElement>("#board-rate");
const rateLabel = document.querySelector<HTMLElement>("#board-rate-value");
const seedSelect = document.querySelector<HTMLSelectElement>("#seed-select");
const seedStatus = document.querySelector<HTMLElement>("#seed-status");
if (canvas === null || rateInput === null || rateLabel === null || seedSelect === null || seedStatus === null) {
  throw new Error("demo DOM is incomplete");
}
const rateSlider = rateInput;
const rateOutput = rateLabel;
const seedChooser = seedSelect;
const statusOutput = seedStatus;

const bank = await loadPrimeMagicSeedBank("/web/assets/seed-bank.json");
const autoOption = document.createElement("option");
autoOption.value = "auto";
autoOption.textContent = `AUTO · ${bank.seeds.length} DISJOINT ORBITS`;
seedChooser.append(autoOption);
for (const entry of bank.seeds) {
  const option = document.createElement("option");
  option.value = String(entry.index);
  option.textContent = `SEED ${String(entry.index).padStart(2, "0")} · CENTER ${entry.centerValue}`;
  seedChooser.append(option);
}
const seeds = await Promise.all(bank.seeds.map((entry) => loadPrimeMagicSeed(entry)));
let seed = seeds[0]!;
let engine: PrimeMagicOrbitEngine | PrimeMagicSeedBankOrbitEngine =
  new PrimeMagicSeedBankOrbitEngine(seeds, 0x19_361_190000361n);
const renderer = new PrimeMagicGridRenderer(canvas, seed.size, 8);
renderer.updateValues(engine.currentView());

function updateStatus(index: number | "auto"): void {
  statusOutput.textContent = index === "auto"
    ? `VERIFIED PRIME MAGIC · 8 ORBITS · 5,945,425,920 STATES · Σ ${seed.magicSum}`
    : `VERIFIED PRIME MAGIC · SEED ${String(index).padStart(2, "0")} · Σ ${seed.magicSum}`;
}
updateStatus("auto");

seedChooser.addEventListener("change", () => {
  if (seedChooser.value === "auto") {
    seed = seeds[0]!;
    engine = new PrimeMagicSeedBankOrbitEngine(seeds, 0x19_361_190000361n);
    renderer.updateValues(engine.currentView());
    updateStatus("auto");
    return;
  }
  const index = Number(seedChooser.value);
  const selectedSeed = seeds[index];
  if (selectedSeed === undefined) return;
  seedChooser.disabled = true;
  try {
    seed = selectedSeed;
    engine = new PrimeMagicOrbitEngine(seed, 0x19_361_190000361n ^ BigInt(index));
    renderer.updateValues(engine.currentView());
    updateStatus(index);
  } catch (error) {
    statusOutput.textContent = `SEED LOAD FAULT · ${String(error)}`;
  } finally {
    seedChooser.disabled = false;
  }
});

let previousBoardTime = performance.now();
function frame(now: number): void {
  const boardRate = Number(rateSlider.value);
  const interval = 1_000 / boardRate;
  if (now - previousBoardTime >= interval) {
    // Skip accumulated stale ticks after a background-tab pause.
    previousBoardTime = now;
    renderer.updateValues(engine.nextView());
  }
  renderer.render(now / 1_000);
  requestAnimationFrame(frame);
}

rateSlider.addEventListener("input", () => {
  rateOutput.textContent = rateSlider.value;
});
rateOutput.textContent = rateSlider.value;
requestAnimationFrame(frame);
