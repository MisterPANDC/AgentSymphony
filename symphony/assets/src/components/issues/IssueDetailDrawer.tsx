import { useEffect, useState, type KeyboardEvent as ReactKeyboardEvent } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import { Check, ExternalLink, LoaderCircle, X } from "lucide-react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { getIssueNotes, updateIssueTitle } from "../../api/issues";
import type { IssueDTO } from "../../types/issue";
import { BlockerEditor } from "./BlockerEditor";
import { GitLabMeta } from "./GitLabMeta";
import { IssueLabelEditor } from "./IssueLabelEditor";
import { IssueNoteComposer } from "./IssueNoteComposer";
import { StatusSelect } from "./StatusSelect";
import { StatusIcon } from "./StatusIcon";

export function IssueDetailDrawer({ issue, onClose }: { issue: IssueDTO | null; onClose: () => void }) {
  const { data } = useQuery({
    queryKey: ["issue-notes", issue?.id],
    queryFn: () => getIssueNotes(issue!.id),
    enabled: Boolean(issue)
  });

  return (
    <Dialog.Root open={Boolean(issue)} onOpenChange={(open) => !open && onClose()}>
      <Dialog.Portal>
        <Dialog.Overlay className="drawer-overlay" />
        <Dialog.Content className="drawer-content" onEscapeKeyDown={keepDrawerOpenForLabelEditing}>
          {issue && (
            <div className="space-y-5">
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0 flex-1">
                  <IssueTitleEditor issue={issue} />
                  <div className="mt-2 flex flex-wrap items-center gap-2">
                    <GitLabMeta issue={issue} showLink={false} />
                    <StatusSelect issue={issue} />
                    {issue.isBlocked && (
                      <span className="status-pill blocked">
                        <StatusIcon status="blocked" size={12} />
                        blocked
                      </span>
                    )}
                  </div>
                </div>
                <Dialog.Close className="dialog-close-button" title="Close">
                  <X size={15} />
                </Dialog.Close>
              </div>
              <IssueLabelEditor issue={issue} />
              <section>
                <h3 className="mb-2 text-xs font-semibold uppercase text-[#686b73]">Description</h3>
                <p className="whitespace-pre-wrap text-sm leading-6 text-[#2f333b]">{issue.description || "No description provided."}</p>
              </section>
              <BlockerEditor issue={issue} />
              <section>
                <h3 className="mb-2 text-xs font-semibold uppercase text-[#686b73]">Notes</h3>
                <div className="space-y-3">
                  <IssueNoteComposer issueId={issue.id} />
                  <div className="space-y-2">
                    {(data?.notes ?? []).map((note) => (
                      <div key={note.id} className="issue-card text-sm">
                        <div className="mb-1 text-[11px] text-[#686b73]">{note.author?.name ?? "GitLab"}</div>
                        <NoteBody body={note.body} issueId={issue.id} />
                      </div>
                    ))}
                  </div>
                </div>
              </section>
            </div>
          )}
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

function NoteBody({ body, issueId }: { body: string; issueId: string }) {
  return <div className="break-words text-sm leading-6 text-[#2f333b]">{renderMarkdown(body, issueId)}</div>;
}

function renderMarkdown(body: string, issueId: string) {
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
    const resolvedUrl = resolveMarkdownUrl(url, issueId);
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
    <a key={`image-${key}`} className="mt-2 block w-fit max-w-full" href={url} target={external ? "_blank" : undefined} rel={external ? "noreferrer" : undefined}>
      <img className="max-h-72 max-w-full rounded-md border border-[#dedfe4] object-contain" src={url} alt={label || "attachment"} />
    </a>
  );
}

function renderLink(label: string, url: string, key: number) {
  const external = isExternalUrl(url);
  return (
    <a key={`link-${key}`} className="text-[#2563eb] underline-offset-2 hover:underline" href={url} target={external ? "_blank" : undefined} rel={external ? "noreferrer" : undefined}>
      {label || url}
    </a>
  );
}

function safeMarkdownUrl(url: string) {
  return url.startsWith("/api/issues/") || isExternalUrl(url);
}

function resolveMarkdownUrl(url: string, issueId: string) {
  const uploadMatch = url.match(/^\/uploads\/([0-9a-fA-F]{32})\/(.+)$/);
  if (!uploadMatch) return url;

  const [, secret, filename] = uploadMatch;
  return `/api/issues/${issueId}/uploads/${encodeURIComponent(secret)}/${encodeURIComponent(decodeURIComponent(filename))}`;
}

function isExternalUrl(url: string) {
  return url.startsWith("https://") || url.startsWith("http://");
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
