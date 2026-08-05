import { PrimeMagicOrbitEngine } from "../src/engine.js";
import { mapSharedOrbitViews } from "../src/shared-buffer.js";
import type { PrimeMagicSeed } from "../src/types.js";

interface InitializeMessage {
  readonly kind: "initialize";
  readonly seed: PrimeMagicSeed;
  readonly randomSeed: string;
  readonly storage: SharedArrayBuffer;
  readonly boardsPerSecond: number;
}

interface StopMessage {
  readonly kind: "stop";
}

type WorkerMessage = InitializeMessage | StopMessage;

let timer: ReturnType<typeof setInterval> | undefined;

function stopTimer(): void {
  if (timer !== undefined) {
    clearInterval(timer);
    timer = undefined;
  }
}

function initialize(message: InitializeMessage): void {
  stopTimer();
  if (!(message.boardsPerSecond > 0) || message.boardsPerSecond > 1_000) {
    throw new RangeError("boardsPerSecond must be in (0, 1000]");
  }
  const engine = new PrimeMagicOrbitEngine(message.seed, BigInt(message.randomSeed));
  const shared = mapSharedOrbitViews(message.storage, message.seed.values.length);
  shared.boards[0].set(message.seed.values);
  shared.boards[1].set(message.seed.values);
  Atomics.store(shared.control, 0, 0);
  Atomics.store(shared.control, 1, 0);
  Atomics.store(shared.control, 2, 0);

  timer = setInterval(() => {
    const front = Atomics.load(shared.control, 0);
    const back = front ^ 1;
    if (Atomics.load(shared.control, 2) === back + 1) return;
    engine.nextInto(shared.boards[back]!);
    Atomics.store(shared.control, 0, back);
    Atomics.add(shared.control, 1, 1);
  }, 1_000 / message.boardsPerSecond);
}

globalThis.onmessage = (event: MessageEvent<WorkerMessage>): void => {
  if (event.data.kind === "stop") {
    stopTimer();
  } else {
    initialize(event.data);
  }
};
