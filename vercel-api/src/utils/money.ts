export function majorToMinor(major: number): number {
  return Math.round(major * 100);
}

export function minorToMajor(minor: number): number {
  return minor / 100;
}

export function formatLeones(minor: number, symbol = "Le"): string {
  return `${symbol} ${(minor / 100).toFixed(2)}`;
}
