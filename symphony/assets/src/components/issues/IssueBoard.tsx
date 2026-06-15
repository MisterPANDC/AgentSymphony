import { useEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { listIssues, updateIssueWorkflow } from "../../api/issues";
import { canUserTransition, isDispatchCandidateStatus, workflowStatuses, type IssueDTO, type WorkflowStatus } from "../../types/issue";
import { ActiveRunStopDialog } from "./ActiveRunStopDialog";
import { IssueColumn } from "./IssueColumn";
import { IssueDetailDrawer } from "./IssueDetailDrawer";
import { formatStatusLabel } from "./StatusIcon";
import { useIssueDetailSelection } from "./useIssueDetailSelection";

interface PendingTransition {
  issue: IssueDTO;
  status: WorkflowStatus;
}

interface PointerDrag {
  issue: IssueDTO;
  startX: number;
  startY: number;
  offsetX: number;
  offsetY: number;
  width: number;
  active: boolean;
}

interface DragPreview {
  x: number;
  y: number;
  width: number;
}

const collapsedStatusesStorageKey = "symphony.board.collapsed-statuses";

export function IssueBoard() {
  const queryClient = useQueryClient();
  const { data } = useQuery({ queryKey: ["issues"], queryFn: () => listIssues() });
  const issues = data?.issues ?? [];
  const { selectedIssue, openIssue, closeIssue } = useIssueDetailSelection(issues);
  const pointerDragRef = useRef<PointerDrag | null>(null);
  const [draggingIssue, setDraggingIssue] = useState<IssueDTO | null>(null);
  const [dragOverStatus, setDragOverStatus] = useState<WorkflowStatus | null>(null);
  const [dragPreview, setDragPreview] = useState<DragPreview | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [pendingTransition, setPendingTransition] = useState<PendingTransition | null>(null);
  const [collapsedStatuses, setCollapsedStatuses] = useState<WorkflowStatus[]>(readCollapsedStatuses);
  const transitionMutation = useMutation({
    mutationFn: ({ issue, status, confirmStopRun }: PendingTransition & { confirmStopRun?: boolean }) =>
      updateIssueWorkflow(issue.id, status, "changed from board drag", { confirmStopRun }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["issues"] });
      queryClient.invalidateQueries({ queryKey: ["monitor-state"] });
      queryClient.invalidateQueries({ queryKey: ["runs"] });
    },
    onError: (error) => {
      setNotice(error.message);
    }
  });

  useEffect(() => {
    if (!notice) {
      return;
    }

    const timeout = window.setTimeout(() => setNotice(null), 4200);
    return () => window.clearTimeout(timeout);
  }, [notice]);

  useEffect(() => {
    try {
      window.localStorage.setItem(collapsedStatusesStorageKey, JSON.stringify(collapsedStatuses));
    } catch {
      // localStorage can be unavailable in restricted browser modes; keep the in-memory state working.
    }
  }, [collapsedStatuses]);

  useEffect(() => {
    function onPointerMove(event: PointerEvent) {
      const currentDrag = pointerDragRef.current;

      if (!currentDrag) {
        return;
      }

      const distance = Math.hypot(event.clientX - currentDrag.startX, event.clientY - currentDrag.startY);
      const isActive = currentDrag.active || distance > 6;

      if (!isActive) {
        return;
      }

      event.preventDefault();

      if (!currentDrag.active) {
        currentDrag.active = true;
        setNotice(null);
        setDraggingIssue(currentDrag.issue);
      }

      setDragPreview({
        x: event.clientX - currentDrag.offsetX,
        y: event.clientY - currentDrag.offsetY,
        width: currentDrag.width
      });
      setDragOverStatus(statusFromPoint(event.clientX, event.clientY));
    }

    function onPointerUp(event: PointerEvent) {
      const currentDrag = pointerDragRef.current;

      if (!currentDrag) {
        return;
      }

      pointerDragRef.current = null;
      setDraggingIssue(null);
      setDragPreview(null);
      setDragOverStatus(null);

      if (!currentDrag.active) {
        openIssue(currentDrag.issue);
        return;
      }

      const status = statusFromPoint(event.clientX, event.clientY);

      if (status) {
        attemptTransition(currentDrag.issue, status);
      }
    }

    function onPointerCancel() {
      pointerDragRef.current = null;
      setDraggingIssue(null);
      setDragPreview(null);
      setDragOverStatus(null);
    }

    window.addEventListener("pointermove", onPointerMove, { passive: false });
    window.addEventListener("pointerup", onPointerUp);
    window.addEventListener("pointercancel", onPointerCancel);

    return () => {
      window.removeEventListener("pointermove", onPointerMove);
      window.removeEventListener("pointerup", onPointerUp);
      window.removeEventListener("pointercancel", onPointerCancel);
    };
  });

  function onIssuePointerDown(event: ReactPointerEvent<HTMLElement>, issue: IssueDTO) {
    if (transitionMutation.isPending) {
      event.preventDefault();
      return;
    }

    if (event.button !== 0) {
      return;
    }

    event.preventDefault();
    const rect = event.currentTarget.getBoundingClientRect();

    pointerDragRef.current = {
      issue,
      startX: event.clientX,
      startY: event.clientY,
      offsetX: event.clientX - rect.left,
      offsetY: event.clientY - rect.top,
      width: rect.width,
      active: false
    };
  }

  function attemptTransition(issue: IssueDTO, status: WorkflowStatus) {
    if (status === issue.workflowStatus) {
      return;
    }

    if (!canUserTransition(issue.workflowStatus, status)) {
      setNotice(
        `${issue.identifier} cannot move from ${formatStatusLabel(issue.workflowStatus)} to ${formatStatusLabel(status)}. This transition is controlled by Symphony workflow rules.`
      );
      return;
    }

    if (willStopActiveRun(issue, status)) {
      setPendingTransition({ issue, status });
      return;
    }

    transitionMutation.mutate({ issue, status });
  }

  function confirmPendingTransition() {
    if (!pendingTransition) {
      return;
    }

    transitionMutation.mutate({ ...pendingTransition, confirmStopRun: true });
    setPendingTransition(null);
  }

  function dropState(status: WorkflowStatus) {
    if (!draggingIssue) {
      return "idle";
    }

    if (status === draggingIssue.workflowStatus) {
      return "current";
    }

    return canUserTransition(draggingIssue.workflowStatus, status) ? "allowed" : "denied";
  }

  function willStopActiveRun(issue: IssueDTO, status: WorkflowStatus) {
    return Boolean(issue.activeRunId) && !isDispatchCandidateStatus(status);
  }

  function toggleColumn(status: WorkflowStatus) {
    setCollapsedStatuses((current) => (current.includes(status) ? current.filter((item) => item !== status) : [...current, status]));
  }

  const visibleStatuses = workflowStatuses.filter((status) => !collapsedStatuses.includes(status));
  const hiddenStatuses = workflowStatuses.filter((status) => collapsedStatuses.includes(status));

  return (
    <>
      {notice && <div className="board-drag-notice">{notice}</div>}
      <div className="board-scroll-shell">
        <div className="board-lane-grid">
          {visibleStatuses.map((status) => (
            <IssueColumn
              key={status}
              status={status}
              issues={issues.filter((issue) => issue.workflowStatus === status)}
              draggingIssue={draggingIssue}
              dropState={dropState(status)}
              isDragOver={dragOverStatus === status}
              dragDisabled={transitionMutation.isPending}
              collapsed={false}
              onCollapsedChange={() => toggleColumn(status)}
              onIssueCreated={openIssue}
              onIssueOpen={openIssue}
              onIssuePointerDown={onIssuePointerDown}
            />
          ))}
          {hiddenStatuses.length > 0 && (
            <aside className="board-hidden-columns" aria-label="Hidden columns">
              <div className="board-column-header board-hidden-columns-header">
                <h2 className="board-column-title">
                  <span>Hidden columns</span>
                </h2>
              </div>
              <div className="board-column-body board-hidden-column-list">
                {hiddenStatuses.map((status) => (
                  <IssueColumn
                    key={status}
                    status={status}
                    issues={issues.filter((issue) => issue.workflowStatus === status)}
                    draggingIssue={draggingIssue}
                    dropState={dropState(status)}
                    isDragOver={dragOverStatus === status}
                    dragDisabled={transitionMutation.isPending}
                    collapsed
                    onCollapsedChange={() => toggleColumn(status)}
                    onIssueCreated={openIssue}
                    onIssueOpen={openIssue}
                    onIssuePointerDown={onIssuePointerDown}
                  />
                ))}
              </div>
            </aside>
          )}
        </div>
      </div>
      {draggingIssue && dragPreview && (
        <div
          className="board-drag-preview"
          style={{
            left: dragPreview.x,
            top: dragPreview.y,
            width: dragPreview.width
          }}
        >
          <span className="mono text-[11px] text-[#686b73]">#{draggingIssue.iid}</span>
          <span className="line-clamp-2 text-sm font-medium leading-5 text-[#1d1d1f]">{draggingIssue.title}</span>
        </div>
      )}
      <ActiveRunStopDialog
        open={Boolean(pendingTransition)}
        status={pendingTransition?.status ?? null}
        pending={transitionMutation.isPending}
        onCancel={() => setPendingTransition(null)}
        onConfirm={confirmPendingTransition}
      />
      <IssueDetailDrawer issue={selectedIssue} onClose={closeIssue} />
    </>
  );
}

function statusFromPoint(x: number, y: number) {
  const element = document.elementFromPoint(x, y);
  const status = element?.closest<HTMLElement>("[data-workflow-status]")?.dataset.workflowStatus;

  return workflowStatuses.includes(status as WorkflowStatus) ? (status as WorkflowStatus) : null;
}

function readCollapsedStatuses(): WorkflowStatus[] {
  try {
    const storedStatuses = JSON.parse(window.localStorage.getItem(collapsedStatusesStorageKey) ?? "[]");

    if (!Array.isArray(storedStatuses)) {
      return [];
    }

    return storedStatuses.filter((status): status is WorkflowStatus => workflowStatuses.includes(status as WorkflowStatus));
  } catch {
    return [];
  }
}
