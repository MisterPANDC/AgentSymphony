import { useEffect, useMemo, useState, type KeyboardEvent } from "react";
import { Check, LoaderCircle, Plus, Tag, Trash2, X } from "lucide-react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { updateIssueLabels } from "../../api/issues";
import type { IssueDTO } from "../../types/issue";

interface IssueLabelListProps {
  labels: string[];
  className?: string;
  limit?: number;
  emptyLabel?: string;
}

export function IssueLabelList({ labels, className = "", limit, emptyLabel }: IssueLabelListProps) {
  const normalized = normalizeLabels(labels);
  const visible = typeof limit === "number" ? normalized.slice(0, limit) : normalized;
  const overflow = typeof limit === "number" ? normalized.length - visible.length : 0;

  if (normalized.length === 0) {
    return emptyLabel ? <span className={`issue-label-empty${className ? ` ${className}` : ""}`}>{emptyLabel}</span> : null;
  }

  return (
    <span className={`issue-label-list${className ? ` ${className}` : ""}`}>
      {visible.map((label) => (
        <span key={label} className="issue-label-chip" title={label}>
          <span>{label}</span>
        </span>
      ))}
      {overflow > 0 && <span className="issue-label-more">+{overflow}</span>}
    </span>
  );
}

export function IssueLabelEditor({ issue }: { issue: IssueDTO }) {
  const queryClient = useQueryClient();
  const [editingIndex, setEditingIndex] = useState<number | null>(null);
  const [editingValue, setEditingValue] = useState("");
  const [adding, setAdding] = useState(false);
  const [newValue, setNewValue] = useState("");
  const currentLabels = useMemo(() => normalizeLabels(issue.labels), [issue.labels]);
  const currentLabelsKey = labelsKey(currentLabels);
  const mutation = useMutation({
    mutationFn: (labels: string[]) => updateIssueLabels(issue.id, labels),
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
      resetInlineState();
    }
  });

  useEffect(() => {
    resetInlineState();
    mutation.reset();
  }, [issue.id, currentLabelsKey]);

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
    const labels = splitLabelInput(newValue);
    if (labels.length === 0) {
      cancelInlineEdit();
      return;
    }

    commitLabels(normalizeLabels([...currentLabels, ...labels]));
  }

  function commitExistingLabel(index: number) {
    const nextLabels = [...currentLabels];
    const trimmed = editingValue.trim();

    if (trimmed) {
      nextLabels[index] = trimmed;
    } else {
      nextLabels.splice(index, 1);
    }

    commitLabels(normalizeLabels(nextLabels));
  }

  function removeLabel(index: number) {
    const nextLabels = currentLabels.filter((_, itemIndex) => itemIndex !== index);
    commitLabels(nextLabels);
  }

  function commitLabels(labels: string[]) {
    if (mutation.isPending) {
      return;
    }

    if (labelsKey(labels) === currentLabelsKey) {
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
      cancelInlineEdit();
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
                  aria-label={`Edit label ${index + 1}`}
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
                <button className="label-editor-chip-label" type="button" aria-label={`Edit label ${label}`} title={`Edit ${label}`} disabled={mutation.isPending} onClick={() => beginEditing(index, label)}>
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
            <button className="label-editor-add-chip" type="button" aria-label="Add label" title="Add label" disabled={mutation.isPending} onClick={beginAdding}>
              <Plus size={13} />
            </button>
          )}
        </div>
        {mutation.isError && <div className="label-editor-error">{mutation.error.message}</div>}
      </div>
    </section>
  );
}

function splitLabelInput(input: string) {
  return input
    .split(",")
    .map((label) => label.trim())
    .filter(Boolean);
}

function normalizeLabels(labels: string[]) {
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

function labelsKey(labels: string[]) {
  return labels.join("\n");
}

function labelInputSize(value: string) {
  return Math.min(Math.max(value.trim().length + 1, 9), 28);
}
