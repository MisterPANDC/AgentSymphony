import { useEffect, useRef, useState, type KeyboardEvent as ReactKeyboardEvent } from "react";
import { createPortal } from "react-dom";
import * as Dialog from "@radix-ui/react-dialog";
import { Check, ChevronDown, ChevronRight, CornerUpLeft, ExternalLink, Link2, LoaderCircle, Maximize2, Minimize2, MoreHorizontal, Pencil, Plus, Tag, Trash2, X } from "lucide-react";
import { useMutation, useQuery, useQueryClient, type QueryClient } from "@tanstack/react-query";
import {
  createIssueNoteReply,
  createMergeRequestNoteReply,
  createMergeRequestNote,
  deleteIssueNote,
  deleteMergeRequestNote,
  getIssueMergeRequests,
  getIssueNotes,
  getMergeRequestNotes,
  updateIssueDescription,
  updateIssueTitle,
  updateMergeRequestGitLab,
  updateMergeRequestNote
} from "../../api/issues";
import type { IssueDTO, MergeRequestDTO, NoteDTO } from "../../types/issue";
import { IssueRelationsSummary } from "./BlockerEditor";
import { GitLabMeta } from "./GitLabMeta";
import { IssueLabelEditor } from "./IssueLabelEditor";
import { ClosedMergeRequestIcon, MergeRequestIcon } from "./MergeRequestIcon";
import { IssueNoteComposer, type NoteQuickAction } from "./IssueNoteComposer";
import { StatusSelect } from "./StatusSelect";
import { StatusIcon } from "./StatusIcon";

type InlineComposerState = { noteId: string; mode: "reply" | "edit" } | null;
type NoteMutationResult = Promise<{ notes: NoteDTO[] }>;
type NoteThreadTarget = {
  queryKey?: readonly unknown[];
  webUrl?: string;
  createNote?: (body: string, files: File[]) => NoteMutationResult;
  createReply?: (discussionId: string, body: string, files: File[]) => NoteMutationResult;
  updateNote?: (noteId: number | string, body: string, files: File[]) => NoteMutationResult;
  deleteNote?: (noteId: number | string) => NoteMutationResult;
};

type NoteThread = { root: NoteDTO; replies: NoteDTO[] };

const MERGE_REQUEST_READY_ACTION: NoteQuickAction = { command: "/ready", description: "Mark this merge request as ready." };
const MERGE_REQUEST_DRAFT_ACTION: NoteQuickAction = { command: "/draft", description: "Mark this merge request as draft." };
const MERGE_REQUEST_QUICK_ACTIONS: NoteQuickAction[] = [MERGE_REQUEST_READY_ACTION, MERGE_REQUEST_DRAFT_ACTION];

