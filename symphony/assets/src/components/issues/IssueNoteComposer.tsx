import type { ChangeEvent, DragEvent, FormEvent } from "react";
import { useRef, useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { Paperclip, SendHorizontal, X } from "lucide-react";
import { createIssueNote } from "../../api/issues";
import type { NoteDTO } from "../../types/issue";

export function IssueNoteComposer({ issueId }: { issueId: string }) {
  const [body, setBody] = useState("");
  const [files, setFiles] = useState<File[]>([]);
  const [isDragging, setIsDragging] = useState(false);
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const queryClient = useQueryClient();
  const trimmedBody = body.trim();

  const mutation = useMutation({
    mutationFn: () => createIssueNote(issueId, trimmedBody, files),
    onSuccess: (data) => {
      queryClient.setQueryData<{ notes: NoteDTO[] }>(["issue-notes", issueId], data);
      queryClient.invalidateQueries({ queryKey: ["monitor-state"] });
      setBody("");
      setFiles([]);
    }
  });
  const canSubmit = Boolean(trimmedBody || files.length > 0) && !mutation.isPending;

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
      className={`issue-note-composer${isDragging ? " is-dragging" : ""}`}
      onSubmit={submit}
      onDragOver={handleDragOver}
      onDragLeave={handleDragLeave}
      onDrop={handleDrop}
    >
      <textarea
        className="issue-note-composer-textarea"
        placeholder="Write a comment..."
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
        <div className="issue-note-composer-status">{mutation.isError ? <span>{mutation.error.message}</span> : null}</div>
        <div className="issue-note-composer-actions">
          <input ref={fileInputRef} className="hidden" type="file" multiple onChange={handleFileChange} />
          <button className="icon-button" type="button" title="Attach files" disabled={mutation.isPending} onClick={() => fileInputRef.current?.click()}>
            <Paperclip size={14} />
          </button>
          <button className="text-button" type="submit" disabled={!canSubmit}>
            <SendHorizontal size={14} />
            {mutation.isPending ? "Posting" : "Comment"}
          </button>
        </div>
      </div>
    </form>
  );
}

function fileKey(file: File) {
  return `${file.name}:${file.size}:${file.lastModified}`;
}
