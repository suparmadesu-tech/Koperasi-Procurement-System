import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom';
import { AuthProvider, useAuth } from './auth/AuthProvider';
import Layout from './components/Layout';
import LogoutButton from './components/LogoutButton';
import RequireRole from './components/RequireRole';
import StatusScreen from './components/StatusScreen';
import { btnPrimary } from './components/ui';
import AdminArea from './pages/AdminArea';
import Belanja from './pages/Belanja';
import Daftar from './pages/Daftar';
import Katalog from './pages/Katalog';
import Login from './pages/Login';
import Pengaturan from './pages/Pengaturan';
import Riwayat from './pages/Riwayat';

function Gate() {
  const { state, retry } = useAuth();

  switch (state.status) {
    case 'loading':
      return <StatusScreen title="KPS" message="Memuat..." busy />;
    case 'config_error':
      return (
        <StatusScreen
          title="Konfigurasi belum lengkap"
          message={`Isi variabel berikut: ${state.missing.join(', ')}.`}
          alert
        />
      );
    case 'signed_out':
      return <Login />;
    case 'context_error':
      return (
        <StatusScreen title="Akun tidak dapat dibuka" message={state.message} alert>
          <button type="button" className={btnPrimary} onClick={() => void retry()}>
            Coba lagi
          </button>
          <LogoutButton />
        </StatusScreen>
      );
    case 'ready':
      return (
        <Layout>
          <Routes>
            <Route path="/" element={<Navigate to="/daftar" replace />} />
            <Route path="/katalog" element={<Katalog />} />
            <Route path="/daftar" element={<Daftar />} />
            <Route path="/belanja" element={<Belanja />} />
            <Route path="/riwayat" element={<Riwayat />} />
            <Route path="/pengaturan" element={<Pengaturan />} />
            <Route
              path="/pengaturan/admin"
              element={
                <RequireRole role="admin">
                  <AdminArea />
                </RequireRole>
              }
            />
            <Route
              path="*"
              element={<p role="alert">Halaman tidak ditemukan.</p>}
            />
          </Routes>
        </Layout>
      );
  }
}

export default function App() {
  return (
    <BrowserRouter>
      <AuthProvider>
        <Gate />
      </AuthProvider>
    </BrowserRouter>
  );
}