export function IssueDetailDrawer({ issue, onClose }: { issue: IssueDTO | null; onClose: () => void }) {
  const dialogRef = useRef<HTMLDivElement | null>(null);
  const issuePaneBodyRef = useRef<HTMLDivElement | null>(null);
  const issueComposerRef = useRef<HTMLDivElement | null>(null);
  const unlockDialogHeightFrameRef = useRef<number | null>(null);
  const [expandedPane, setExpandedPane] = useState<"issue" | "merge-request" | null>(null);
  const [inlineComposer, setInlineComposer] = useState<InlineComposerState>(null);
  const [mergeRequestInlineComposer, setMergeRequestInlineComposer] = useState<InlineComposerState>(null);
  const [descriptionEditing, setDescriptionEditing] = useState(false);
  const [mergeRequestDescriptionEditing, setMergeRequestDescriptionEditing] = useState(false);
  const [lockedDialogHeight, setLockedDialogHeight] = useState<number | null>(null);
  const [mergeRequestMenuOpen, setMergeRequestMenuOpen] = useState(false);
  const [issuePaneAtBottom, setIssuePaneAtBottom] = useState(true);
  const [selectedMergeRequestId, setSelectedMergeRequestId] = useState<number | null>(null);
  const { data } = useQuery({
    queryKey: ["issue-notes", issue?.id],
    queryFn: () => getIssueNotes(issue!.id),
    enabled: Boolean(issue)
  });
  const mergeRequestQuery = useQuery({
    queryKey: ["issue-merge-requests", issue?.id],
    queryFn: () => getIssueMergeRequests(issue!.id),
    enabled: Boolean(issue && (issue.mergeRequestCount ?? 0) > 0),
    staleTime: 30_000
  });
  const notes = data?.notes ?? [];
  const noteThreads = groupNoteThreads(notes);
  const userCommentCount = notes.filter((note) => !note.system).length;
  const mergeRequests = mergeRequestQuery.data?.mergeRequests ?? [];
  const selectedMergeRequest = mergeRequests.find((mergeRequest) => mergeRequest.id === selectedMergeRequestId) ?? null;
  const mergeRequestNotesQueryKey = ["merge-request-notes", issue?.id, selectedMergeRequest?.iid] as const;
  const mergeRequestNotesQuery = useQuery({
    queryKey: mergeRequestNotesQueryKey,
    queryFn: () => getMergeRequestNotes(issue!.id, selectedMergeRequest!.iid),
    enabled: Boolean(issue && selectedMergeRequest),
    staleTime: 30_000
  });
  const mergeRequestNotes = mergeRequestNotesQuery.data?.notes ?? [];

  useEffect(() => {
    clearScheduledDialogHeightUnlock();
    setExpandedPane(null);
    setInlineComposer(null);
    setMergeRequestInlineComposer(null);
    setDescriptionEditing(false);
    setMergeRequestDescriptionEditing(false);
    setLockedDialogHeight(null);
    setMergeRequestMenuOpen(false);
    setSelectedMergeRequestId(null);
  }, [issue?.id]);

  useEffect(() => {
    if (!selectedMergeRequestId || mergeRequests.some((mergeRequest) => mergeRequest.id === selectedMergeRequestId)) return;
    setSelectedMergeRequestId(null);
  }, [mergeRequests, selectedMergeRequestId]);

  useEffect(() => {
    setMergeRequestInlineComposer(null);
  }, [selectedMergeRequestId]);

  useEffect(() => {
    return () => clearScheduledDialogHeightUnlock();
  }, []);

  useEffect(() => {
    const frame = window.requestAnimationFrame(updateIssuePaneScrollState);
    return () => window.cancelAnimationFrame(frame);
  }, [issue?.id, notes.length, inlineComposer]);

  function clearScheduledDialogHeightUnlock() {
    if (unlockDialogHeightFrameRef.current === null) return;
    window.cancelAnimationFrame(unlockDialogHeightFrameRef.current);
    unlockDialogHeightFrameRef.current = null;
  }

  function unlockDialogHeightAfterLayout() {
    clearScheduledDialogHeightUnlock();
    unlockDialogHeightFrameRef.current = window.requestAnimationFrame(() => {
      unlockDialogHeightFrameRef.current = window.requestAnimationFrame(() => {
        setLockedDialogHeight(null);
        unlockDialogHeightFrameRef.current = null;
      });
    });
  }

  function lockDialogHeight() {
    clearScheduledDialogHeightUnlock();
    if (!expandedPane) {
      const height = dialogRef.current?.getBoundingClientRect().height;
      setLockedDialogHeight(height ? Math.round(height) : null);
    }
  }

  function startInlineComposer(noteId: string, mode: "reply" | "edit") {
    lockDialogHeight();
    setInlineComposer({ noteId, mode });
  }

  function startMergeRequestInlineComposer(noteId: string, mode: "reply" | "edit") {
    lockDialogHeight();
    setMergeRequestInlineComposer({ noteId, mode });
  }

  function cancelInlineComposer() {
    setInlineComposer(null);
    if (!descriptionEditing) {
      unlockDialogHeightAfterLayout();
    }
  }

  function cancelMergeRequestInlineComposer() {
    setMergeRequestInlineComposer(null);
    if (!mergeRequestDescriptionEditing) {
      unlockDialogHeightAfterLayout();
    }
  }

  function startDescriptionEditing() {
    lockDialogHeight();
    setDescriptionEditing(true);
  }

  function startMergeRequestDescriptionEditing() {
    lockDialogHeight();
    setMergeRequestDescriptionEditing(true);
  }

  function finishDescriptionEditing() {
    setDescriptionEditing(false);
    if (!inlineComposer) {
      unlockDialogHeightAfterLayout();
    }
  }

  function finishMergeRequestDescriptionEditing() {
    setMergeRequestDescriptionEditing(false);
    if (!mergeRequestInlineComposer) {
      unlockDialogHeightAfterLayout();
    }
  }

  function toggleIssueExpanded() {
    clearScheduledDialogHeightUnlock();
    setLockedDialogHeight(null);
    setExpandedPane((value) => (value === "issue" ? null : "issue"));
  }

  function toggleMergeRequestExpanded() {
    clearScheduledDialogHeightUnlock();
    setLockedDialogHeight(null);
    setExpandedPane((value) => (value === "merge-request" ? null : "merge-request"));
  }

  function closeDrawer() {
    clearScheduledDialogHeightUnlock();
    setExpandedPane(null);
    setDescriptionEditing(false);
    setMergeRequestDescriptionEditing(false);
    setLockedDialogHeight(null);
    onClose();
  }

  function closeIssuePane() {
    if (!selectedMergeRequest) {
      closeDrawer();
      return;
    }

    clearScheduledDialogHeightUnlock();
    setLockedDialogHeight(null);
    setMergeRequestMenuOpen(false);
    setInlineComposer(null);
    setDescriptionEditing(false);
    setExpandedPane("merge-request");
  }

  function scrollToIssueComposer() {
    scrollPaneToComposer(issuePaneBodyRef, issueComposerRef);
  }

  function updateIssuePaneScrollState() {
    setIssuePaneAtBottom(isPaneScrolledToBottom(issuePaneBodyRef.current));
  }

  return (
    <Dialog.Root
      open={Boolean(issue)}
      onOpenChange={(open) => {
        if (!open) {
          closeDrawer();
        }
      }}
    >
      <Dialog.Portal>
        <Dialog.Overlay className="issue-detail-overlay" />
        <Dialog.Content
          ref={dialogRef}
          className={`issue-detail-dialog${expandedPane ? " is-expanded" : ""}${expandedPane === "issue" ? " is-issue-expanded" : ""}${expandedPane === "merge-request" ? " is-merge-request-expanded" : ""}${selectedMergeRequest ? " has-merge-request-panel" : ""}`}
          style={!expandedPane && lockedDialogHeight ? { height: lockedDialogHeight } : undefined}
          onEscapeKeyDown={keepDrawerOpenForInlineEditing}
        >
          {issue && (
            <>
              <Dialog.Description className="issue-detail-title--hidden">
                Issue details, description, labels, and activity for {issue.identifier}.
              </Dialog.Description>
              <div className="issue-detail-dialog-content">
                <div className="issue-detail-pane">
                  <div ref={issuePaneBodyRef} className="issue-detail-dialog-body" onScroll={updateIssuePaneScrollState}>
                    <div className="issue-detail-dialog-header">
                      <div className="min-w-0 flex-1">
                        <IssueTitleEditor issue={issue} />
                        <div className="mt-2 flex flex-wrap items-center gap-2">
                          <GitLabMeta issue={issue} showLink={false} />
                          <StatusSelect issue={issue} />
                          <MergeRequestSelector
                            issue={issue}
                            mergeRequests={mergeRequests}
                            loading={mergeRequestQuery.isFetching}
                            error={mergeRequestQuery.isError ? mergeRequestQuery.error.message : null}
                            open={mergeRequestMenuOpen}
                            onOpenChange={setMergeRequestMenuOpen}
                            selectedMergeRequest={selectedMergeRequest}
                            onSelect={(mergeRequest) => {
                              setSelectedMergeRequestId(mergeRequest.id);
                              setMergeRequestMenuOpen(false);
                            }}
                          />
                          <IssueRelationsSummary issue={issue} />
                          {issue.isBlocked && (
                            <span className="status-pill blocked">
                              <StatusIcon status="blocked" size={12} />
                              blocked
                            </span>
                          )}
                        </div>
                      </div>
                      <div className="pane-actions issue-pane-actions" aria-label="Issue pane actions">
                        <button
                          className="dialog-close-button"
                          type="button"
                          aria-label={expandedPane === "issue" ? "Restore issue pane" : "Expand issue pane"}
                          title={expandedPane === "issue" ? "Restore issue pane" : "Expand issue pane"}
                          onClick={toggleIssueExpanded}
                        >
                          {expandedPane === "issue" ? <Minimize2 size={15} /> : <Maximize2 size={15} />}
                        </button>
                        <button
                          className="dialog-close-button"
                          type="button"
                          aria-label={selectedMergeRequest ? "Close issue pane" : "Close issue details"}
                          title={selectedMergeRequest ? "Close issue pane" : "Close issue details"}
                          onClick={closeIssuePane}
                        >
                          <X size={15} />
                        </button>
                      </div>
                    </div>
                    <IssueLabelEditor issue={issue} />
                    <IssueDescriptionEditor issue={issue} onStartEditing={startDescriptionEditing} onFinishEditing={finishDescriptionEditing} />
                    <section className="issue-activity-section">
                      <div className="issue-activity-header">
                        <h3 className="issue-activity-title">Activity</h3>
                        <span className="issue-activity-count">
                          {userCommentCount} {userCommentCount === 1 ? "comment" : "comments"}
                        </span>
                      </div>
                      <div className="issue-activity-list" aria-label="Issue activity">
                        {noteThreads.length > 0 ? (
                          noteThreads.map((thread) => (
                            <ActivityNote
                              key={thread.root.id}
                              thread={thread}
                              issue={issue}
                              activeComposer={inlineComposer}
                              onStartReply={(noteId) => startInlineComposer(noteId, "reply")}
                              onStartEdit={(noteId) => startInlineComposer(noteId, "edit")}
                              onCancelInline={cancelInlineComposer}
                            />
                          ))
                        ) : (
                          <div className="issue-activity-empty">No activity yet.</div>
                        )}
                      </div>
                      {!inlineComposer && (
                        <div ref={issueComposerRef} className="issue-activity-composer">
                          <IssueNoteComposer issueId={issue.id} />
                        </div>
                      )}
                    </section>
                  </div>
                  <button
                    className={`issue-scroll-to-composer-button${issuePaneAtBottom ? " is-hidden" : ""}`}
                    type="button"
                    aria-label="Scroll to comment composer"
                    title="Scroll to comment composer"
                    onClick={scrollToIssueComposer}
                  >
                    <ChevronDown size={18} />
                  </button>
                </div>
                <MergeRequestDetailPanel
                  issue={issue}
                  mergeRequest={selectedMergeRequest}
                  onStartDescriptionEditing={startMergeRequestDescriptionEditing}
                  onFinishDescriptionEditing={finishMergeRequestDescriptionEditing}
                  notes={mergeRequestNotes}
                  notesLoading={mergeRequestNotesQuery.isFetching}
                  notesError={mergeRequestNotesQuery.isError ? mergeRequestNotesQuery.error.message : null}
                  noteTarget={
                    selectedMergeRequest
                      ? {
                          queryKey: mergeRequestNotesQueryKey,
                          webUrl: selectedMergeRequest.webUrl,
                          createNote: (body, files) => createMergeRequestNote(issue.id, selectedMergeRequest.iid, body, files),
                          createReply: (discussionId, body, files) => createMergeRequestNoteReply(issue.id, selectedMergeRequest.iid, discussionId, body, files),
                          updateNote: (noteId, body, files) => updateMergeRequestNote(issue.id, selectedMergeRequest.iid, noteId, body, files),
                          deleteNote: (noteId) => deleteMergeRequestNote(issue.id, selectedMergeRequest.iid, noteId)
                        }
                      : undefined
                  }
                  activeComposer={mergeRequestInlineComposer}
                  onStartReply={(noteId) => startMergeRequestInlineComposer(noteId, "reply")}
                  onStartEdit={(noteId) => startMergeRequestInlineComposer(noteId, "edit")}
                  onCancelInline={cancelMergeRequestInlineComposer}
                  expanded={expandedPane === "merge-request"}
                  onToggleExpanded={toggleMergeRequestExpanded}
                  onClose={() => {
                    if (expandedPane === "merge-request") {
                      setExpandedPane(null);
                    }
                    setSelectedMergeRequestId(null);
                  }}
                />
              </div>
            </>
          )}
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

function MergeRequestSelector({
  issue,
  mergeRequests,
  loading,
  error,
  open,
  onOpenChange,
  selectedMergeRequest,
  onSelect
}: {
  issue: IssueDTO;
  mergeRequests: MergeRequestDTO[];
  loading: boolean;
  error: string | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  selectedMergeRequest: MergeRequestDTO | null;
  onSelect: (mergeRequest: MergeRequestDTO) => void;
}) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const availableCount = mergeRequests.length || issue.mergeRequestCount || 0;
  const shouldRender = availableCount > 0 || loading || Boolean(error);

  useEffect(() => {
    if (!open) return;

    function closeMenu(event: MouseEvent) {
      const target = event.target;
      if (target instanceof HTMLElement && containerRef.current?.contains(target)) return;
      onOpenChange(false);
    }

    document.addEventListener("mousedown", closeMenu);
    return () => document.removeEventListener("mousedown", closeMenu);
  }, [open, onOpenChange]);

  if (!shouldRender) return null;

  return (
    <div ref={containerRef} className="merge-request-selector">
      <button
        className={`merge-request-trigger${open ? " is-open" : ""}${selectedMergeRequest ? " has-selection" : ""}`}
        type="button"
        aria-label="Show linked merge requests"
        aria-expanded={open}
        title="Linked merge requests"
        onClick={() => onOpenChange(!open)}
      >
        <MergeRequestIcon size={13} />
        <span>{availableCount || "MR"}</span>
      </button>
      {open && (
        <div className="merge-request-menu" role="menu">
          <div className="merge-request-menu-header">
            <span>Merge requests</span>
            {loading && <LoaderCircle size={12} className="animate-spin" />}
          </div>
          {error ? (
            <div className="merge-request-menu-empty">{error}</div>
          ) : mergeRequests.length > 0 ? (
            <div className="merge-request-list">
              {mergeRequests.map((mergeRequest) => (
                <button
                  key={mergeRequest.id}
                  className={`merge-request-row${selectedMergeRequest?.id === mergeRequest.id ? " is-selected" : ""}`}
                  type="button"
                  role="menuitem"
                  onClick={() => onSelect(mergeRequest)}
                >
                  <span className="merge-request-row-main">
                    <MergeRequestIcon size={14} className={mergeRequest.draft ? "is-draft" : "is-ready"} />
                    <span className="merge-request-row-iid">!{mergeRequest.iid}</span>
                    <span className="merge-request-row-title-text">{mergeRequest.title}</span>
                  </span>
                  <span className="merge-request-row-status">
                    <MergeRequestDraftStatusText mergeRequest={mergeRequest} />
                    <MergeRequestGitLabStateBadge mergeRequest={mergeRequest} compact />
                  </span>
                </button>
              ))}
            </div>
          ) : (
            <div className="merge-request-menu-empty">Searching for Closes #{issue.iid}.</div>
          )}
        </div>
      )}
    </div>
  );
}

function MergeRequestDetailPanel({
  issue,
  mergeRequest,
  onStartDescriptionEditing,
  onFinishDescriptionEditing,
  notes,
  notesLoading,
  notesError,
  noteTarget,
  activeComposer,
  onStartReply,
  onStartEdit,
  onCancelInline,
  expanded,
  onToggleExpanded,
  onClose
}: {
  issue: IssueDTO;
  mergeRequest: MergeRequestDTO | null;
  onStartDescriptionEditing: () => void;
  onFinishDescriptionEditing: () => void;
  notes: NoteDTO[];
  notesLoading: boolean;
  notesError: string | null;
  noteTarget?: NoteThreadTarget;
  activeComposer: InlineComposerState;
  onStartReply: (noteId: string) => void;
  onStartEdit: (noteId: string) => void;
  onCancelInline: () => void;
  expanded: boolean;
  onToggleExpanded: () => void;
  onClose: () => void;
}) {
  const queryClient = useQueryClient();
  const mergeRequestPaneBodyRef = useRef<HTMLDivElement | null>(null);
  const mergeRequestComposerRef = useRef<HTMLDivElement | null>(null);
  const [mergeRequestPaneAtBottom, setMergeRequestPaneAtBottom] = useState(true);
  const notesLoaded = !notesLoading && !notesError;
  const noteThreads = groupNoteThreads(notes);
  const userCommentCount = notesLoaded ? notes.filter((note) => !note.system).length : mergeRequest?.userNotesCount ?? 0;

  useEffect(() => {
    const frame = window.requestAnimationFrame(updateMergeRequestPaneScrollState);
    return () => window.cancelAnimationFrame(frame);
  }, [mergeRequest?.id, notes.length, activeComposer, notesLoading, notesError]);

  async function applyMergeRequestQuickAction(action: NoteQuickAction) {
    if (!mergeRequest) throw new Error("Merge request is required");

    const draft = draftValueForMergeRequestQuickAction(action);
    if (draft === null) {
      throw new Error(`Unsupported merge request command: ${action.command}`);
    }

    updateMergeRequestCache(queryClient, issue.id, {
      ...mergeRequest,
      draft,
      workInProgress: draft
    });

    if (noteTarget?.queryKey) {
      queryClient.invalidateQueries({ queryKey: noteTarget.queryKey });
    }
  }

  function scrollToMergeRequestComposer() {
    scrollPaneToComposer(mergeRequestPaneBodyRef, mergeRequestComposerRef);
  }

  function updateMergeRequestPaneScrollState() {
    setMergeRequestPaneAtBottom(isPaneScrolledToBottom(mergeRequestPaneBodyRef.current));
  }

  return (
    <aside className={`merge-request-detail-panel${mergeRequest ? " is-visible" : ""}`} aria-hidden={!mergeRequest}>
      {mergeRequest && (
        <>
          <div ref={mergeRequestPaneBodyRef} className="merge-request-detail-body" onScroll={updateMergeRequestPaneScrollState}>
            <div className="merge-request-detail-dialog-header">
              <div className="min-w-0 flex-1">
                <MergeRequestTitleEditor issue={issue} mergeRequest={mergeRequest} />
                <div className="merge-request-header-meta">
                  <MergeRequestGitLabStateBadge mergeRequest={mergeRequest} />
                  <div className="merge-request-branch-strip">
                    <span className="mono">{mergeRequest.sourceBranch || "source"}</span>
                    <span aria-hidden="true">-&gt;</span>
                    <span className="mono">{mergeRequest.targetBranch || "target"}</span>
                  </div>
                  <MergeRequestDraftStatusText mergeRequest={mergeRequest} />
                </div>
              </div>
              <div className="pane-actions merge-request-pane-actions" aria-label="Merge request pane actions">
                <button
                  className="dialog-close-button"
                  type="button"
                  aria-label={expanded ? "Restore merge request pane" : "Expand merge request pane"}
                  title={expanded ? "Restore merge request pane" : "Expand merge request pane"}
                  onClick={onToggleExpanded}
                >
                  {expanded ? <Minimize2 size={15} /> : <Maximize2 size={15} />}
                </button>
                <button className="dialog-close-button" type="button" aria-label="Close merge request pane" title="Close merge request pane" onClick={onClose}>
                  <X size={15} />
                </button>
              </div>
            </div>

            <MergeRequestLabelEditor issue={issue} mergeRequest={mergeRequest} />

            <MergeRequestDescriptionEditor
              issue={issue}
              mergeRequest={mergeRequest}
              onStartEditing={onStartDescriptionEditing}
              onFinishEditing={onFinishDescriptionEditing}
            />

            <section className="issue-activity-section">
              <div className="issue-activity-header">
                <h3 className="issue-activity-title">Activity</h3>
                <span className="issue-activity-count">
                  {userCommentCount} {userCommentCount === 1 ? "comment" : "comments"}
                </span>
              </div>
              <div className="issue-activity-list" aria-label="Merge request activity">
                {notesError ? (
                  <div className="issue-activity-empty is-error">{notesError}</div>
                ) : noteThreads.length > 0 ? (
                  noteThreads.map((thread) => (
                    <ActivityNote
                      key={thread.root.id}
                      thread={thread}
                      issue={issue}
                      noteTarget={noteTarget}
                      activeComposer={activeComposer}
                      onStartReply={(noteId) => onStartReply(noteId)}
                      onStartEdit={(noteId) => onStartEdit(noteId)}
                      onCancelInline={onCancelInline}
                    />
                  ))
                ) : (
                  <div className="issue-activity-empty">{notesLoading ? "Loading activity..." : "No activity yet."}</div>
                )}
              </div>
              {!activeComposer && noteTarget && (
                <div ref={mergeRequestComposerRef} className="issue-activity-composer">
                  <IssueNoteComposer
                    issueId={issue.id}
                    queryKey={noteTarget.queryKey}
                    createNote={noteTarget.createNote}
                    updateNote={noteTarget.updateNote}
                    quickActions={MERGE_REQUEST_QUICK_ACTIONS}
                    quickActionButtons={mergeRequest.draft ? [MERGE_REQUEST_READY_ACTION] : []}
                    onQuickAction={applyMergeRequestQuickAction}
                  />
                </div>
              )}
            </section>
          </div>
          <button
            className={`issue-scroll-to-composer-button${mergeRequestPaneAtBottom ? " is-hidden" : ""}`}
            type="button"
            aria-label="Scroll to comment composer"
            title="Scroll to comment composer"
            onClick={scrollToMergeRequestComposer}
          >
            <ChevronDown size={18} />
          </button>
        </>
      )}
    </aside>
  );
}

function MergeRequestTitleEditor({ issue, mergeRequest }: { issue: IssueDTO; mergeRequest: MergeRequestDTO }) {
  const queryClient = useQueryClient();
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(mergeRequest.title);
  const shortIdentifier = `!${mergeRequest.iid}`;
  const titleHasChanges = draft.trim().length > 0 && draft.trim() !== mergeRequest.title;
  const mutation = useMutation({
    mutationFn: (title: string) => updateMergeRequestGitLab(issue.id, mergeRequest.iid, { title }),
    onSuccess: ({ mergeRequest: updatedMergeRequest }) => {
      updateMergeRequestCache(queryClient, issue.id, updatedMergeRequest);
      setEditing(false);
      setDraft(updatedMergeRequest.title);
    }
  });

  useEffect(() => {
    setEditing(false);
    setDraft(mergeRequest.title);
    mutation.reset();
  }, [mergeRequest.id, mergeRequest.title]);

  function beginEditing() {
    mutation.reset();
    setDraft(mergeRequest.title);
    setEditing(true);
  }

  function cancelEditing() {
    mutation.reset();
    setDraft(mergeRequest.title);
    setEditing(false);
  }

  function commitTitle() {
    if (mutation.isPending) return;

    const trimmed = draft.trim();
    if (!trimmed || trimmed === mergeRequest.title) {
      cancelEditing();
      return;
    }

    mutation.mutate(trimmed);
  }

  function handleTitleKeyDown(event: ReactKeyboardEvent<HTMLInputElement>) {
    if (event.key === "Enter") {
      event.preventDefault();
      event.stopPropagation();
      commitTitle();
      return;
    }

    if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      cancelEditing();
    }
  }

  return (
    <div className={`issue-title-editor merge-request-title-editor${editing ? " issue-title-editor--editing" : ""}`}>
      {editing ? (
        <>
          <span className="issue-title-identifier">{shortIdentifier}</span>
          <input
            autoFocus
            aria-label="Merge request title"
            className="issue-title-input"
            disabled={mutation.isPending}
            size={titleInputSize(draft || mergeRequest.title)}
            value={draft}
            onBlur={commitTitle}
            onChange={(event) => setDraft(event.target.value)}
            onKeyDown={handleTitleKeyDown}
          />
          {titleHasChanges && (
            <button
              className="issue-title-confirm"
              type="button"
              aria-label="Save merge request title"
              title="Save title"
              disabled={mutation.isPending}
              onMouseDown={(event) => event.preventDefault()}
              onClick={commitTitle}
            >
              <Check size={13} />
            </button>
          )}
          {mutation.isPending && <LoaderCircle className="issue-title-saving animate-spin" size={14} />}
        </>
      ) : (
        <>
          <button className="issue-title-display" type="button" aria-label="Edit merge request title" title="Edit title" disabled={mutation.isPending} onClick={beginEditing}>
            <span className="issue-title-identifier">{shortIdentifier}</span>
            <span className="issue-detail-title">{mergeRequest.title}</span>
          </button>
          {mergeRequest.webUrl && (
            <a className="issue-title-link" href={mergeRequest.webUrl} target="_blank" rel="noreferrer" aria-label="Open merge request in GitLab" title="Open in GitLab">
              <ExternalLink size={14} />
            </a>
          )}
          {mutation.isPending && <LoaderCircle className="issue-title-saving animate-spin" size={14} />}
        </>
      )}
      {mutation.isError && <div className="issue-title-error">{mutation.error.message}</div>}
    </div>
  );
}

