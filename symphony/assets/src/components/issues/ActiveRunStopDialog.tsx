import * as Dialog from "@radix-ui/react-dialog";
import { TriangleAlert } from "lucide-react";
import type { WorkflowStatus } from "../../types/issue";
import { formatStatusLabel } from "./StatusIcon";

export function ActiveRunStopDialog({
  open,
  status,
  pending,
  onCancel,
  onConfirm
}: {
  open: boolean;
  status: WorkflowStatus | null;
  pending: boolean;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  return (
    <Dialog.Root open={open} onOpenChange={(nextOpen) => !nextOpen && onCancel()}>
      <Dialog.Portal>
        <Dialog.Overlay className="confirm-dialog-overlay" />
        <Dialog.Content className="confirm-dialog-content">
          <div className="confirm-dialog-icon">
            <TriangleAlert size={16} />
          </div>
          <div className="confirm-dialog-body">
            <Dialog.Title className="confirm-dialog-title">Stop active run?</Dialog.Title>
            <Dialog.Description className="confirm-dialog-description">
              Changing to {status ? formatStatusLabel(status) : "this status"} removes the issue from dispatch candidates and cancels the current active run.
            </Dialog.Description>
            <div className="confirm-dialog-actions">
              <Dialog.Close className="text-button" disabled={pending}>
                Cancel
              </Dialog.Close>
              <button className="text-button confirm-dialog-danger" type="button" disabled={pending} onClick={onConfirm}>
                Confirm
              </button>
            </div>
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}
