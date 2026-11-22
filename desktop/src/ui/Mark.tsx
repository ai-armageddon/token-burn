// The four-ring mark from TokenBurnMark.swift.
const rings: [number, number, number][] = [
  [24, 24, 0.89],
  [76, 24, 0.65],
  [24, 76, 0.74],
  [76, 76, 0.48],
];
const C = 2 * Math.PI * 19;

export function TokenBurnMark({ size }: { size: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 100 100" aria-hidden="true" data-tauri-drag-region>
      {rings.map(([x, y, r]) => (
        <g key={`${x}-${y}`} fill="none" stroke="#22D86A" stroke-width={6.8} stroke-linecap="round">
          <circle cx={x} cy={y} r={19} opacity={0.25} />
          <circle cx={x} cy={y} r={19} stroke-dasharray={`${C * r} ${C}`} transform={`rotate(-90 ${x} ${y})`} />
        </g>
      ))}
    </svg>
  );
}
