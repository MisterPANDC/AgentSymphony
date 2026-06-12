import { Search } from "lucide-react";

export function CommandPalette() {
  return (
    <button className="text-button w-full max-w-[360px] justify-start text-[#64748b]" title="Command palette">
      <Search size={15} />
      <span className="truncate">Search issues, runs, settings</span>
      <span className="ml-auto mono text-[11px] text-[#94a3b8]">⌘K</span>
    </button>
  );
}
