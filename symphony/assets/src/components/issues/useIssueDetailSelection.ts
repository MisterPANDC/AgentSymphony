import { useCallback, useMemo, useState } from "react";
import type { IssueDTO } from "../../types/issue";

export function useIssueDetailSelection(issues: IssueDTO[]) {
  const [selectedIssueId, setSelectedIssueId] = useState<string | null>(null);
  const selectedIssue = useMemo(() => issues.find((issue) => issue.id === selectedIssueId) ?? null, [issues, selectedIssueId]);

  const openIssue = useCallback((issue: IssueDTO) => {
    setSelectedIssueId(issue.id);
  }, []);

  const closeIssue = useCallback(() => {
    setSelectedIssueId(null);
  }, []);

  return { selectedIssue, openIssue, closeIssue };
}
