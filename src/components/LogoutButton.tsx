import { useState } from 'react';
import { useAuth } from '../auth/AuthProvider';
import { planLogout } from '../lib/logout-flow';
import { countPendingOps } from '../lib/pending-ops';
import ConfirmDialog from './ConfirmDialog';
import { btnSecondary } from './ui';

export default function LogoutButton() {
  const { signOut } = useAuth();
  const [busy, setBusy] = useState(false);
  const [warning, setWarning] = useState<string | null>(null);

  async function onClick() {
    setBusy(true);
    let pending: number | null;
    try {
      pending = await countPendingOps();
    } catch {
      pending = null;
    }
    const plan = planLogout(pending);
    if (plan.needsConfirm) {
      setWarning(plan.message);
      setBusy(false);
      return;
    }
    await signOut();
  }

  async function confirmed() {
    setWarning(null);
    setBusy(true);
    await signOut();
  }

  return (
    <>
      <button type="button" className={btnSecondary} onClick={onClick} disabled={busy}>
        {busy ? 'Memproses...' : 'Keluar'}
      </button>
      <ConfirmDialog
        open={warning !== null}
        title="Keluar dari KPS?"
        message={warning ?? ''}
        confirmLabel="Tetap keluar"
        cancelLabel="Batal"
        onConfirm={confirmed}
        onCancel={() => setWarning(null)}
      />
    </>
  );
}
