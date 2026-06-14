import { useEffect, useState, type FormEvent, type ReactNode } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import { FilePlus2, LoaderCircle, Tag, X } from "lucide-react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { createIssue } from "../../api/issues";
import { type IssueDTO, type WorkflowStatus } from "../../types/issue";
import { WorkflowStatusSelect } from "./StatusSelect";

interface CreateIssueDialogProps {
  defaultStatus?: WorkflowStatus;
  trigger: ReactNode;
  onCreated?: (issue: IssueDTO) => void;
}

export function CreateIssueDialog({ defaultStatus = "triage", trigger, onCreated }: CreateIssueDialogProps) {
  const queryClient = useQueryClient();
  const [open, setOpen] = useState(false);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [labels, setLabels] = useState("");
  const [workflowStatus, setWorkflowStatus] = useState<WorkflowStatus>(defaultStatus);

  const mutation = useMutation({
    mutationFn: () =>
      createIssue({
        title: title.trim(),
        description: description.trim(),
        labels: labels.trim(),
        workflowStatus
      }),
    onSuccess: ({ issue }) => {
      queryClient.invalidateQueries({ queryKey: ["issues"] });
      queryClient.invalidateQueries({ queryKey: ["monitor-state"] });
      onCreated?.(issue);
      setOpen(false);
      resetForm(defaultStatus);
    }
  });

  useEffect(() => {
    if (!open) {
      setWorkflowStatus(defaultStatus);
    }
  }, [defaultStatus, open]);

  function resetForm(status: WorkflowStatus) {
    setTitle("");
    setDescription("");
    setLabels("");
    setWorkflowStatus(status);
    mutation.reset();
  }

  function handleOpenChange(nextOpen: boolean) {
    setOpen(nextOpen);
    if (nextOpen) {
      mutation.reset();
      setWorkflowStatus(defaultStatus);
    } else {
      resetForm(defaultStatus);
    }
  }

  function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!title.trim() || mutation.isPending) {
      return;
    }
    mutation.mutate();
  }

  return (
    <Dialog.Root open={open} onOpenChange={handleOpenChange}>
      <Dialog.Trigger asChild>{trigger}</Dialog.Trigger>
      <Dialog.Portal>
        <Dialog.Overlay className="create-issue-overlay" />
        <Dialog.Content className="create-issue-dialog">
          <form onSubmit={handleSubmit}>
            <Dialog.Title className="sr-only">New issue</Dialog.Title>
            <div className="create-issue-titlebar">
              <input
                autoFocus
                className="create-issue-title-input"
                placeholder="Untitled issue"
                value={title}
                onChange={(event) => setTitle(event.target.value)}
              />
              <Dialog.Close className="dialog-close-button" title="Close new issue">
                <X size={15} />
              </Dialog.Close>
            </div>
            <div className="create-issue-meta-row">
              <div className="create-issue-meta-control">
                <span className="create-issue-meta-label">Status</span>
                <WorkflowStatusSelect
                  value={workflowStatus}
                  onChange={setWorkflowStatus}
                  menuAlign="start"
                  shellClassName="create-issue-status-select"
                  triggerClassName="create-issue-status-trigger"
                />
              </div>
              <label className="create-issue-meta-control create-issue-label-control" htmlFor="create-issue-labels">
                <span className="create-issue-meta-label">Labels</span>
                <span className="create-issue-label-input-shell">
                  <Tag size={13} />
                  <input
                    id="create-issue-labels"
                    placeholder="frontend, bug"
                    value={labels}
                    onChange={(event) => setLabels(event.target.value)}
                  />
                </span>
              </label>
            </div>
            <div className="create-issue-body">
              <textarea
                id="create-issue-description"
                className="create-issue-textarea"
                placeholder="Add description..."
                value={description}
                onChange={(event) => setDescription(event.target.value)}
              />
              {mutation.isError && <div className="create-issue-error">{mutation.error.message}</div>}
            </div>
            <div className="create-issue-footer">
              <Dialog.Close className="text-button" type="button">
                Cancel
              </Dialog.Close>
              <button className="text-button create-issue-submit" type="submit" disabled={!title.trim() || mutation.isPending}>
                {mutation.isPending ? <LoaderCircle size={14} className="animate-spin" /> : <FilePlus2 size={14} />}
                Create issue
              </button>
            </div>
          </form>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
