import * as Dialog from "@radix-ui/react-dialog";
import { X } from "lucide-react";
import { useQuery } from "@tanstack/react-query";
import { getIssueNotes } from "../../api/issues";
import type { IssueDTO } from "../../types/issue";
import { BlockerEditor } from "./BlockerEditor";
import { GitLabMeta } from "./GitLabMeta";
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
        <Dialog.Content className="drawer-content">
          {issue && (
            <div className="space-y-5">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <Dialog.Title className="text-lg font-semibold leading-7 text-[#1d1d1f]">{issue.title}</Dialog.Title>
                  <div className="mt-2 flex flex-wrap items-center gap-2">
                    <GitLabMeta issue={issue} />
                    <StatusSelect issue={issue} />
                    {issue.isBlocked && (
                      <span className="status-pill blocked">
                        <StatusIcon status="blocked" size={12} />
                        blocked
                      </span>
                    )}
                  </div>
                </div>
                <Dialog.Close className="icon-button" title="Close">
                  <X size={15} />
                </Dialog.Close>
              </div>
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
                        <p className="whitespace-pre-wrap">{note.body}</p>
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
