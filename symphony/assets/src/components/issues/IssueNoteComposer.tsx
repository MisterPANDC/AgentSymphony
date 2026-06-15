import type { ChangeEvent, DragEvent, FormEvent } from "react";
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
  onCancel?: () => void;
  onSuccess?: () => void;
}

export function IssueNoteComposer({ issueId, mode = "comment", noteId, initialBody = "", autoFocus = false, onCancel, onSuccess }: IssueNoteComposerProps) {
  const [body, setBody] = useState(initialBody);
  const [files, setFiles] = useState<File[]>([]);
  const [isDragging, setIsDragging] = useState(false);
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const textareaRef = useRef<HTMLTextAreaElement | null>(null);
  const queryClient = useQueryClient();
  const submittedBody = mode === "edit" ? body : body.trim();
  const hasPayload = body.trim().length > 0 || files.length > 0;
  const hasChanges = mode !== "edit" || body !== initialBody || files.length > 0;
  const submitLabel = mode === "edit" ? "Save" : mode === "reply" ? "Reply" : "Comment";
  const pendingLabel = mode === "edit" ? "Saving" : mode === "reply" ? "Replying" : "Posting";
  const placeholder = mode === "reply" ? "Write a reply..." : "Write a comment...";

  const mutation = useMutation({
    mutationFn: () => {
      if (mode === "edit") {
        if (noteId === undefined) throw new Error("Note ID is required");
        return updateIssueNote(issueId, noteId, submittedBody, files);
      }

      return createIssueNote(issueId, submittedBody, files);
    },
    onSuccess: (data) => {
      queryClient.setQueryData<{ notes: NoteDTO[] }>(["issue-notes", issueId], data);
      queryClient.invalidateQueries({ queryKey: ["monitor-state"] });
      setBody(mode === "edit" ? data.notes.find((note) => String(note.note_id) === String(noteId))?.body ?? submittedBody : "");
      setFiles([]);
      onSuccess?.();
    }
  });
  const canSubmit = hasPayload && hasChanges && !mutation.isPending;

  useEffect(() => {
    setBody(initialBody);
    setFiles([]);
    mutation.reset();
  }, [initialBody, issueId, noteId, mode]);

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
      className={`issue-note-composer is-${mode}${isDragging ? " is-dragging" : ""}`}
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
        onChange={(event) => setBody(event.target.value)}
      />
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
