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
    <form className="rounded-lg border border-[#dedfe4] bg-[#ffffff] shadow-sm focus-within:border-[#9ca3af] focus-within:ring-4 focus-within:ring-[#9ca3af]/15" onSubmit={submit}>
      <textarea
        className="min-h-[84px] w-full resize-y rounded-t-lg border-0 bg-transparent px-3 py-2 text-sm leading-6 text-[#2f333b] outline-none placeholder:text-[#8a8d96]"
        placeholder="Add a note..."
        value={body}
        disabled={mutation.isPending}
        onChange={(event) => setBody(event.target.value)}
      />
      <div className="flex min-h-[40px] items-center justify-between gap-3 border-t border-[#eaebef] px-2 py-1.5">
        <div className="min-w-0 text-xs text-[#686b73]">
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
