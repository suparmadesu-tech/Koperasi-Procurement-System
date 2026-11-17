import { useEffect, useRef } from 'react';
import { btnPrimary, btnSecondary } from './ui';

type Props = {
  open: boolean;
  title: string;
  message: string;
  confirmLabel: string;
  cancelLabel: string;
  onConfirm: () => void;
  onCancel: () => void;
};

export default function ConfirmDialog(props: Props) {
  const { open, title, message, confirmLabel, cancelLabel, onConfirm, onCancel } = props;
  const ref = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    const dialog = ref.current;
    if (!dialog) return;
    if (open && !dialog.open) dialog.showModal();
    if (!open && dialog.open) dialog.close();
  }, [open]);

  return (
    <dialog
      ref={ref}
      aria-labelledby="confirm-title"
      onCancel={(e) => {
        e.preventDefault();
        onCancel();
      }}
      className="w-[calc(100%-2rem)] max-w-sm rounded-lg bg-white p-5 text-ink backdrop:bg-black/50"
    >
      <h2 id="confirm-title" className="text-lg font-semibold">
        {title}
      </h2>
      <p className="mt-2 text-base">{message}</p>
      <div className="mt-5 flex flex-col gap-3">
        <button type="button" className={btnSecondary} onClick={onCancel} autoFocus>
          {cancelLabel}
        </button>
        <button type="button" className={btnPrimary} onClick={onConfirm}>
          {confirmLabel}
        </button>
      </div>
    </dialog>
  );
}