function MergeRequestDraftStatusText({ mergeRequest }: { mergeRequest: MergeRequestDTO }) {
  const status = mergeRequest.draft ? "draft" : "ready";
  return <span className={`merge-request-draft-text is-${status}`}>{status.toUpperCase()}</span>;
}

function MergeRequestGitLabStateBadge({ mergeRequest, compact = false }: { mergeRequest: MergeRequestDTO; compact?: boolean }) {
  const state = mergeRequestGitLabState(mergeRequest);

  return (
    <span className={`merge-request-gitlab-state-badge is-${state}${compact ? " is-compact" : ""}`} aria-label={`GitLab merge request is ${state}`}>
      {state === "closed" ? <ClosedMergeRequestIcon size={compact ? 13 : 14} /> : <MergeRequestIcon size={compact ? 13 : 14} />}
      <span className="merge-request-gitlab-state-label">{state}</span>
    </span>
  );
}

function MergeRequestLabelEditor({ issue, mergeRequest }: { issue: IssueDTO; mergeRequest: MergeRequestDTO }) {
  const queryClient = useQueryClient();
  const [editingIndex, setEditingIndex] = useState<number | null>(null);
  const [editingValue, setEditingValue] = useState("");
  const [adding, setAdding] = useState(false);
  const [newValue, setNewValue] = useState("");
  const currentLabels = normalizeEditableLabels(mergeRequest.labels);
  const currentLabelsKey = editableLabelsKey(currentLabels);
  const mutation = useMutation({
    mutationFn: (labels: string[]) => updateMergeRequestGitLab(issue.id, mergeRequest.iid, { labels }),
    onSuccess: ({ mergeRequest: updatedMergeRequest }) => {
      updateMergeRequestCache(queryClient, issue.id, updatedMergeRequest);
      resetInlineState();
    }
  });

  useEffect(() => {
    resetInlineState();
    mutation.reset();
  }, [mergeRequest.id, currentLabelsKey]);

  function resetInlineState() {
    setEditingIndex(null);
    setEditingValue("");
    setAdding(false);
    setNewValue("");
  }

  function beginEditing(index: number, label: string) {
    mutation.reset();
    setAdding(false);
    setNewValue("");
    setEditingIndex(index);
    setEditingValue(label);
  }

  function beginAdding() {
    mutation.reset();
    setEditingIndex(null);
    setEditingValue("");
    setAdding(true);
    setNewValue("");
  }

  function commitNewLabel() {
    const labels = splitEditableLabelInput(newValue);
    if (labels.length === 0) {
      cancelInlineEdit();
      return;
    }

    commitLabels(normalizeEditableLabels([...currentLabels, ...labels]));
  }

  function commitExistingLabel(index: number) {
    const nextLabels = [...currentLabels];
    const trimmed = editingValue.trim();

    if (trimmed) {
      nextLabels[index] = trimmed;
    } else {
      nextLabels.splice(index, 1);
    }

    commitLabels(normalizeEditableLabels(nextLabels));
  }

  function removeLabel(index: number) {
    commitLabels(currentLabels.filter((_label, itemIndex) => itemIndex !== index));
  }

  function commitLabels(labels: string[]) {
    if (mutation.isPending) return;

    if (editableLabelsKey(labels) === currentLabelsKey) {
      cancelInlineEdit();
      return;
    }

    resetInlineState();
    mutation.mutate(labels);
  }

  function cancelInlineEdit() {
    resetInlineState();
    mutation.reset();
  }

  function handleNewLabelKeyDown(event: ReactKeyboardEvent<HTMLInputElement>) {
    if (event.key === "Enter" || event.key === ",") {
      event.preventDefault();
      event.stopPropagation();
      commitNewLabel();
      return;
    }

    if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      cancelInlineEdit();
    }
  }

  function handleExistingLabelKeyDown(event: ReactKeyboardEvent<HTMLInputElement>, index: number) {
    if (event.key === "Enter") {
      event.preventDefault();
      event.stopPropagation();
      commitExistingLabel(index);
      return;
    }

    if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      cancelInlineEdit();
    }
  }

  return (
    <section className="label-editor">
      <div className="label-editor-header">
        <h3>
          <Tag size={12} />
          Labels
        </h3>
        {mutation.isPending && <LoaderCircle className="label-editor-saving animate-spin" size={13} />}
      </div>
      <div className="label-editor-body">
        <div className="label-editor-input-shell">
          {currentLabels.map((label, index) => {
            const labelHasChanges = editingIndex === index && editingValue.trim().length > 0 && editingValue.trim() !== label;

            return editingIndex === index ? (
              <span key={`${label}-${index}`} className="label-editor-edit-chip">
                <input
                  autoFocus
                  aria-label={`Edit merge request label ${index + 1}`}
                  value={editingValue}
                  disabled={mutation.isPending}
                  placeholder="Label name"
                  size={labelInputSize(editingValue || label)}
                  onBlur={() => commitExistingLabel(index)}
                  onChange={(event) => setEditingValue(event.target.value)}
                  onKeyDown={(event) => handleExistingLabelKeyDown(event, index)}
                />
                {labelHasChanges && (
                  <button
                    className="label-editor-chip-confirm"
                    type="button"
                    aria-label={`Save label ${editingValue.trim()}`}
                    title="Save label"
                    disabled={mutation.isPending}
                    onMouseDown={(event) => event.preventDefault()}
                    onClick={() => commitExistingLabel(index)}
                  >
                    <Check size={11} />
                  </button>
                )}
                <button
                  className="label-editor-chip-delete"
                  type="button"
                  aria-label={`Remove ${label}`}
                  title={`Remove ${label}`}
                  disabled={mutation.isPending}
                  onMouseDown={(event) => event.preventDefault()}
                  onClick={() => removeLabel(index)}
                >
                  <Trash2 size={11} />
                </button>
              </span>
            ) : (
              <span key={`${label}-${index}`} className="label-editor-value-chip">
                <button
                  className="label-editor-chip-label"
                  type="button"
                  aria-label={`Edit merge request label ${label}`}
                  title={`Edit ${label}`}
                  disabled={mutation.isPending}
                  onClick={() => beginEditing(index, label)}
                >
                  <span>{label}</span>
                </button>
              </span>
            );
          })}
          {adding ? (
            <span className="label-editor-new-chip">
              <input
                autoFocus
                value={newValue}
                disabled={mutation.isPending}
                placeholder={currentLabels.length === 0 ? "Add label..." : "New label"}
                size={labelInputSize(newValue || "New label")}
                onBlur={commitNewLabel}
                onChange={(event) => setNewValue(event.target.value)}
                onKeyDown={handleNewLabelKeyDown}
              />
              <button type="button" title="Cancel new label" disabled={mutation.isPending} onMouseDown={(event) => event.preventDefault()} onClick={cancelInlineEdit}>
                <X size={11} />
              </button>
            </span>
          ) : (
            <button className="label-editor-add-chip" type="button" aria-label="Add merge request label" title="Add label" disabled={mutation.isPending} onClick={beginAdding}>
              <Plus size={13} />
            </button>
          )}
        </div>
        {mutation.isError && <div className="label-editor-error">{mutation.error.message}</div>}
      </div>
    </section>
  );
}

