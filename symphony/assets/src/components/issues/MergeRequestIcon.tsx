export function MergeRequestIcon({ size = 14, className = "" }: { size?: number; className?: string }) {
  return (
    <span className={`merge-request-icon${className ? ` ${className}` : ""}`} style={{ width: size, height: size }} aria-hidden="true">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.35" strokeLinecap="round" strokeLinejoin="round" focusable="false">
        <circle cx="7" cy="7" r="2.2" />
        <circle cx="7" cy="17" r="2.2" />
        <line x1="7" y1="9.2" x2="7" y2="14.8" />
        <circle cx="17" cy="17" r="2.2" />
        <path d="M17 14.8V10.5A3.5 3.5 0 0 0 13.5 7H11" />
        <path d="M13.5 4.5 11 7l2.5 2.5" />
      </svg>
    </span>
  );
}

export function ClosedMergeRequestIcon({ size = 14, className = "" }: { size?: number; className?: string }) {
  return (
    <span className={`merge-request-icon merge-request-icon--closed${className ? ` ${className}` : ""}`} style={{ width: size, height: size }} aria-hidden="true">
      <svg viewBox="0 0 120 120" fill="none" focusable="false">
        <g stroke="currentColor" strokeWidth="14" strokeLinecap="round" strokeLinejoin="round" fill="none">
          <line x1="18" y1="18" x2="38" y2="38" />
          <line x1="38" y1="18" x2="18" y2="38" />
          <line x1="28" y1="60" x2="28" y2="78" />
          <circle cx="28" cy="92" r="14" />
          <path d="M60 28h16a16 16 0 0 1 16 16v34" />
          <circle cx="92" cy="92" r="14" />
        </g>
      </svg>
    </span>
  );
}

export function MergeRequestBadge({ count, className = "" }: { count?: number | null; className?: string }) {
  if (!count || count < 1) return null;

  return (
    <span className={`merge-request-badge ${className}`.trim()} title={`${count} linked merge ${count === 1 ? "request" : "requests"}`} aria-label={`${count} linked merge ${count === 1 ? "request" : "requests"}`}>
      <MergeRequestIcon size={13} />
      {count > 1 && <span className="merge-request-badge-count">{count}</span>}
    </span>
  );
}
