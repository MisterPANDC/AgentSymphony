import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type CSSProperties } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Ban, Check, ChevronDown } from "lucide-react";
import { updateIssueWorkflow } from "../../api/issues";
import { canUserTransition, isDispatchCandidateStatus, workflowStatuses, type IssueDTO, type WorkflowStatus } from "../../types/issue";
import { ActiveRunStopDialog } from "./ActiveRunStopDialog";
import { formatStatusLabel, StatusIcon } from "./StatusIcon";

interface WorkflowStatusSelectProps {
  value: WorkflowStatus;
  onChange: (status: WorkflowStatus) => void;
  disabled?: boolean;
  disabledOptionTitle?: string;
  isOptionDisabled?: (status: WorkflowStatus) => boolean;
  statuses?: readonly WorkflowStatus[];
  menuAlign?: "start" | "end";
  shellClassName?: string;
  triggerClassName?: string;
}

export function WorkflowStatusSelect({
  value,
  onChange,
  disabled = false,
  disabledOptionTitle = "This transition is controlled by Symphony workflow rules",
  isOptionDisabled,
  statuses = workflowStatuses,
  menuAlign = "end",
  shellClassName = "",
  triggerClassName = ""
}: WorkflowStatusSelectProps) {
  const menuRef = useRef<HTMLDivElement>(null);
  const menuPanelRef = useRef<HTMLDivElement>(null);
  const triggerRef = useRef<HTMLButtonElement>(null);
  const [open, setOpen] = useState(false);
  const [menuStyle, setMenuStyle] = useState<CSSProperties>({});
  const optionStatuses = statuses;

  const updateMenuPosition = useCallback(() => {
    const trigger = triggerRef.current;
    if (!trigger) {
      return;
    }

    const viewportMargin = 8;
    const menuOffset = 6;
    const menuWidth = 128;
    const menuHeaderHeight = 26;
    const fullMenuHeight = menuHeaderHeight + optionStatuses.length * 32 + 2;
    const rect = trigger.getBoundingClientRect();
    const containingBlock = findFixedContainingBlock(trigger);
    const availableBelow = window.innerHeight - rect.bottom - viewportMargin;
    const availableAbove = rect.top - viewportMargin;
    const placeAbove = availableBelow < fullMenuHeight && availableAbove > availableBelow;
    const availableSpace = placeAbove ? availableAbove : availableBelow;
    const maxHeight = Math.max(48, Math.min(fullMenuHeight, availableSpace - menuOffset));
    const preferredLeft = menuAlign === "start" ? rect.left : rect.right - menuWidth;
    const maxLeft = Math.max(viewportMargin, window.innerWidth - menuWidth - viewportMargin);
    const viewportLeft = Math.min(Math.max(viewportMargin, preferredLeft), maxLeft);
    const viewportTop = placeAbove ? rect.top - menuOffset - maxHeight : rect.bottom + menuOffset;

    setMenuStyle({
      left: viewportLeft - containingBlock.left,
      maxHeight,
      top: viewportTop - containingBlock.top,
      width: menuWidth
    });
  }, [menuAlign, optionStatuses]);

  useEffect(() => {
    if (!open) {
      return;
    }

    function onDocumentClick(event: MouseEvent) {
      const target = event.target as Node;
      if (!menuRef.current?.contains(target) && !menuPanelRef.current?.contains(target)) {
        setOpen(false);
      }
    }

    function onKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") {
        setOpen(false);
      }
    }

    document.addEventListener("click", onDocumentClick);
    document.addEventListener("keydown", onKeyDown);
    window.addEventListener("resize", updateMenuPosition);
    window.addEventListener("scroll", updateMenuPosition, true);
    return () => {
      document.removeEventListener("click", onDocumentClick);
      document.removeEventListener("keydown", onKeyDown);
      window.removeEventListener("resize", updateMenuPosition);
      window.removeEventListener("scroll", updateMenuPosition, true);
    };
  }, [open, updateMenuPosition]);

  useLayoutEffect(() => {
    if (open) {
      updateMenuPosition();
    }
  }, [open, updateMenuPosition]);

  function selectStatus(status: WorkflowStatus) {
    setOpen(false);
    if (status === value || isOptionDisabled?.(status)) {
      return;
    }

    onChange(status);
  }

  return (
    <div className={`status-select-shell${shellClassName ? ` ${shellClassName}` : ""}`} ref={menuRef}>
      <button
        ref={triggerRef}
        className={`status-select-trigger ${value}${open ? " is-open" : ""}${triggerClassName ? ` ${triggerClassName}` : ""}`}
        type="button"
        disabled={disabled}
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => setOpen((current) => !current)}
      >
        <StatusIcon status={value} size={14} />
        <span>{formatStatusLabel(value)}</span>
        <ChevronDown className="status-select-chevron" size={12} />
      </button>
      {open && (
        <div className="status-select-menu" ref={menuPanelRef} role="menu" style={menuStyle}>
          <div className="status-select-menu-header">
            <span>Status</span>
          </div>
          {optionStatuses.map((status) => {
            const selected = status === value;
            const optionDisabled = !selected && Boolean(isOptionDisabled?.(status));

            return (
              <button
                key={status}
                className={`status-select-option${selected ? " is-selected" : ""}${optionDisabled ? " is-disabled" : ""}`}
                type="button"
                role="menuitemradio"
                aria-checked={selected}
                aria-disabled={optionDisabled}
                disabled={optionDisabled}
                title={optionDisabled ? disabledOptionTitle : undefined}
                onPointerDown={(event) => {
                  event.preventDefault();
                  selectStatus(status);
                }}
                onClick={() => selectStatus(status)}
              >
                <StatusIcon status={status} size={14} />
                <span>{formatStatusLabel(status)}</span>
                {selected && <Check size={14} />}
                {optionDisabled && <Ban className="status-select-option-ban" size={13} />}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}

function findFixedContainingBlock(element: HTMLElement) {
  let parent = element.parentElement;
  while (parent && parent !== document.body) {
    const style = window.getComputedStyle(parent);
    if (style.transform !== "none" || style.filter !== "none" || style.perspective !== "none") {
      const rect = parent.getBoundingClientRect();
      return { left: rect.left, top: rect.top };
    }
    parent = parent.parentElement;
  }

  return { left: 0, top: 0 };
}

export function StatusSelect({ issue }: { issue: IssueDTO }) {
  const queryClient = useQueryClient();
  const value = issue.workflowStatus;
  const [pendingStatus, setPendingStatus] = useState<WorkflowStatus | null>(null);
  const transitionStatuses = useMemo(() => workflowStatuses.filter((status) => canUserTransition(value, status)), [value]);
  const mutation = useMutation({
    mutationFn: ({ status, confirmStopRun }: { status: WorkflowStatus; confirmStopRun?: boolean }) =>
      updateIssueWorkflow(issue.id, status, "changed from dashboard", { confirmStopRun }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["issues"] });
      queryClient.invalidateQueries({ queryKey: ["monitor-state"] });
      queryClient.invalidateQueries({ queryKey: ["runs"] });
    }
  });

  function selectStatus(status: WorkflowStatus) {
    if (status === value || !canUserTransition(value, status)) {
      return;
    }

    if (willStopActiveRun(status)) {
      setPendingStatus(status);
      return;
    }

    mutation.mutate({ status });
  }

  function confirmPendingStatus() {
    if (!pendingStatus) {
      return;
    }

    mutation.mutate({ status: pendingStatus, confirmStopRun: true });
    setPendingStatus(null);
  }

  function willStopActiveRun(status: WorkflowStatus) {
    return Boolean(issue.activeRunId) && !isDispatchCandidateStatus(status);
  }

  return (
    <>
      <WorkflowStatusSelect
        value={value}
        onChange={selectStatus}
        disabled={mutation.isPending}
        statuses={transitionStatuses}
      />
      <ActiveRunStopDialog
        open={Boolean(pendingStatus)}
        status={pendingStatus}
        pending={mutation.isPending}
        onCancel={() => setPendingStatus(null)}
        onConfirm={confirmPendingStatus}
      />
    </>
  );
}
