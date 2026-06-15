import { useEffect, useRef, useState, type KeyboardEvent as ReactKeyboardEvent } from "react";
import { createPortal } from "react-dom";
import * as Dialog from "@radix-ui/react-dialog";
import { Check, CornerUpLeft, ExternalLink, Link2, LoaderCircle, Maximize2, Minimize2, MoreHorizontal, Pencil, Trash2, X } from "lucide-react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { deleteIssueNote, getIssueNotes, updateIssueDescription, updateIssueTitle } from "../../api/issues";
import type { IssueDTO, NoteDTO } from "../../types/issue";
import { IssueRelationsSummary } from "./BlockerEditor";
import { GitLabMeta } from "./GitLabMeta";
import { IssueLabelEditor } from "./IssueLabelEditor";
import { IssueNoteComposer } from "./IssueNoteComposer";
import { StatusSelect } from "./StatusSelect";
import { StatusIcon } from "./StatusIcon";

type InlineComposerState = { noteId: string; mode: "reply" | "edit" } | null;

export function IssueDetailDrawer({ issue, onClose }: { issue: IssueDTO | null; onClose: () => void }) {
  const dialogRef = useRef<HTMLDivElement | null>(null);
  const unlockDialogHeightFrameRef = useRef<number | null>(null);
  const [expanded, setExpanded] = useState(false);
  const [inlineComposer, setInlineComposer] = useState<InlineComposerState>(null);
  const [descriptionEditing, setDescriptionEditing] = useState(false);
  const [lockedDialogHeight, setLockedDialogHeight] = useState<number | null>(null);
  const { data } = useQuery({
    queryKey: ["issue-notes", issue?.id],
    queryFn: () => getIssueNotes(issue!.id),
    enabled: Boolean(issue)
  });
  const notes = data?.notes ?? [];
  const userCommentCount = notes.filter((note) => !note.system).length;

  useEffect(() => {
    clearScheduledDialogHeightUnlock();
    setExpanded(false);
    setInlineComposer(null);
    setDescriptionEditing(false);
    setLockedDialogHeight(null);
  }, [issue?.id]);

  useEffect(() => {
    return () => clearScheduledDialogHeightUnlock();
  }, []);

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
    if (!expanded) {
      const height = dialogRef.current?.getBoundingClientRect().height;
      setLockedDialogHeight(height ? Math.round(height) : null);
    }
  }

  function startInlineComposer(noteId: string, mode: "reply" | "edit") {
    lockDialogHeight();
    setInlineComposer({ noteId, mode });
  }

  function cancelInlineComposer() {
    setInlineComposer(null);
    if (!descriptionEditing) {
      unlockDialogHeightAfterLayout();
    }
  }

  function startDescriptionEditing() {
    lockDialogHeight();
    setDescriptionEditing(true);
  }

  function finishDescriptionEditing() {
    setDescriptionEditing(false);
    if (!inlineComposer) {
      unlockDialogHeightAfterLayout();
    }
  }

  function toggleExpanded() {
    clearScheduledDialogHeightUnlock();
    setLockedDialogHeight(null);
    setExpanded((value) => !value);
  }

  return (
    <Dialog.Root
      open={Boolean(issue)}
      onOpenChange={(open) => {
        if (!open) {
          clearScheduledDialogHeightUnlock();
          setExpanded(false);
          setDescriptionEditing(false);
          setLockedDialogHeight(null);
          onClose();
        }
      }}
    >
      <Dialog.Portal>
        <Dialog.Overlay className="issue-detail-overlay" />
        <Dialog.Content
          ref={dialogRef}
          className={`issue-detail-dialog${expanded ? " is-expanded" : ""}`}
          style={!expanded && lockedDialogHeight ? { height: lockedDialogHeight } : undefined}
          onEscapeKeyDown={keepDrawerOpenForInlineEditing}
        >
          {issue && (
            <>
              <Dialog.Description className="issue-detail-title--hidden">
                Issue details, description, labels, and activity for {issue.identifier}.
              </Dialog.Description>
              <div className="issue-detail-dialog-actions">
                <button
                  className="dialog-close-button"
                  type="button"
                  aria-label={expanded ? "Restore issue dialog" : "Expand issue dialog"}
                  title={expanded ? "Restore" : "Expand"}
                  onClick={toggleExpanded}
                >
                  {expanded ? <Minimize2 size={15} /> : <Maximize2 size={15} />}
                </button>
                <Dialog.Close className="dialog-close-button" title="Close">
                  <X size={15} />
                </Dialog.Close>
              </div>
              <div className="issue-detail-dialog-body">
                <div className="issue-detail-dialog-header">
                  <div className="min-w-0 flex-1">
                    <IssueTitleEditor issue={issue} />
                    <div className="mt-2 flex flex-wrap items-center gap-2">
                      <GitLabMeta issue={issue} showLink={false} />
                      <StatusSelect issue={issue} />
                      <IssueRelationsSummary issue={issue} />
                      {issue.isBlocked && (
                        <span className="status-pill blocked">
                          <StatusIcon status="blocked" size={12} />
                          blocked
                        </span>
                      )}
                    </div>
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
                    {notes.length > 0 ? (
                      notes.map((note) => (
                        <ActivityNote
                          key={note.id}
                          note={note}
                          issue={issue}
                          activeComposer={inlineComposer?.noteId === note.id ? inlineComposer.mode : null}
                          onStartReply={() => startInlineComposer(note.id, "reply")}
                          onStartEdit={() => startInlineComposer(note.id, "edit")}
                          onCancelInline={cancelInlineComposer}
                        />
                      ))
                    ) : (
                      <div className="issue-activity-empty">No activity yet.</div>
                    )}
                  </div>
                  {!inlineComposer && (
                    <div className="issue-activity-composer">
                      <IssueNoteComposer issueId={issue.id} />
                    </div>
                  )}
                </section>
              </div>
            </>
          )}
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

function ActivityNote({
  note,
  issue,
  activeComposer,
  onStartReply,
  onStartEdit,
  onCancelInline
}: {
  note: NoteDTO;
  issue: IssueDTO;
  activeComposer: "reply" | "edit" | null;
  onStartReply: () => void;
  onStartEdit: () => void;
  onCancelInline: () => void;
}) {
  const authorName = note.author?.name || note.author?.username || "GitLab";
  const authorUsername = note.author?.username ? `@${note.author.username}` : null;
  const avatarUrl = authorAvatarUrl(note.author);
  const authorProfileUrl = authorWebUrl(note.author);
  const createdAt = note.gitlab_created_at;
  const updatedAt = note.gitlab_updated_at;
  const edited = Boolean(createdAt && updatedAt && new Date(updatedAt).getTime() - new Date(createdAt).getTime() > 1000);

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
              title={`Open ${authorName} profile in GitLab`}
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
    <article className={`issue-activity-item is-comment${activeComposer ? " has-inline-composer" : ""}`} id={note.note_id ? `note_${note.note_id}` : note.id}>
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
                title={`Open ${authorName} profile in GitLab`}
              >
                {authorName}
              </a>
            ) : (
              <span className="issue-activity-author">{authorName}</span>
            )}
            {authorUsername && <span className="issue-activity-username">{authorUsername}</span>}
            <span className="issue-activity-action">commented</span>
            {createdAt && (
              <time className="issue-activity-time" dateTime={createdAt} title={formatExactDate(createdAt)}>
                {formatRelativeDate(createdAt)}
              </time>
            )}
            {edited && <span className="issue-activity-action">edited</span>}
          </div>
          <div className={`issue-activity-note-tags${activeComposer ? " is-placeholder" : ""}`}>
            {note.internal && <span className="issue-activity-pill">internal</span>}
            {activeComposer ? (
              <span className="issue-comment-actions-placeholder" aria-hidden="true" />
            ) : (
              <CommentActions note={note} issue={issue} onStartReply={onStartReply} onStartEdit={onStartEdit} onCancelInline={onCancelInline} />
            )}
          </div>
        </div>
        {activeComposer === "edit" ? (
          <div className="issue-activity-inline-composer is-edit">
            <IssueNoteComposer issueId={issue.id} mode="edit" noteId={note.note_id} initialBody={note.body} autoFocus onCancel={onCancelInline} onSuccess={onCancelInline} />
          </div>
        ) : (
          <NoteBody body={note.body} issue={issue} />
        )}
        {activeComposer === "reply" && (
          <div className="issue-activity-inline-composer is-reply">
            <IssueNoteComposer issueId={issue.id} mode="reply" autoFocus onCancel={onCancelInline} onSuccess={onCancelInline} />
          </div>
        )}
      </div>
    </article>
  );
}

