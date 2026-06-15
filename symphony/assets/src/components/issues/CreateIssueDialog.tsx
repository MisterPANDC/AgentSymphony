import { useEffect, useState, type FormEvent, type KeyboardEvent, type ReactNode } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import { Check, FilePlus2, LoaderCircle, Plus, Tag, Trash2, X } from "lucide-react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { createIssue } from "../../api/issues";
import { canUserCreateIssueInStatus, userCreatableWorkflowStatuses, type IssueDTO, type WorkflowStatus } from "../../types/issue";
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
  const [labels, setLabels] = useState<string[]>([]);
  const [workflowStatus, setWorkflowStatus] = useState<WorkflowStatus>(() => creatableStatus(defaultStatus));

  const mutation = useMutation({
    mutationFn: () =>
      createIssue({
        title: title.trim(),
        description: description.trim(),
        labels: labels.join(","),
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
      setWorkflowStatus(creatableStatus(defaultStatus));
    }
  }, [defaultStatus, open]);

  function resetForm(status: WorkflowStatus) {
    setTitle("");
    setDescription("");
    setLabels([]);
    setWorkflowStatus(creatableStatus(status));
    mutation.reset();
  }

  function handleOpenChange(nextOpen: boolean) {
    setOpen(nextOpen);
    if (nextOpen) {
      mutation.reset();
      setWorkflowStatus(creatableStatus(defaultStatus));
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
              <WorkflowStatusSelect value={workflowStatus} onChange={setWorkflowStatus} menuAlign="start" statuses={userCreatableWorkflowStatuses} />
              <CreateIssueLabelEditor labels={labels} onChange={setLabels} />
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

function creatableStatus(status: WorkflowStatus): WorkflowStatus {
  return canUserCreateIssueInStatus(status) ? status : "triage";
}

function CreateIssueLabelEditor({ labels, onChange }: { labels: string[]; onChange: (labels: string[]) => void }) {
  const [editingIndex, setEditingIndex] = useState<number | null>(null);
  const [editingValue, setEditingValue] = useState("");
  const [adding, setAdding] = useState(false);
  const [newValue, setNewValue] = useState("");
  const currentLabels = normalizeCreateIssueLabels(labels);

  function resetInlineState() {
    setEditingIndex(null);
    setEditingValue("");
    setAdding(false);
    setNewValue("");
  }

  function beginEditing(index: number, label: string) {
    setAdding(false);
    setNewValue("");
    setEditingIndex(index);
    setEditingValue(label);
  }

  function beginAdding() {
    setEditingIndex(null);
    setEditingValue("");
    setAdding(true);
    setNewValue("");
  }

  function commitLabels(nextLabels: string[]) {
    onChange(normalizeCreateIssueLabels(nextLabels));
    resetInlineState();
  }

  function commitNewLabel() {
    const nextLabels = splitCreateIssueLabelInput(newValue);
    if (nextLabels.length === 0) {
      resetInlineState();
      return;
    }

    commitLabels([...currentLabels, ...nextLabels]);
  }

  function commitExistingLabel(index: number) {
    const nextLabels = [...currentLabels];
    const trimmed = editingValue.trim();

    if (trimmed) {
      nextLabels[index] = trimmed;
    } else {
      nextLabels.splice(index, 1);
    }

    commitLabels(nextLabels);
  }

  function removeLabel(index: number) {
    commitLabels(currentLabels.filter((_label, itemIndex) => itemIndex !== index));
  }

  function handleNewLabelKeyDown(event: KeyboardEvent<HTMLInputElement>) {
    if (event.key === "Enter" || event.key === ",") {
      event.preventDefault();
      event.stopPropagation();
      commitNewLabel();
      return;
    }

    if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      resetInlineState();
    }
  }

  function handleExistingLabelKeyDown(event: KeyboardEvent<HTMLInputElement>, index: number) {
    if (event.key === "Enter") {
      event.preventDefault();
      event.stopPropagation();
      commitExistingLabel(index);
      return;
    }

    if (event.key === "Escape") {
      event.preventDefault();
      event.stopPropagation();
      resetInlineState();
    }
  }

  return (
    <section className="label-editor create-issue-label-editor">
      <div className="label-editor-header">
        <h3>
          <Tag size={12} />
          Labels
        </h3>
      </div>
      <div className="label-editor-body">
        <div className="label-editor-input-shell">
          {currentLabels.map((label, index) =>
            editingIndex === index ? (
              <span key={`${label}-${index}`} className="label-editor-edit-chip">
                <input
                  autoFocus
                  aria-label={`Edit label ${index + 1}`}
                  value={editingValue}
                  placeholder="Label name"
                  size={labelInputSize(editingValue || label)}
                  onBlur={() => commitExistingLabel(index)}
                  onChange={(event) => setEditingValue(event.target.value)}
                  onKeyDown={(event) => handleExistingLabelKeyDown(event, index)}
                />
                {editingValue.trim().length > 0 && editingValue.trim() !== label && (
                  <button
                    className="label-editor-chip-confirm"
                    type="button"
                    aria-label={`Save label ${editingValue.trim()}`}
                    title="Save label"
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
                  onMouseDown={(event) => event.preventDefault()}
                  onClick={() => removeLabel(index)}
                >
                  <Trash2 size={11} />
                </button>
              </span>
            ) : (
              <span key={`${label}-${index}`} className="label-editor-value-chip">
                <button className="label-editor-chip-label" type="button" aria-label={`Edit label ${label}`} title={`Edit ${label}`} onClick={() => beginEditing(index, label)}>
                  <span>{label}</span>
                </button>
              </span>
            )
          )}
          {adding ? (
            <span className="label-editor-new-chip">
              <input
                autoFocus
                value={newValue}
                placeholder={currentLabels.length === 0 ? "Add label..." : "New label"}
                size={labelInputSize(newValue || "New label")}
                onBlur={commitNewLabel}
                onChange={(event) => setNewValue(event.target.value)}
                onKeyDown={handleNewLabelKeyDown}
              />
              <button type="button" title="Cancel new label" onMouseDown={(event) => event.preventDefault()} onClick={resetInlineState}>
                <X size={11} />
              </button>
            </span>
          ) : (
            <button className="label-editor-add-chip" type="button" aria-label="Add label" title="Add label" onClick={beginAdding}>
              <Plus size={13} />
            </button>
          )}
        </div>
      </div>
    </section>
  );
}

function splitCreateIssueLabelInput(input: string) {
  return input
    .split(",")
    .map((label) => label.trim())
    .filter(Boolean);
}

function normalizeCreateIssueLabels(labels: string[]) {
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

function labelInputSize(value: string) {
  return Math.min(Math.max(value.trim().length + 1, 9), 28);
}
