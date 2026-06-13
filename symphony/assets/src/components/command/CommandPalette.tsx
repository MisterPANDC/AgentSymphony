import { useEffect, useMemo, useState } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import { useNavigate } from "react-router-dom";
import { Search, X } from "lucide-react";

const commands = [
  { label: "Dashboard", description: "Issues and runtime overview", to: "/" },
  { label: "Issues", description: "Issue list and workflow controls", to: "/issues" },
  { label: "Board", description: "Workflow status board", to: "/board" },
  { label: "Agents", description: "Agent capacity and run history", to: "/agents" },
  { label: "Runs", description: "Run history", to: "/runs" },
  { label: "Run Monitor", description: "Runtime health and active work", to: "/monitor" },
  { label: "GitLab Settings", description: "GitLab connection settings", to: "/settings/gitlab" },
  { label: "Workflow Settings", description: "Workflow rules and limits", to: "/settings/workflow" }
];

export function CommandPalette() {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const navigate = useNavigate();

  const results = useMemo(() => {
    const needle = query.trim().toLowerCase();
    if (!needle) return commands;
    return commands.filter((command) => `${command.label} ${command.description}`.toLowerCase().includes(needle));
  }, [query]);

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        setOpen(true);
      }
    }

    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  function runCommand(to: string) {
    navigate(to);
    setOpen(false);
    setQuery("");
  }

  return (
    <Dialog.Root open={open} onOpenChange={setOpen}>
      <Dialog.Trigger asChild>
        <button className="command-trigger text-button min-w-0 justify-start text-[#686b73]" title="Command palette">
          <Search size={15} />
          <span className="command-trigger-label truncate">Search issues, runs, settings</span>
          <span className="command-trigger-shortcut ml-auto mono text-[11px] text-[#8a8d96]">⌘K</span>
        </button>
      </Dialog.Trigger>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-30 bg-black/10" />
        <Dialog.Content className="fixed left-1/2 top-16 z-40 w-[min(720px,calc(100vw-32px))] -translate-x-1/2 overflow-hidden rounded-lg border border-[#dedfe4] bg-[#ffffff] shadow-2xl">
          <Dialog.Title className="sr-only">Command palette</Dialog.Title>
          <div className="flex items-center gap-2 border-b border-[#eaebef] px-3 py-2">
            <Search size={16} className="text-[#686b73]" />
            <input
              autoFocus
              className="h-9 min-w-0 flex-1 bg-transparent text-sm outline-none placeholder:text-[#8a8d96]"
              placeholder="Search pages"
              value={query}
              onChange={(event) => setQuery(event.target.value)}
            />
            <Dialog.Close className="icon-button" title="Close command palette">
              <X size={15} />
            </Dialog.Close>
          </div>
          <div className="max-h-[420px] overflow-auto p-2">
            {results.length === 0 ? (
              <div className="px-2 py-6 text-center text-sm text-[#686b73]">No matching pages</div>
            ) : (
              results.map((command) => (
                <button
                  key={command.to}
                  className="flex w-full items-center justify-between gap-4 rounded-md px-3 py-2 text-left transition-colors hover:bg-[#f4f5f7]"
                  onClick={() => runCommand(command.to)}
                >
                  <span className="min-w-0">
                    <span className="block truncate text-sm font-medium">{command.label}</span>
                    <span className="block truncate text-xs text-[#686b73]">{command.description}</span>
                  </span>
                  <span className="mono shrink-0 text-[11px] text-[#8a8d96]">{command.to}</span>
                </button>
              ))
            )}
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
