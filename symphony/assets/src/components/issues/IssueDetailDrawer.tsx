import * as Dialog from "@radix-ui/react-dialog";
import { X } from "lucide-react";
import { useQuery } from "@tanstack/react-query";
import { getIssueNotes } from "../../api/issues";
import type { IssueDTO } from "../../types/issue";
import { BlockerEditor } from "./BlockerEditor";
import { GitLabMeta } from "./GitLabMeta";
import { StatusSelect } from "./StatusSelect";

export function IssueDetailDrawer({ issue, onClose }: { issue: IssueDTO | null; onClose: () => void }) {
  const { data } = useQuery({
    queryKey: ["issue-notes", issue?.id],
    queryFn: () => getIssueNotes(issue!.id),
    enabled: Boolean(issue)
  });

  return (
    <Dialog.Root open={Boolean(issue)} onOpenChange={(open) => !open && onClose()}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 bg-black/10" />
        <Dialog.Content className="fixed right-0 top-0 h-screen w-full max-w-[560px] overflow-auto border-l border-[#d7dce3] bg-[#ffffff] p-4 shadow-2xl">
          {issue && (
            <div className="space-y-5">
              <div className="flex items-start justify-between gap-3">
                <div>
                  <Dialog.Title className="text-lg font-semibold">{issue.title}</Dialog.Title>
                  <div className="mt-2 flex items-center gap-2">
                    <GitLabMeta issue={issue} />
                    <StatusSelect issueId={issue.id} value={issue.workflowStatus} />
                  </div>
                </div>
                <Dialog.Close className="icon-button" title="Close">
                  <X size={15} />
                </Dialog.Close>
              </div>
              <section>
                <h3 className="mb-2 text-xs font-semibold uppercase text-[#6b7280]">Description</h3>
                <p className="whitespace-pre-wrap text-sm leading-6 text-[#1f2937]">{issue.description || "No description provided."}</p>
              </section>
              <BlockerEditor issue={issue} />
              <section>
                <h3 className="mb-2 text-xs font-semibold uppercase text-[#6b7280]">Notes</h3>
                <div className="space-y-2">
                  {(data?.notes ?? []).map((note) => (
                    <div key={note.id} className="rounded-md border border-[#e5e7eb] p-2 text-sm">
                      <div className="mb-1 text-[11px] text-[#6b7280]">{note.author?.name ?? "GitLab"}</div>
                      <p className="whitespace-pre-wrap">{note.body}</p>
                    </div>
                  ))}
                </div>
              </section>
            </div>
          )}
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
