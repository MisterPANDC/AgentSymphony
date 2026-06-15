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
      className={`rounded-lg border bg-[#ffffff] shadow-sm focus-within:border-[#9ca3af] focus-within:ring-4 focus-within:ring-[#9ca3af]/15 ${
        isDragging ? "border-[#6b7280] ring-4 ring-[#9ca3af]/15" : "border-[#dedfe4]"
      }`}
      onSubmit={submit}
      onDragOver={handleDragOver}
      onDragLeave={handleDragLeave}
      onDrop={handleDrop}
    >
      <textarea
        className="min-h-[84px] w-full resize-y rounded-t-lg border-0 bg-transparent px-3 py-2 text-sm leading-6 text-[#2f333b] outline-none placeholder:text-[#8a8d96]"
        placeholder="Add a note..."
        value={body}
        disabled={mutation.isPending}
        onChange={(event) => setBody(event.target.value)}
      />
      {files.length > 0 && (
        <div className="flex flex-wrap gap-1.5 border-t border-[#eaebef] px-2 py-2">
          {files.map((file, index) => (
            <span key={fileKey(file)} className="inline-flex max-w-full items-center gap-1 rounded-md border border-[#dedfe4] bg-[#f7f8fa] px-2 py-1 text-xs text-[#3c4048]">
              <span className="truncate">{file.name}</span>
              <button className="dialog-close-button h-5 w-5" type="button" title="Remove attachment" disabled={mutation.isPending} onClick={() => removeFile(index)}>
                <X size={12} />
              </button>
            </span>
          ))}
        </div>
      )}
      <div className="flex min-h-[40px] items-center justify-between gap-3 border-t border-[#eaebef] px-2 py-1.5">
        <div className="min-w-0 text-xs text-[#686b73]">
          {mutation.isError ? <span className="text-[#b42318]">{mutation.error.message}</span> : null}
        </div>
        <div className="flex items-center gap-1.5">
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