function MergeRequestDescriptionEditor({
  issue,
  mergeRequest,
  onStartEditing,
  onFinishEditing
}: {
  issue: IssueDTO;
  mergeRequest: MergeRequestDTO;
  onStartEditing: () => void;
  onFinishEditing: () => void;
}) {
  const queryClient = useQueryClient();
  const currentDescription = mergeRequest.description ?? "";
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(currentDescription);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const hasDescription = currentDescription.trim().length > 0;
  const descriptionHasChanges = draft !== currentDescription;
  const mutation = useMutation({
    mutationFn: (description: string) => updateMergeRequestGitLab(issue.id, mergeRequest.iid, { description }),
    onSuccess: ({ mergeRequest: updatedMergeRequest }) => {
      updateMergeRequestCache(queryClient, issue.id, updatedMergeRequest);
      setEditing(false);
      setDraft(updatedMergeRequest.description ?? "");
      onFinishEditing();
    }
  });

  useEffect(() => {
    setEditing(false);
    setDraft(currentDescription);
    mutation.reset();
  }, [mergeRequest.id, currentDescription]);

  useEffect(() => {
    if (!editing) return;

    const textarea = textareaRef.current;
    if (!textarea) return;

    const selectionPosition = textarea.value.length;
    const frame = window.requestAnimationFrame(() => {
      textarea.focus({ preventScroll: true });
      textarea.setSelectionRange(selectionPosition, selectionPosition);
    });

    return () => window.cancelAnimationFrame(frame);
  }, [editing, mergeRequest.id]);

  function beginEditing() {
    mutation.reset();
    setDraft(currentDescription);
    onStartEditing();
    setEditing(true);
  }

  function cancelEditing() {
    mutation.reset();
    setDraft(currentDescription);
    setEditing(false);
    onFinishEditing();
  }

  function commitDescription() {
    if (mutation.isPending) return;

    if (!descriptionHasChanges) {
      cancelEditing();
      return;
    }

    mutation.mutate(draft.trim().length > 0 ? draft : "");
  }

  function handleDescriptionKeyDown(event: ReactKeyboardEvent<HTMLTextAreaElement>) {
    if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
      event.preventDefault();
      event.stopPropagation();
      commitDescription();
      return;
    }

    if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      cancelEditing();
    }
  }

  return (
    <section className={`issue-description-section${editing ? " is-editing" : ""}`}>
      <div className="issue-description-header">
        <h3>Description</h3>
        {!editing && (
          <button
            className="issue-description-edit-button"
            type="button"
            aria-label="Edit merge request description"
            title="Edit description"
            disabled={mutation.isPending}
            onClick={beginEditing}
          >
            <Pencil size={12} />
          </button>
        )}
      </div>
      {editing ? (
        <div className="issue-description-editor">
          <textarea
            ref={textareaRef}
            autoFocus
            aria-label="Merge request description"
            className="issue-description-textarea"
            disabled={mutation.isPending}
            placeholder="Add description..."
            value={draft}
            onChange={(event) => setDraft(event.target.value)}
            onKeyDown={handleDescriptionKeyDown}
          />
          <div className="issue-description-editor-footer">
            <div className="issue-description-status" aria-live="polite">
              {mutation.isError ? mutation.error.message : mutation.isPending ? "Saving..." : ""}
            </div>
            <div className="issue-description-actions">
              <button className="text-button issue-description-secondary" type="button" disabled={mutation.isPending} onClick={cancelEditing}>
                Cancel
              </button>
              <button className="text-button issue-description-primary" type="button" disabled={mutation.isPending || !descriptionHasChanges} onClick={commitDescription}>
                {mutation.isPending ? <LoaderCircle className="animate-spin" size={13} /> : <Check size={13} />}
                Save
              </button>
            </div>
          </div>
        </div>
      ) : (
        <div className={`issue-description-card${hasDescription ? "" : " is-empty"}`}>{hasDescription ? renderMarkdown(currentDescription, issue) : "No description provided."}</div>
      )}
    </section>
  );
}

