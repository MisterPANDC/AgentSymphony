import type { ChangeEvent, DragEvent, FormEvent, KeyboardEvent } from "react";
import { useEffect, useRef, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Check, LoaderCircle, Paperclip, SendHorizontal, X } from "lucide-react";
import { createIssueNote, updateIssueNote } from "../../api/issues";
import type { NoteDTO } from "../../types/issue";

interface IssueNoteComposerProps {
  issueId: string;
  mode?: "comment" | "reply" | "edit";
  noteId?: number | string;
  initialBody?: string;
  autoFocus?: boolean;
  queryKey?: readonly unknown[];
  createNote?: (body: string, files: File[]) => Promise<{ notes: NoteDTO[] }>;
  updateNote?: (noteId: number | string, body: string, files: File[]) => Promise<{ notes: NoteDTO[] }>;
  quickActions?: NoteQuickAction[];
  quickActionButtons?: NoteQuickAction[];
  onQuickAction?: (action: NoteQuickAction) => Promise<void>;
  onCancel?: () => void;
  onSuccess?: () => void;
}

export interface NoteQuickAction {
  command: "/ready" | "/draft" | string;
  description: string;
}

type ComposerMutationResult = { notes: NoteDTO[]; quickAction?: boolean };

export function IssueNoteComposer({
  issueId,
  mode = "comment",
  noteId,
  initialBody = "",
  autoFocus = false,
  queryKey,
  createNote = (body, files) => createIssueNote(issueId, body, files),
  updateNote = (targetNoteId, body, files) => updateIssueNote(issueId, targetNoteId, body, files),
  quickActions = [],
  quickActionButtons = [],
  onQuickAction,
  onCancel,
  onSuccess
}: IssueNoteComposerProps) {
  const [body, setBody] = useState(initialBody);
  const [files, setFiles] = useState<File[]>([]);
  const [isDragging, setIsDragging] = useState(false);
  const [quickActionMenuOpen, setQuickActionMenuOpen] = useState(false);
  const [highlightedQuickActionIndex, setHighlightedQuickActionIndex] = useState(0);
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const textareaRef = useRef<HTMLTextAreaElement | null>(null);
  const queryClient = useQueryClient();
  const submittedBody = mode === "edit" ? body : body.trim();
  const enabledQuickActions = mode === "edit" ? [] : quickActions;
  const exactQuickAction = findExactQuickAction(submittedBody, enabledQuickActions);
  const activeQuickAction = exactQuickAction && onQuickAction && files.length === 0 ? exactQuickAction : null;
  const quickActionQuery = quickActionInputQuery(body);
  const visibleQuickActions =
    quickActionQuery === null
      ? []
      : enabledQuickActions.filter((action) => action.command.slice(1).toLowerCase().startsWith(quickActionQuery));
  const hasPayload = body.trim().length > 0 || files.length > 0;
  const hasChanges = mode !== "edit" || body !== initialBody || files.length > 0;
  const submitLabel = activeQuickAction ? quickActionSubmitLabel(activeQuickAction) : mode === "edit" ? "Save" : mode === "reply" ? "Reply" : "Comment";
  const pendingLabel = activeQuickAction ? "Applying" : mode === "edit" ? "Saving" : mode === "reply" ? "Replying" : "Posting";
  const placeholder = composerPlaceholder(mode, enabledQuickActions);
  const visibleQuickActionButtons = mode === "comment" ? quickActionButtons : [];
  const notesQueryKey = queryKey ?? ["issue-notes", issueId];

  const mutation = useMutation<ComposerMutationResult>({
    mutationFn: async () => {
      if (mode === "edit") {
        if (noteId === undefined) throw new Error("Note ID is required");
        return updateNote(noteId, submittedBody, files);
      }

      const quickAction = findExactQuickAction(submittedBody, enabledQuickActions);
      if (quickAction && onQuickAction && files.length === 0) {
        const result = await createNote(quickActionBody(quickAction), []);
        await onQuickAction(quickAction);
        return {
          ...result,
          quickAction: true
        };
      }

      return createNote(submittedBody, files);
    },
    onSuccess: (data) => {
      queryClient.setQueryData<{ notes: NoteDTO[] }>(notesQueryKey, data);
      if (data.quickAction) {
        void queryClient.invalidateQueries({ queryKey: notesQueryKey });
      }
      queryClient.invalidateQueries({ queryKey: ["monitor-state"] });
      setBody(mode === "edit" ? data.notes.find((note) => String(note.note_id) === String(noteId))?.body ?? submittedBody : "");
      setFiles([]);
      setQuickActionMenuOpen(false);
      onSuccess?.();
    }
  });
  const canSubmit = hasPayload && hasChanges && !mutation.isPending;
  const showQuickActionSuggestions = quickActionMenuOpen && !exactQuickAction && visibleQuickActions.length > 0 && !mutation.isPending;

  useEffect(() => {
    setBody(initialBody);
    setFiles([]);
    setQuickActionMenuOpen(false);
    mutation.reset();
  }, [initialBody, issueId, noteId, mode]);

  useEffect(() => {
    setHighlightedQuickActionIndex(0);
  }, [quickActionQuery]);

  useEffect(() => {
    if (highlightedQuickActionIndex < visibleQuickActions.length) return;
    setHighlightedQuickActionIndex(Math.max(visibleQuickActions.length - 1, 0));
  }, [highlightedQuickActionIndex, visibleQuickActions.length]);

  useEffect(() => {
    if (!autoFocus) return;

    const frame = window.requestAnimationFrame(() => {
      const textarea = textareaRef.current;
      if (!textarea) return;

      const selectionPosition = textarea.value.length;
      textarea.focus({ preventScroll: true });
      textarea.setSelectionRange(selectionPosition, selectionPosition);
    });

    return () => window.cancelAnimationFrame(frame);
  }, [autoFocus, initialBody, issueId, mode, noteId]);

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!canSubmit) return;
    mutation.mutate();
  }

  function handleBodyChange(event: ChangeEvent<HTMLTextAreaElement>) {
    const nextBody = event.target.value;
    setBody(nextBody);
    const nextQuery = quickActionInputQuery(nextBody);
    setQuickActionMenuOpen(nextQuery !== null && !findExactQuickAction(nextBody.trim(), enabledQuickActions));
  }

  function handleTextareaFocus() {
    if (quickActionQuery !== null && !exactQuickAction) {
      setQuickActionMenuOpen(true);
    }
  }

  function handleTextareaKeyDown(event: KeyboardEvent<HTMLTextAreaElement>) {
    if (!showQuickActionSuggestions) return;

    if (event.key === "ArrowDown") {
      event.preventDefault();
      setHighlightedQuickActionIndex((index) => (index + 1) % visibleQuickActions.length);
      return;
    }

    if (event.key === "ArrowUp") {
      event.preventDefault();
      setHighlightedQuickActionIndex((index) => (index - 1 + visibleQuickActions.length) % visibleQuickActions.length);
      return;
    }

    if (event.key === "Enter" || event.key === "Tab") {
      event.preventDefault();
      selectQuickAction(visibleQuickActions[highlightedQuickActionIndex]);
      return;
    }

    if (event.key === "Escape") {
      event.preventDefault();
      setQuickActionMenuOpen(false);
    }
  }

  function selectQuickAction(action: NoteQuickAction | undefined) {
    if (!action) return;

    const nextBody = quickActionBody(action);
    setBody(nextBody);
    setQuickActionMenuOpen(false);
    window.requestAnimationFrame(() => {
      const textarea = textareaRef.current;
      if (!textarea) return;
      const selectionPosition = nextBody.length;
      textarea.focus({ preventScroll: true });
      textarea.setSelectionRange(selectionPosition, selectionPosition);
    });
  }

  function addFiles(nextFiles: FileList | File[]) {
    const incoming = Array.from(nextFiles);
    if (incoming.length === 0) return;

    setFiles((current) => {
      const seen = new Set(current.map(fileKey));
      const unique = incoming.filter((file) => {
        const key = fileKey(file);
        if (seen.has(key)) return false;
        seen.add(key);
        return true;
      });
      return [...current, ...unique];
    });
  }

  function removeFile(index: number) {
    setFiles((current) => current.filter((_file, fileIndex) => fileIndex !== index));
  }

  function handleFileChange(event: ChangeEvent<HTMLInputElement>) {
    if (event.target.files) addFiles(event.target.files);
    event.target.value = "";
  }

  function handleDragOver(event: DragEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!mutation.isPending) setIsDragging(true);
  }

  function handleDragLeave(event: DragEvent<HTMLFormElement>) {
    if (!event.currentTarget.contains(event.relatedTarget as Node | null)) {
      setIsDragging(false);
    }
  }

  function handleDrop(event: DragEvent<HTMLFormElement>) {
    event.preventDefault();
    setIsDragging(false);
    if (mutation.isPending) return;
    addFiles(event.dataTransfer.files);
  }

  return (
    <form
      className={`issue-note-composer is-${mode}${isDragging ? " is-dragging" : ""}${activeQuickAction ? " has-quick-action-preview" : ""}`}
      onSubmit={submit}
      onDragOver={handleDragOver}
      onDragLeave={handleDragLeave}
      onDrop={handleDrop}
    >
      <textarea
        ref={textareaRef}
        className="issue-note-composer-textarea"
        placeholder={placeholder}
        value={body}
        disabled={mutation.isPending}
        onChange={handleBodyChange}
        onFocus={handleTextareaFocus}
        onKeyDown={handleTextareaKeyDown}
      />
      {activeQuickAction && (
        <div className="issue-note-quick-action-inline-preview" aria-hidden="true">
          <span className="issue-note-quick-action-command">{activeQuickAction.command}</span>
          <span aria-hidden="true">·</span>
          <span className="issue-note-quick-action-description">{activeQuickAction.description}</span>
        </div>
      )}
      {showQuickActionSuggestions && (
        <div className="issue-note-quick-action-menu" role="listbox" aria-label="Comment commands">
          {visibleQuickActions.map((action, index) => (
            <button
              key={action.command}
              className={`issue-note-quick-action-option${index === highlightedQuickActionIndex ? " is-highlighted" : ""}`}
              type="button"
              role="option"
              aria-selected={index === highlightedQuickActionIndex}
              onMouseDown={(event) => {
                event.preventDefault();
                selectQuickAction(action);
              }}
            >
              <span className="issue-note-quick-action-command">{action.command}</span>
              <span className="issue-note-quick-action-description">{action.description}</span>
            </button>
          ))}
        </div>
      )}
      {files.length > 0 && (
        <div className="issue-note-attachments">
          {files.map((file, index) => (
            <span key={fileKey(file)} className="issue-note-attachment-chip">
              <span>{file.name}</span>
              <button className="dialog-close-button h-5 w-5" type="button" title="Remove attachment" disabled={mutation.isPending} onClick={() => removeFile(index)}>
                <X size={12} />
              </button>
            </span>
          ))}
        </div>
      )}
      <div className="issue-note-composer-footer">
        <div className="issue-note-composer-footer-left">
          <input ref={fileInputRef} className="hidden" type="file" multiple onChange={handleFileChange} />
          <button className="icon-button issue-note-attach-button" type="button" title="Attach files" disabled={mutation.isPending} onClick={() => fileInputRef.current?.click()}>
            <Paperclip size={14} />
          </button>
          <div className="issue-note-composer-status" aria-live="polite">{mutation.isError ? <span>{mutation.error.message}</span> : null}</div>
        </div>
        <div className="issue-note-composer-actions">
          {onCancel && (
            <button
              className="text-button issue-note-secondary-action"
              type="button"
              disabled={mutation.isPending}
              onClick={onCancel}
            >
              Cancel
            </button>
          )}
          {visibleQuickActionButtons.map((action) => (
            <button
              key={action.command}
              className={`text-button issue-note-command-action ${quickActionButtonClass(action)}`}
              type="button"
              disabled={mutation.isPending}
              onClick={() => selectQuickAction(action)}
            >
              {quickActionButtonLabel(action)}
            </button>
          ))}
          <button className="text-button" type="submit" disabled={!canSubmit}>
            {mutation.isPending ? <LoaderCircle className="animate-spin" size={14} /> : mode === "edit" ? <Check size={14} /> : <SendHorizontal size={14} />}
            {mutation.isPending ? pendingLabel : submitLabel}
          </button>
        </div>
      </div>
    </form>
  );
}

