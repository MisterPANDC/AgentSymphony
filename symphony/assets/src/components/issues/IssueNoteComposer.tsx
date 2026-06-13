import type { FormEvent } from "react";
import { useState } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { SendHorizontal } from "lucide-react";
import { createIssueNote } from "../../api/issues";
import type { NoteDTO } from "../../types/issue";

export function IssueNoteComposer({ issueId }: { issueId: string }) {
  const [body, setBody] = useState("");
  const queryClient = useQueryClient();
  const trimmedBody = body.trim();

  const mutation = useMutation({
    mutationFn: () => createIssueNote(issueId, trimmedBody),
    onSuccess: (data) => {
      queryClient.setQueryData<{ notes: NoteDTO[] }>(["issue-notes", issueId], data);
      queryClient.invalidateQueries({ queryKey: ["monitor-state"] });
      setBody("");
    }
  });

  function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!trimmedBody || mutation.isPending) return;
    mutation.mutate();
  }

  return (
    <form className="rounded-md border border-[#d7dce3] bg-[#ffffff] shadow-sm focus-within:border-[#94a3b8]" onSubmit={submit}>
      <textarea
        className="min-h-[84px] w-full resize-y rounded-t-md border-0 bg-transparent px-3 py-2 text-sm leading-6 text-[#1f2937] outline-none placeholder:text-[#94a3b8]"
        placeholder="Add a note..."
        value={body}
        disabled={mutation.isPending}
        onChange={(event) => setBody(event.target.value)}
      />
      <div className="flex min-h-[42px] items-center justify-between gap-3 border-t border-[#e5e7eb] px-2 py-1.5">
        <div className="min-w-0 text-xs text-[#64748b]">
          {mutation.isError ? <span className="text-[#b42318]">{mutation.error.message}</span> : null}
        </div>
        <button className="text-button" type="submit" disabled={!trimmedBody || mutation.isPending}>
          <SendHorizontal size={14} />
          {mutation.isPending ? "Posting" : "Comment"}
        </button>
      </div>
    </form>
  );
}