function updateMergeRequestCache(queryClient: QueryClient, issueId: string, updatedMergeRequest: MergeRequestDTO) {
  queryClient.setQueryData<{ mergeRequests: MergeRequestDTO[] }>(["issue-merge-requests", issueId], (previous) =>
    previous
      ? {
          ...previous,
          mergeRequests: previous.mergeRequests.map((mergeRequest) => (mergeRequest.id === updatedMergeRequest.id ? updatedMergeRequest : mergeRequest))
        }
      : previous
  );
  queryClient.invalidateQueries({ queryKey: ["issue-merge-requests", issueId] });
  queryClient.invalidateQueries({ queryKey: ["monitor-state"] });
}

function draftValueForMergeRequestQuickAction(action: NoteQuickAction) {
  if (action.command === "/draft") return true;
  if (action.command === "/ready") return false;
  return null;
}

function splitEditableLabelInput(input: string) {
  return input
    .split(",")
    .map((label) => label.trim())
    .filter(Boolean);
}

function normalizeEditableLabels(labels: string[]) {
  const seen = new Set<string>();

  return labels.reduce<string[]>((normalized, label) => {
    const trimmed = label.trim();
    if (!trimmed || seen.has(trimmed)) {
      return normalized;
    }

    seen.add(trimmed);
    return [...normalized, trimmed];
  }, []);
}

function editableLabelsKey(labels: string[]) {
  return labels.join("\n");
}

function labelInputSize(value: string) {
  return Math.min(Math.max(value.trim().length + 1, 9), 28);
}

function formatMergeRequestState(mergeRequest: MergeRequestDTO) {
  if (mergeRequest.state === "merged") return "merged";
  if (mergeRequest.state === "closed") return "closed";
  if (mergeRequest.state === "opened") return mergeRequest.draft ? "draft" : "open";
  return humanizeStatus(mergeRequest.state);
}

function mergeRequestStateClass(mergeRequest: MergeRequestDTO) {
  return formatMergeRequestState(mergeRequest).toLowerCase().replace(/\s+/g, "-");
}

function mergeRequestGitLabState(mergeRequest: MergeRequestDTO): "open" | "closed" {
  return mergeRequest.state === "closed" ? "closed" : "open";
}

