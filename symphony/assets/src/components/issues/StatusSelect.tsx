import { useEffect, useRef, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Check, ChevronDown } from "lucide-react";
import { updateIssueWorkflow } from "../../api/issues";
import { workflowStatuses, type WorkflowStatus } from "../../types/issue";
import { formatStatusLabel, StatusIcon } from "./StatusIcon";

export function StatusSelect({ issueId, value }: { issueId: string; value: WorkflowStatus }) {
  const queryClient = useQueryClient();
  const menuRef = useRef<HTMLDivElement>(null);
  const [open, setOpen] = useState(false);
  const mutation = useMutation({
    mutationFn: (status: WorkflowStatus) => updateIssueWorkflow(issueId, status, "changed from dashboard"),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["issues"] });
      queryClient.invalidateQueries({ queryKey: ["monitor-state"] });
    }
  });

  useEffect(() => {
    if (!open) {
      return;
    }

    function onPointerDown(event: PointerEvent) {
      if (!menuRef.current?.contains(event.target as Node)) {
        setOpen(false);
      }
    }

    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") {
        setOpen(false);
      }
    }

    document.addEventListener("pointerdown", onPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("pointerdown", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [open]);

  function selectStatus(status: WorkflowStatus) {
    setOpen(false);
    if (status !== value) {
      mutation.mutate(status);
    }
  }

  return (
    <div className="status-select-shell" ref={menuRef}>
      <button
        className={`status-select-trigger ${value}${open ? " is-open" : ""}`}
        type="button"
        disabled={mutation.isPending}
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => setOpen((current) => !current)}
      >
        <StatusIcon status={value} size={14} />
        <span>{formatStatusLabel(value)}</span>
        <ChevronDown className="status-select-chevron" size={12} />
      </button>
      {open && (
        <div className="status-select-menu" role="menu">
          {workflowStatuses.map((status) => {
            const selected = status === value;

            return (
              <button
                key={status}
                className={`status-select-option${selected ? " is-selected" : ""}`}
                type="button"
                role="menuitemradio"
                aria-checked={selected}
                onClick={() => selectStatus(status)}
              >
                <StatusIcon status={status} size={14} />
                <span>{formatStatusLabel(status)}</span>
                {selected && <Check size={14} />}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}
