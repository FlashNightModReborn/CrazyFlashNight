export {};

declare global {
  interface Window {
    cf7Balance?: {
      runtime: string;
      versions: Record<string, string>;
    };
  }
}