function CommentActions({
  note,
  issue,
  onStartReply,
  onStartEdit,
  onCancelInline
}: {
  note: NoteDTO;
  issue: IssueDTO;
  onStartReply: () => void;
  onStartEdit: () => void;
  onCancelInline: () => void;
}) {
  const queryClient = useQueryClient();
  const [menuOpen, setMenuOpen] = useState(false);
  const [menuPosition, setMenuPosition] = useState<{ top: number; left: number } | null>(null);
  const [copyState, setCopyState] = useState<"idle" | "copied" | "failed">("idle");
  const menuButtonRef = useRef<HTMLButtonElement | null>(null);
  const commentUrl = `${issue.webUrl}#note_${note.note_id}`;
  const deleteMutation = useMutation({
    mutationFn: () => deleteIssueNote(issue.id, note.note_id),
    onSuccess: (data) => {
      queryClient.setQueryData<{ notes: NoteDTO[] }>(["issue-notes", issue.id], data);
      queryClient.invalidateQueries({ queryKey: ["monitor-state"] });
      onCancelInline();
      setMenuOpen(false);
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
    if (!window.confirm("Delete this comment?")) return;
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
      <button className="issue-comment-action-button" type="button" title="Reply to comment" aria-label="Reply to comment" disabled={deleteMutation.isPending} onClick={onStartReply}>
        <CornerUpLeft size={14} />
      </button>
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
          {body.slice(lastIndex, match.index)}
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
        {body.slice(lastIndex)}
      </span>
    );
  }

  return nodes.length > 0 ? nodes : <span className="whitespace-pre-wrap">{body}</span>;
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
        <div className={`issue-description-card${hasDescription ? "" : " is-empty"}`}>
          {hasDescription ? currentDescription : "No description provided."}
        </div>
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
