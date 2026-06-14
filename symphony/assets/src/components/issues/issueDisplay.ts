import type { IssueDTO } from "../../types/issue";

export function formatGitLabState(state: IssueDTO["gitlabState"]) {
  return state === "opened" ? "open" : state;
}
