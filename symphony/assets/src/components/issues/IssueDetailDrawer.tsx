import { useEffect, useState, type KeyboardEvent as ReactKeyboardEvent } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import { Check, ExternalLink, LoaderCircle, Maximize2, Minimize2, X } from "lucide-react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { getIssueNotes, updateIssueTitle } from "../../api/issues";
import type { IssueDTO, NoteDTO } from "../../types/issue";
import { IssueRelationsSummary } from "./BlockerEditor";
import { GitLabMeta } from "./GitLabMeta";
import { IssueLabelEditor } from "./IssueLabelEditor";
import { IssueNoteComposer } from "./IssueNoteComposer";
import { StatusSelect } from "./StatusSelect";
import { StatusIcon } from "./StatusIcon";

export function IssueDetailDrawer({ issue, onClose }: { issue: IssueDTO | null; onClose: () => void }) {
  const [expanded, setExpanded] = useState(false);
  const { data } = useQuery({
    queryKey: ["issue-notes", issue?.id],
    queryFn: () => getIssueNotes(issue!.id),
    enabled: Boolean(issue)
  });
  const notes = data?.notes ?? [];
  const userCommentCount = notes.filter((note) => !note.system).length;

  useEffect(() => {
    setExpanded(false);
  }, [issue?.id]);

  return (
    <Dialog.Root
      open={Boolean(issue)}
      onOpenChange={(open) => {
        if (!open) {
          setExpanded(false);
          onClose();
        }
      }}
    >
      <Dialog.Portal>
        <Dialog.Overlay className="issue-detail-overlay" />
        <Dialog.Content className={`issue-detail-dialog${expanded ? " is-expanded" : ""}`} onEscapeKeyDown={keepDrawerOpenForLabelEditing}>
          {issue && (
            <>
              <div className="issue-detail-dialog-actions">
                <button
                  className="dialog-close-button"
                  type="button"
                  aria-label={expanded ? "Restore issue dialog" : "Expand issue dialog"}
                  title={expanded ? "Restore" : "Expand"}
                  onClick={() => setExpanded((value) => !value)}
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
                <section>
                  <h3 className="mb-2 text-xs font-semibold uppercase text-[#686b73]">Description</h3>
                  <p className="whitespace-pre-wrap text-sm leading-6 text-[#2f333b]">{issue.description || "No description provided."}</p>
                </section>
                <section className="issue-activity-section">
                  <div className="issue-activity-header">
                    <h3 className="issue-activity-title">Activity</h3>
                    <span className="issue-activity-count">
                      {userCommentCount} {userCommentCount === 1 ? "comment" : "comments"}
                    </span>
                  </div>
                  <div className="issue-activity-list" aria-label="Issue activity">
                    {notes.length > 0 ? (
                      notes.map((note) => <ActivityNote key={note.id} note={note} issue={issue} />)
                    ) : (
                      <div className="issue-activity-empty">No activity yet.</div>
                    )}
                  </div>
                  <div className="issue-activity-composer">
                    <IssueNoteComposer issueId={issue.id} />
                  </div>
                </section>
              </div>
            </>
          )}
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

function ActivityNote({ note, issue }: { note: NoteDTO; issue: IssueDTO }) {
  const authorName = note.author?.name || note.author?.username || "GitLab";
  const authorUsername = note.author?.username ? `@${note.author.username}` : null;
  const avatarUrl = authorAvatarUrl(note.author);
  const authorProfileUrl = authorWebUrl(note.author);
  const createdAt = note.gitlab_created_at;

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
    <article className="issue-activity-item is-comment">
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
          </div>
          <div className="issue-activity-note-tags">
            {note.internal && <span className="issue-activity-pill">internal</span>}
          </div>
        </div>
        <NoteBody body={note.body} issue={issue} />
      </div>
    </article>
  );
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

function keepDrawerOpenForLabelEditing(event: KeyboardEvent) {
  const target = event.target;
  if (target instanceof HTMLElement && target.closest(".issue-title-editor, .label-editor-edit-chip, .label-editor-new-chip")) {
    event.preventDefault();
  }
}

function titleInputSize(value: string) {
  return Math.min(Math.max(value.trim().length + 2, 3), 42);
}