function fileKey(file: File) {
  return `${file.name}:${file.size}:${file.lastModified}`;
}

function quickActionInputQuery(body: string) {
  const trimmed = body.trimStart();
  if (!trimmed.startsWith("/")) return null;
  if (trimmed.includes("\n") || /\s/.test(trimmed.slice(1))) return null;
  return trimmed.slice(1).toLowerCase();
}

function findExactQuickAction(body: string, quickActions: NoteQuickAction[]) {
  return quickActions.find((action) => action.command.toLowerCase() === body.toLowerCase()) ?? null;
}

function quickActionSubmitLabel(action: NoteQuickAction) {
  return action.command === "/draft" ? "Set draft" : action.command === "/ready" ? "Set ready" : "Apply";
}

function quickActionButtonLabel(action: NoteQuickAction) {
  return action.command === "/ready" ? "Ready" : action.command === "/draft" ? "Draft" : action.command.slice(1);
}

function quickActionButtonClass(action: NoteQuickAction) {
  return action.command === "/ready" ? "is-ready" : action.command === "/draft" ? "is-draft" : "";
}

function composerPlaceholder(mode: "comment" | "reply" | "edit", quickActions: NoteQuickAction[]) {
  const base = mode === "reply" ? "Write a reply..." : "Write a comment...";
  if (mode !== "comment" || quickActions.length === 0) return base;

  return `${base} Type / for commands like ${quickActionHint(quickActions[0])}.`;
}

function quickActionHint(action: NoteQuickAction) {
  if (action.command === "/ready") return "mark as ready";
  if (action.command === "/draft") return "mark as draft";
  return action.description.replace(/\.$/, "").toLowerCase();
}

function quickActionBody(action: NoteQuickAction) {
  return `${action.command} `;
}
