import type { IssueDTO, IssueRelationRef } from "../../types/issue";

type RelationKind = "related" | "blocks" | "blocked-by";

interface RelationChip {
  kind: RelationKind;
  label: string;
  item: IssueRelationRef;
}

export function IssueRelationsSummary({ issue }: { issue: IssueDTO }) {
  const relationChips = issueRelationChips(issue);

  if (relationChips.length === 0) {
    return null;
  }

  return (
    <div className="issue-relations-summary" aria-label="Issue relations">
      {relationChips.map(({ kind, label, item }) => (
        <span
          key={`${kind}-${item.issueId}-${item.identifier}`}
          className={`issue-relation-chip issue-relation-chip--${kind}`}
          title={`${label}: ${item.identifier} ${item.title}`}
        >
          <span className="issue-relation-kind">{label}</span>
          <span className="issue-relation-id mono">{item.identifier}</span>
          <span className="issue-relation-title">{item.title}</span>
        </span>
      ))}
    </div>
  );
}

function issueRelationChips(issue: IssueDTO): RelationChip[] {
  const related = issue.relations?.related ?? [];
  const blocks = issue.relations?.blocks ?? [];
  const blockedBy = (issue.relations?.blockedBy?.length ? issue.relations.blockedBy : issue.blockers) ?? [];

  return [
    ...related.map((item) => ({ kind: "related" as const, label: "related", item })),
    ...blocks.map((item) => ({ kind: "blocks" as const, label: "blocks", item })),
    ...blockedBy.map((item) => ({ kind: "blocked-by" as const, label: "blocked by", item }))
  ];
}