function humanizeStatus(value: string) {
  return value
    .replace(/[_-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/^\w/, (letter) => letter.toUpperCase());
}

function groupNoteThreads(notes: NoteDTO[]): NoteThread[] {
  const threads: NoteThread[] = [];
  const threadByDiscussion = new Map<string, NoteThread>();

  for (const note of notes) {
    const discussionId = note.discussion_id;
    const isReply = note.discussion_reply === true;

    if (!discussionId || note.system || !isReply) {
      const thread = { root: note, replies: [] };
      threads.push(thread);

      if (discussionId && !note.system) {
        threadByDiscussion.set(discussionId, thread);
      }

      continue;
    }

    const existingThread = threadByDiscussion.get(discussionId);

    if (existingThread) {
      existingThread.replies.push(note);
    } else {
      threads.push({ root: note, replies: [] });
    }
  }

  return threads;
}

function scrollPaneToComposer(
  paneRef: { current: HTMLElement | null },
  composerRef: { current: HTMLElement | null }
) {
  const composer = composerRef.current;
  if (composer) {
    composer.scrollIntoView({ behavior: "smooth", block: "end" });
    window.requestAnimationFrame(() => {
      composer.querySelector<HTMLTextAreaElement>("textarea")?.focus({ preventScroll: true });
    });
    return;
  }

  const pane = paneRef.current;
  if (pane) {
    pane.scrollTo({ top: pane.scrollHeight, behavior: "smooth" });
  }
}

function isPaneScrolledToBottom(pane: HTMLElement | null) {
  if (!pane) return true;
  return pane.scrollHeight - pane.scrollTop - pane.clientHeight <= 12;
}

function ActivityNote({
  thread,
  issue,
  noteTarget,
  activeComposer,
  onStartReply,
  onStartEdit,
  onCancelInline
}: {
  thread: NoteThread;
  issue: IssueDTO;
  noteTarget?: NoteThreadTarget;
  activeComposer: InlineComposerState;
  onStartReply: (noteId: string) => void;
  onStartEdit: (noteId: string) => void;
  onCancelInline: () => void;
}) {
  const { root: note, replies } = thread;
  const authorName = note.author?.name || note.author?.username || "GitLab";
  const authorUsername = note.author?.username ? `@${note.author.username}` : null;
  const avatarUrl = authorAvatarUrl(note.author);
  const authorProfileUrl = authorWebUrl(note.author);
  const createdAt = note.gitlab_created_at;
  const updatedAt = note.gitlab_updated_at;
  const edited = Boolean(createdAt && updatedAt && new Date(updatedAt).getTime() - new Date(createdAt).getTime() > 1000);
  const [expanded, setExpanded] = useState(false);
  const rootActiveComposer = activeComposer?.noteId === note.id ? activeComposer.mode : null;
  const activeReplyComposer = replies.some((reply) => activeComposer?.noteId === reply.id);
  const showReplies = replies.length > 0 && (expanded || activeReplyComposer || rootActiveComposer === "reply");
  const replyCreateNote =
    note.discussion_id && (noteTarget?.createReply || !noteTarget)
      ? (body: string, files: File[]) => (noteTarget?.createReply ? noteTarget.createReply(note.discussion_id!, body, files) : createIssueNoteReply(issue.id, note.discussion_id!, body, files))
      : undefined;

  if (note.system) {
    return (
      <article className="issue-activity-item is-system">
        <div className="issue-activity-system-dot" aria-hidden="true" />
        <div className="issue-system-event">
          {authorProfileUrl ? (
            <a
              className="issue-activity-author issue-activity-author-link"
              href={authorProfileUrl}
              target="_blank"
              rel="noreferrer"
            >
              {authorName}
            </a>
          ) : (
            <span className="issue-activity-author">{authorName}</span>
          )}
          <span className="issue-system-event-body">{renderMarkdown(note.body, issue)}</span>
          {note.internal && <span className="issue-activity-pill">internal</span>}
          {createdAt && (
            <time className="issue-activity-time" dateTime={createdAt} title={formatExactDate(createdAt)}>
              {formatRelativeDate(createdAt)}
            </time>
          )}
        </div>
      </article>
    );
  }

  return (
    <article className={`issue-activity-item is-comment${rootActiveComposer || activeReplyComposer ? " has-inline-composer" : ""}`} id={note.note_id ? `note_${note.note_id}` : note.id}>
      <div className="issue-activity-avatar" aria-hidden="true">
        {avatarUrl ? <img src={avatarUrl} alt="" /> : <span>{authorInitials(authorName)}</span>}
      </div>
      <div className="issue-activity-note-card">
        <div className="issue-activity-note-header">
          <div className="issue-activity-note-meta">
            {authorProfileUrl ? (
              <a
                className="issue-activity-author issue-activity-author-link"
                href={authorProfileUrl}
                target="_blank"
                rel="noreferrer"
              >
                {authorName}
              </a>
            ) : (
              <span className="issue-activity-author">{authorName}</span>
            )}
            {authorUsername &&
              (authorProfileUrl ? (
                <a
                  className="issue-activity-username issue-activity-username-link"
                  href={authorProfileUrl}
                  target="_blank"
                  rel="noreferrer"
                >
                  {authorUsername}
                </a>
              ) : (
                <span className="issue-activity-username">{authorUsername}</span>
              ))}
            <span className="issue-activity-action">commented</span>
            {createdAt && (
              <time className="issue-activity-time" dateTime={createdAt} title={formatExactDate(createdAt)}>
                {formatRelativeDate(createdAt)}
              </time>
            )}
            {edited && <span className="issue-activity-action">edited</span>}
          </div>
          <div className={`issue-activity-note-tags${rootActiveComposer ? " is-placeholder" : ""}`}>
            {note.internal && <span className="issue-activity-pill">internal</span>}
            {rootActiveComposer ? (
              <span className="issue-comment-actions-placeholder" aria-hidden="true" />
            ) : (
              <CommentActions
                note={note}
                issue={issue}
                noteTarget={noteTarget}
                canReply={Boolean(replyCreateNote)}
                onStartReply={() => onStartReply(note.id)}
                onStartEdit={() => onStartEdit(note.id)}
                onCancelInline={onCancelInline}
              />
            )}
          </div>
        </div>
        {rootActiveComposer === "edit" ? (
          <div className="issue-activity-inline-composer is-edit">
            <IssueNoteComposer
              issueId={issue.id}
              mode="edit"
              noteId={note.note_id}
              initialBody={note.body}
              autoFocus
              queryKey={noteTarget?.queryKey}
              updateNote={noteTarget?.updateNote}
              createNote={noteTarget?.createNote}
              onCancel={onCancelInline}
              onSuccess={onCancelInline}
            />
          </div>
        ) : (
          <NoteBody body={note.body} issue={issue} />
        )}
        {replies.length > 0 && !showReplies && (
          <ReplySummary replies={replies} onToggle={() => setExpanded(true)} />
        )}
        {showReplies && (
          <div className="issue-activity-replies">
            <button className="issue-activity-replies-toggle" type="button" onClick={() => setExpanded(false)}>
              <ChevronDown size={14} />
              <span>Collapse replies</span>
            </button>
            {replies.map((reply) => (
              <ActivityReply
                key={reply.id}
                note={reply}
                issue={issue}
                noteTarget={noteTarget}
                activeComposer={activeComposer?.noteId === reply.id ? activeComposer.mode : null}
                onStartReply={() => onStartReply(note.id)}
                onStartEdit={() => onStartEdit(reply.id)}
                onCancelInline={onCancelInline}
              />
            ))}
          </div>
        )}
        {rootActiveComposer === "reply" && replyCreateNote && (
          <div className="issue-activity-inline-composer is-reply">
            <IssueNoteComposer
              issueId={issue.id}
              mode="reply"
              autoFocus
              queryKey={noteTarget?.queryKey}
              createNote={replyCreateNote}
              updateNote={noteTarget?.updateNote}
              onCancel={onCancelInline}
              onSuccess={onCancelInline}
            />
          </div>
        )}
      </div>
    </article>
  );
}

function ReplySummary({ replies, onToggle }: { replies: NoteDTO[]; onToggle: () => void }) {
  const lastReply = replies[replies.length - 1];
  const authorName = lastReply?.author?.name || lastReply?.author?.username || "GitLab";
  const avatarUrl = authorAvatarUrl(lastReply?.author ?? null);

  return (
    <button className="issue-activity-reply-summary" type="button" onClick={onToggle}>
      <ChevronRight size={14} />
      {avatarUrl && <img src={avatarUrl} alt="" />}
      <span className="issue-activity-reply-summary-count">
        {replies.length} {replies.length === 1 ? "reply" : "replies"}
      </span>
      {lastReply && (
        <span className="issue-activity-reply-summary-meta">
          Last reply by {authorName}
          {lastReply.gitlab_created_at ? ` ${formatRelativeDate(lastReply.gitlab_created_at)}` : ""}
        </span>
      )}
    </button>
  );
}

function ActivityReply({
  note,
  issue,
  noteTarget,
  activeComposer,
  onStartReply,
  onStartEdit,
  onCancelInline
}: {
  note: NoteDTO;
  issue: IssueDTO;
  noteTarget?: NoteThreadTarget;
  activeComposer: "reply" | "edit" | null;
  onStartReply: () => void;
  onStartEdit: () => void;
  onCancelInline: () => void;
}) {
  const authorName = note.author?.name || note.author?.username || "GitLab";
  const avatarUrl = authorAvatarUrl(note.author);
  const createdAt = note.gitlab_created_at;
  const updatedAt = note.gitlab_updated_at;
  const edited = Boolean(createdAt && updatedAt && new Date(updatedAt).getTime() - new Date(createdAt).getTime() > 1000);

  return (
    <div className={`issue-activity-reply${activeComposer ? " has-inline-composer" : ""}`} id={note.note_id ? `note_${note.note_id}` : note.id}>
      <div className="issue-activity-reply-avatar" aria-hidden="true">
        {avatarUrl ? <img src={avatarUrl} alt="" /> : <span>{authorInitials(authorName)}</span>}
      </div>
      <div className="issue-activity-reply-content">
        <div className="issue-activity-reply-header">
          <div className="issue-activity-note-meta">
            <span className="issue-activity-author">{authorName}</span>
            {createdAt && (
              <time className="issue-activity-time" dateTime={createdAt} title={formatExactDate(createdAt)}>
                {formatRelativeDate(createdAt)}
              </time>
            )}
            {edited && <span className="issue-activity-action">edited</span>}
          </div>
          {activeComposer ? (
            <span className="issue-comment-actions-placeholder" aria-hidden="true" />
          ) : (
            <CommentActions
              note={note}
              issue={issue}
              noteTarget={noteTarget}
              showReply={false}
              onStartReply={onStartReply}
              onStartEdit={onStartEdit}
              onCancelInline={onCancelInline}
            />
          )}
        </div>
        {activeComposer === "edit" ? (
          <div className="issue-activity-inline-composer is-edit">
            <IssueNoteComposer
              issueId={issue.id}
              mode="edit"
              noteId={note.note_id}
              initialBody={note.body}
              autoFocus
              queryKey={noteTarget?.queryKey}
              updateNote={noteTarget?.updateNote}
              createNote={noteTarget?.createNote}
              onCancel={onCancelInline}
              onSuccess={onCancelInline}
            />
          </div>
        ) : (
          <NoteBody body={note.body} issue={issue} />
        )}
      </div>
    </div>
  );
}

function CommentActions({
  note,
  issue,
  noteTarget,
  showReply = true,
  canReply = true,
  onStartReply,
  onStartEdit,
  onCancelInline
}: {
  note: NoteDTO;
  issue: IssueDTO;
  noteTarget?: NoteThreadTarget;
  showReply?: boolean;
  canReply?: boolean;
  onStartReply: () => void;
  onStartEdit: () => void;
  onCancelInline: () => void;
}) {
  const queryClient = useQueryClient();
  const [menuOpen, setMenuOpen] = useState(false);
  const [menuPosition, setMenuPosition] = useState<{ top: number; left: number } | null>(null);
  const [copyState, setCopyState] = useState<"idle" | "copied" | "failed">("idle");
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
  const menuButtonRef = useRef<HTMLButtonElement | null>(null);
  const notesQueryKey = noteTarget?.queryKey ?? ["issue-notes", issue.id];
  const commentUrl = `${noteTarget?.webUrl ?? issue.webUrl}#note_${note.note_id}`;
  const deleteMutation = useMutation({
    mutationFn: () => (noteTarget?.deleteNote ? noteTarget.deleteNote(note.note_id) : deleteIssueNote(issue.id, note.note_id)),
    onSuccess: (data) => {
      queryClient.setQueryData<{ notes: NoteDTO[] }>(notesQueryKey, data);
      queryClient.invalidateQueries({ queryKey: ["monitor-state"] });
      onCancelInline();
      setMenuOpen(false);
      setDeleteDialogOpen(false);
    }
  });

  function placeMenu() {
    const rect = menuButtonRef.current?.getBoundingClientRect();
    if (!rect) return;

    const menuWidth = Math.min(196, window.innerWidth - 24);
    setMenuPosition({
      top: rect.bottom + 4,
      left: Math.max(12, Math.min(rect.right - menuWidth, window.innerWidth - menuWidth - 12))
    });
  }

  useEffect(() => {
    if (!menuOpen) return;

    function closeMenu(event: MouseEvent) {
      const target = event.target;
      if (target instanceof HTMLElement && target.closest(`[data-comment-menu="${note.id}"]`)) return;
      setMenuOpen(false);
    }

    placeMenu();
    document.addEventListener("mousedown", closeMenu);
    window.addEventListener("resize", placeMenu);
    window.addEventListener("scroll", placeMenu, true);
    return () => {
      document.removeEventListener("mousedown", closeMenu);
      window.removeEventListener("resize", placeMenu);
      window.removeEventListener("scroll", placeMenu, true);
    };
  }, [menuOpen, note.id]);

  function beginEdit() {
    setMenuOpen(false);
    onStartEdit();
  }

  async function copyCommentLink() {
    try {
      await copyText(commentUrl);
      setCopyState("copied");
    } catch {
      setCopyState("failed");
    }
    setMenuOpen(false);
    window.setTimeout(() => setCopyState("idle"), 1600);
  }

  function deleteComment() {
    setMenuOpen(false);
    setDeleteDialogOpen(true);
  }

  function confirmDeleteComment() {
    deleteMutation.mutate();
  }

  const floatingActions = (
    <>
      {menuOpen && (
        <div className="issue-comment-menu" data-comment-menu={note.id} role="menu" style={menuPosition ? { top: menuPosition.top, left: menuPosition.left } : undefined}>
          <button type="button" role="menuitem" onClick={copyCommentLink}>
            <Link2 size={14} />
            Copy link to comment
          </button>
          <button type="button" role="menuitem" onClick={beginEdit}>
            <Pencil size={14} />
            Edit comment
          </button>
          <button className="is-danger" type="button" role="menuitem" disabled={deleteMutation.isPending} onClick={deleteComment}>
            <Trash2 size={14} />
            Delete comment
          </button>
        </div>
      )}
      <DeleteCommentDialog
        open={deleteDialogOpen}
        pending={deleteMutation.isPending}
        onCancel={() => setDeleteDialogOpen(false)}
        onConfirm={confirmDeleteComment}
      />
      {copyState !== "idle" && (
        <span className={`issue-comment-copy-state ${copyState}`} data-comment-menu={note.id} style={menuPosition ? { top: menuPosition.top, left: menuPosition.left } : undefined}>
          {copyState === "copied" ? "Copied" : "Copy failed"}
        </span>
      )}
      {deleteMutation.isError && (
        <span className="issue-comment-action-error" data-comment-menu={note.id} style={menuPosition ? { top: menuPosition.top, left: menuPosition.left } : undefined}>
          {deleteMutation.error.message}
        </span>
      )}
    </>
  );

  return (
    <div className="issue-comment-actions" data-comment-menu={note.id}>
      {showReply && (
        <button
          className="issue-comment-action-button"
          type="button"
          title={canReply ? "Reply to comment" : "Reply requires a synced GitLab discussion"}
          aria-label="Reply to comment"
          disabled={deleteMutation.isPending || !canReply}
          onClick={onStartReply}
        >
          <CornerUpLeft size={14} />
        </button>
      )}
      <button className="issue-comment-action-button" type="button" title="Edit comment" aria-label="Edit comment" disabled={deleteMutation.isPending} onClick={onStartEdit}>
        <Pencil size={14} />
      </button>
      <button
        ref={menuButtonRef}
        className="issue-comment-action-button"
        type="button"
        title="More actions"
        aria-label="More actions"
        aria-expanded={menuOpen}
        disabled={deleteMutation.isPending}
        onClick={() => {
          if (menuOpen) {
            setMenuOpen(false);
          } else {
            placeMenu();
            setMenuOpen(true);
          }
        }}
      >
        <MoreHorizontal size={15} />
      </button>
      {createPortal(floatingActions, document.body)}
    </div>
  );
}

function DeleteCommentDialog({
  open,
  pending,
  onCancel,
  onConfirm
}: {
  open: boolean;
  pending: boolean;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  return (
    <Dialog.Root open={open} onOpenChange={(nextOpen) => !nextOpen && !pending && onCancel()}>
      <Dialog.Portal>
        <Dialog.Overlay className="confirm-dialog-overlay issue-comment-delete-overlay" />
        <Dialog.Content className="confirm-dialog-content issue-comment-delete-dialog">
          <div className="confirm-dialog-body">
            <Dialog.Close className="issue-comment-delete-close" disabled={pending} aria-label="Close delete confirmation">
              <X size={16} />
            </Dialog.Close>
            <Dialog.Title className="confirm-dialog-title">Delete comment?</Dialog.Title>
            <Dialog.Description className="confirm-dialog-description">
              Are you sure you want to delete this comment?
            </Dialog.Description>
            <div className="confirm-dialog-actions">
              <button className="text-button" type="button" disabled={pending} onClick={onCancel}>
                Cancel
              </button>
              <button className="text-button confirm-dialog-danger issue-comment-delete-confirm" type="button" disabled={pending} onClick={onConfirm}>
                {pending ? "Deleting" : "Delete comment"}
              </button>
            </div>
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

async function copyText(text: string) {
  if (navigator.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(text);
      return;
    } catch {
      // Fall through to the selection-based fallback for local browser contexts
      // that expose the Clipboard API but reject writes without a permission grant.
    }
  }

  const textarea = document.createElement("textarea");
  textarea.value = text;
  textarea.setAttribute("readonly", "");
  textarea.style.position = "fixed";
  textarea.style.inset = "0 auto auto 0";
  textarea.style.opacity = "0";
  document.body.appendChild(textarea);
  textarea.select();
  const copied = document.execCommand("copy");
  document.body.removeChild(textarea);

  if (!copied) {
    throw new Error("Copy failed");
  }
}

function NoteBody({ body, issue }: { body: string; issue: IssueDTO }) {
  return <div className="issue-activity-note-body">{renderMarkdown(body, issue)}</div>;
}

function renderMarkdown(body: string, issue: IssueDTO) {
  const nodes: JSX.Element[] = [];
  const pattern = /(!?)\[([^\]]*)\]\(([^)\s]+)\)/g;
  let lastIndex = 0;
  let match: RegExpExecArray | null;

  while ((match = pattern.exec(body))) {
    if (match.index > lastIndex) {
      nodes.push(
        <span key={`text-${lastIndex}`} className="whitespace-pre-wrap">
          {renderPlainTextMarkdown(body.slice(lastIndex, match.index), issue, `text-${lastIndex}`)}
        </span>
      );
    }

    const [raw, imageMarker, label, url] = match;
    const resolvedUrl = resolveMarkdownUrl(url, issue);
    if (safeMarkdownUrl(resolvedUrl)) {
      nodes.push(imageMarker ? renderImage(label, resolvedUrl, match.index) : renderLink(label, resolvedUrl, match.index));
    } else {
      nodes.push(
        <span key={`unsafe-${match.index}`} className="whitespace-pre-wrap">
          {raw}
        </span>
      );
    }

    lastIndex = match.index + raw.length;
  }

  if (lastIndex < body.length) {
    nodes.push(
      <span key={`text-${lastIndex}`} className="whitespace-pre-wrap">
        {renderPlainTextMarkdown(body.slice(lastIndex), issue, `text-${lastIndex}`)}
      </span>
    );
  }

  return nodes.length > 0 ? nodes : <span className="whitespace-pre-wrap">{renderPlainTextMarkdown(body, issue, "text-0")}</span>;
}

function renderImage(label: string, url: string, key: number) {
  const external = isExternalUrl(url);
  return (
    <a key={`image-${key}`} className="issue-note-image-link" href={url} target={external ? "_blank" : undefined} rel={external ? "noreferrer" : undefined}>
      <img className="issue-note-image" src={url} alt={label || "attachment"} />
    </a>
  );
}

function renderLink(label: string, url: string, key: number) {
  const external = isExternalUrl(url);
  const referenceLabel = markdownReferenceLabel(label);
  return (
    <a key={`link-${key}`} className={`issue-note-link${referenceLabel ? " issue-note-link--reference" : ""}`} href={url} target={external ? "_blank" : undefined} rel={external ? "noreferrer" : undefined}>
      {referenceLabel || label || url}
    </a>
  );
}

function renderPlainTextMarkdown(text: string, issue: IssueDTO, keyPrefix: string) {
  const nodes: Array<JSX.Element | string> = [];
  const pattern = /\*\*([^*]+)\*\*/g;
  let lastIndex = 0;
  let match: RegExpExecArray | null;

  while ((match = pattern.exec(text))) {
    if (match.index > lastIndex) {
      nodes.push(...renderGitLabReferences(text.slice(lastIndex, match.index), issue, `${keyPrefix}-plain-${lastIndex}`));
    }

    nodes.push(
      <strong key={`${keyPrefix}-strong-${match.index}`} className="issue-note-strong">
        {renderGitLabReferences(match[1], issue, `${keyPrefix}-strong-${match.index}`)}
      </strong>
    );

    lastIndex = match.index + match[0].length;
  }

  if (lastIndex < text.length) {
    nodes.push(...renderGitLabReferences(text.slice(lastIndex), issue, `${keyPrefix}-plain-${lastIndex}`));
  }

  return nodes.length > 0 ? nodes : [text];
}

function renderGitLabReferences(text: string, issue: IssueDTO, keyPrefix: string): Array<JSX.Element | string> {
  const nodes: Array<JSX.Element | string> = [];
  const pattern = /(^|[^\w`/])([#!]\d+|@[A-Za-z0-9_](?:[A-Za-z0-9_.-]*[A-Za-z0-9_])?)/g;
  let lastIndex = 0;
  let match: RegExpExecArray | null;

  while ((match = pattern.exec(text))) {
    const [raw, prefix, reference] = match;
    const referenceStart = match.index + prefix.length;

    if (referenceStart > lastIndex) {
      nodes.push(text.slice(lastIndex, referenceStart));
    }

    nodes.push(
      <a key={`${keyPrefix}-ref-${referenceStart}`} className="issue-note-link issue-note-link--reference" href={resolveGitLabReferenceUrl(reference, issue)} target="_blank" rel="noreferrer">
        {reference}
      </a>
    );

    lastIndex = match.index + raw.length;
  }

  if (lastIndex < text.length) {
    nodes.push(text.slice(lastIndex));
  }

  return nodes.length > 0 ? nodes : [text];
}

function resolveGitLabReferenceUrl(reference: string, issue: IssueDTO) {
  const projectUrl = gitLabProjectUrl(issue);

  if (reference.startsWith("!")) {
    return `${projectUrl}/-/merge_requests/${reference.slice(1)}`;
  }

  if (reference.startsWith("#")) {
    return `${projectUrl}/-/issues/${reference.slice(1)}`;
  }

  return `${gitLabOriginUrl(issue)}/${encodeURIComponent(reference.slice(1))}`;
}

function gitLabProjectUrl(issue: IssueDTO) {
  const match = issue.webUrl.match(/^(.*)\/-\/issues\/\d+(?:[#?].*)?$/);
  return match ? match[1] : issue.webUrl.replace(/\/+$/, "");
}

function gitLabOriginUrl(issue: IssueDTO) {
  try {
    return new URL(issue.webUrl).origin;
  } catch {
    return gitLabProjectUrl(issue).split("/-/")[0];
  }
}

function safeMarkdownUrl(url: string) {
  return url.startsWith("/api/issues/") || isExternalUrl(url);
}

function resolveMarkdownUrl(url: string, issue: IssueDTO) {
  const uploadMatch = url.match(/^\/uploads\/([0-9a-fA-F]{32})\/(.+)$/);
  if (!uploadMatch) {
    if (url.startsWith("/")) {
      try {
        return new URL(url, issue.webUrl).toString();
      } catch {
        return url;
      }
    }
    return url;
  }

  const [, secret, filename] = uploadMatch;
  return `/api/issues/${issue.id}/uploads/${encodeURIComponent(secret)}/${encodeURIComponent(decodeURIComponent(filename))}`;
}

function isExternalUrl(url: string) {
  return url.startsWith("https://") || url.startsWith("http://");
}

function markdownReferenceLabel(label: string) {
  const trimmed = label.trim();
  return trimmed.startsWith("`") && trimmed.endsWith("`") && trimmed.length > 2 ? trimmed.slice(1, -1) : null;
}

function authorAvatarUrl(author: NoteDTO["author"]) {
  return author?.avatarUrl || author?.avatar_url || null;
}

function authorWebUrl(author: NoteDTO["author"]) {
  return author?.webUrl || author?.web_url || null;
}

function authorInitials(name: string) {
  const parts = name
    .trim()
    .split(/\s+/)
    .filter(Boolean);

  if (parts.length === 0) return "G";
  return parts
    .slice(0, 2)
    .map((part) => part[0])
    .join("")
    .toUpperCase();
}

function formatRelativeDate(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Unknown date";

  const seconds = Math.round((date.getTime() - Date.now()) / 1000);
  const absoluteSeconds = Math.abs(seconds);
  if (absoluteSeconds < 45) return "just now";

  const units: Array<[Intl.RelativeTimeFormatUnit, number]> = [
    ["year", 60 * 60 * 24 * 365],
    ["month", 60 * 60 * 24 * 30],
    ["week", 60 * 60 * 24 * 7],
    ["day", 60 * 60 * 24],
    ["hour", 60 * 60],
    ["minute", 60]
  ];
  const formatter = new Intl.RelativeTimeFormat("en-US", { numeric: "auto" });

  for (const [unit, unitSeconds] of units) {
    if (absoluteSeconds >= unitSeconds) {
      return formatter.format(Math.round(seconds / unitSeconds), unit);
    }
  }

  return formatter.format(seconds, "second");
}

function formatExactDate(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;

  return new Intl.DateTimeFormat("en-US", {
    dateStyle: "medium",
    timeStyle: "short"
  }).format(date);
}

function IssueTitleEditor({ issue }: { issue: IssueDTO }) {
  const queryClient = useQueryClient();
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(issue.title);
  const shortIdentifier = `#${issue.iid}`;
  const titleHasChanges = draft.trim().length > 0 && draft.trim() !== issue.title;
  const mutation = useMutation({
    mutationFn: (title: string) => updateIssueTitle(issue.id, title),
    onSuccess: ({ issue: updatedIssue }) => {
      queryClient.setQueryData<{ issues: IssueDTO[] }>(["issues"], (previous) =>
        previous
          ? {
              ...previous,
              issues: previous.issues.map((item) => (item.id === updatedIssue.id ? updatedIssue : item))
            }
          : previous
      );
      queryClient.invalidateQueries({ queryKey: ["issues"] });
      queryClient.invalidateQueries({ queryKey: ["monitor-state"] });
      setEditing(false);
      setDraft(updatedIssue.title);
    }
  });

  useEffect(() => {
    setEditing(false);
    setDraft(issue.title);
    mutation.reset();
  }, [issue.id, issue.title]);

  function beginEditing() {
    mutation.reset();
    setDraft(issue.title);
    setEditing(true);
  }

  function cancelEditing() {
    mutation.reset();
    setDraft(issue.title);
    setEditing(false);
  }

  function commitTitle() {
    if (mutation.isPending) {
      return;
    }

    const trimmed = draft.trim();
    if (!trimmed || trimmed === issue.title) {
      cancelEditing();
      return;
    }

    mutation.mutate(trimmed);
  }

  function handleTitleKeyDown(event: ReactKeyboardEvent<HTMLInputElement>) {
    if (event.key === "Enter") {
      event.preventDefault();
      event.stopPropagation();
      commitTitle();
      return;
    }

    if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      cancelEditing();
    }
  }

  return (
    <div className={`issue-title-editor${editing ? " issue-title-editor--editing" : ""}`}>
      {editing ? (
        <>
          <Dialog.Title className="issue-detail-title issue-detail-title--hidden">{issue.title}</Dialog.Title>
          <span className="issue-title-identifier">{shortIdentifier}</span>
          <input
            autoFocus
            aria-label="Issue title"
            className="issue-title-input"
            disabled={mutation.isPending}
            size={titleInputSize(draft || issue.title)}
            value={draft}
            onBlur={commitTitle}
            onChange={(event) => setDraft(event.target.value)}
            onKeyDown={handleTitleKeyDown}
          />
          {titleHasChanges && (
            <button
              className="issue-title-confirm"
              type="button"
              aria-label="Save issue title"
              title="Save title"
              disabled={mutation.isPending}
              onMouseDown={(event) => event.preventDefault()}
              onClick={commitTitle}
            >
              <Check size={13} />
            </button>
          )}
          {mutation.isPending && <LoaderCircle className="issue-title-saving animate-spin" size={14} />}
        </>
      ) : (
        <>
          <Dialog.Title className="issue-detail-title issue-detail-title--hidden">{issue.title}</Dialog.Title>
          <button className="issue-title-display" type="button" aria-label="Edit issue title" title="Edit title" disabled={mutation.isPending} onClick={beginEditing}>
            <span className="issue-title-identifier">{shortIdentifier}</span>
            <span className="issue-detail-title">{issue.title}</span>
          </button>
          <a className="issue-title-link" href={issue.webUrl} target="_blank" rel="noreferrer" aria-label="Open issue in GitLab" title="Open in GitLab">
            <ExternalLink size={14} />
          </a>
          {mutation.isPending && <LoaderCircle className="issue-title-saving animate-spin" size={14} />}
        </>
      )}
      {mutation.isError && <div className="issue-title-error">{mutation.error.message}</div>}
    </div>
  );
}

function IssueDescriptionEditor({
  issue,
  onStartEditing,
  onFinishEditing
}: {
  issue: IssueDTO;
  onStartEditing: () => void;
  onFinishEditing: () => void;
}) {
  const queryClient = useQueryClient();
  const currentDescription = issue.description ?? "";
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(currentDescription);
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const hasDescription = currentDescription.trim().length > 0;
  const descriptionHasChanges = draft !== currentDescription;
  const mutation = useMutation({
    mutationFn: (description: string) => updateIssueDescription(issue.id, description),
    onSuccess: ({ issue: updatedIssue }) => {
      queryClient.setQueryData<{ issues: IssueDTO[] }>(["issues"], (previous) =>
        previous
          ? {
              ...previous,
              issues: previous.issues.map((item) => (item.id === updatedIssue.id ? updatedIssue : item))
            }
          : previous
      );
      queryClient.invalidateQueries({ queryKey: ["issues"] });
      queryClient.invalidateQueries({ queryKey: ["monitor-state"] });
      setEditing(false);
      setDraft(updatedIssue.description ?? "");
      onFinishEditing();
    }
  });

  useEffect(() => {
    setEditing(false);
    setDraft(currentDescription);
    mutation.reset();
  }, [issue.id, currentDescription]);

  useEffect(() => {
    if (!editing) {
      return;
    }

    const textarea = textareaRef.current;
    if (!textarea) {
      return;
    }

    const selectionPosition = textarea.value.length;
    const frame = window.requestAnimationFrame(() => {
      textarea.focus({ preventScroll: true });
      textarea.setSelectionRange(selectionPosition, selectionPosition);
    });

    return () => window.cancelAnimationFrame(frame);
  }, [editing, issue.id]);

  function beginEditing() {
    mutation.reset();
    setDraft(currentDescription);
    onStartEditing();
    setEditing(true);
  }

  function cancelEditing() {
    mutation.reset();
    setDraft(currentDescription);
    setEditing(false);
    onFinishEditing();
  }

  function commitDescription() {
    if (mutation.isPending) {
      return;
    }

    if (!descriptionHasChanges) {
      cancelEditing();
      return;
    }

    mutation.mutate(draft.trim().length > 0 ? draft : "");
  }

  function handleDescriptionKeyDown(event: ReactKeyboardEvent<HTMLTextAreaElement>) {
    if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
      event.preventDefault();
      event.stopPropagation();
      commitDescription();
      return;
    }

    if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      cancelEditing();
    }
  }

  return (
    <section className={`issue-description-section${editing ? " is-editing" : ""}`}>
      <div className="issue-description-header">
        <h3>Description</h3>
        {!editing && (
          <button
            className="issue-description-edit-button"
            type="button"
            aria-label="Edit issue description"
            title="Edit description"
            disabled={mutation.isPending}
            onClick={beginEditing}
          >
            <Pencil size={12} />
          </button>
        )}
      </div>
      {editing ? (
        <div className="issue-description-editor">
          <textarea
            ref={textareaRef}
            autoFocus
            aria-label="Issue description"
            className="issue-description-textarea"
            disabled={mutation.isPending}
            placeholder="Add description..."
            value={draft}
            onChange={(event) => setDraft(event.target.value)}
            onKeyDown={handleDescriptionKeyDown}
          />
          <div className="issue-description-editor-footer">
            <div className="issue-description-status" aria-live="polite">
              {mutation.isError ? mutation.error.message : mutation.isPending ? "Saving..." : ""}
            </div>
            <div className="issue-description-actions">
              <button className="text-button issue-description-secondary" type="button" disabled={mutation.isPending} onClick={cancelEditing}>
                Cancel
              </button>
              <button className="text-button issue-description-primary" type="button" disabled={mutation.isPending || !descriptionHasChanges} onClick={commitDescription}>
                {mutation.isPending ? <LoaderCircle className="animate-spin" size={13} /> : <Check size={13} />}
                Save
              </button>
            </div>
          </div>
        </div>
      ) : (
        <div className={`issue-description-card${hasDescription ? "" : " is-empty"}`}>{hasDescription ? renderMarkdown(currentDescription, issue) : "No description provided."}</div>
      )}
    </section>
  );
}

function keepDrawerOpenForInlineEditing(event: KeyboardEvent) {
  const target = event.target;
  if (target instanceof HTMLElement && target.closest(".issue-title-editor, .issue-description-section.is-editing, .label-editor-edit-chip, .label-editor-new-chip, .issue-note-composer, .issue-comment-menu")) {
    event.preventDefault();
  }
}

function titleInputSize(value: string) {
  return Math.min(Math.max(value.trim().length + 2, 3), 42);
}
