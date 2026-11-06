import { createClient } from '@supabase/supabase-js';
import { mountConfigurator, clearConfigurator } from '../app.js';
import { createConfiguratorAdapter } from './configurator-adapter.js';
import '../styles.css';

const root = document.querySelector('#app');
const url = import.meta.env.VITE_SUPABASE_URL;
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
const localEmailPreview = import.meta.env.DEV && import.meta.env.VITE_AUTH_EMAIL_DELIVERY === 'local';
let client;
let generation = 0;
let currentUserId = null;
let pendingEmail = '';
let loginMode = 'password';
let definingPassword = sessionStorage.getItem('exclusive-define-password') === 'yes';
let busy = false;
let resendAfter = 0;
const escapeHtml = value => String(value).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));

function shell(content) {
  root.innerHTML = `<main class="auth-screen"><section class="auth-card"><div class="auth-brand">City Park <span>EXCLUSIVE</span></div>${content}</section></main>`;
}
function showPasswordForm(message = '') {
  shell(`<h1>Defina sua senha</h1><p>Use pelo menos 10 caracteres. Você usará esta senha nos próximos acessos.</p>
    <form id="password-form"><label for="new-password">Nova senha</label><input id="new-password" type="password" autocomplete="new-password" minlength="10" required>
    <label for="confirm-password">Confirme a senha</label><input id="confirm-password" type="password" autocomplete="new-password" minlength="10" required>
    <button class="auth-primary">Salvar senha e entrar</button></form><p class="auth-message" role="status">${escapeHtml(message)}</p><button id="cancel-password" class="auth-link">Sair</button>`);
  document.querySelector('#cancel-password').onclick = signOut;
  document.querySelector('#password-form').onsubmit = async event => {
    event.preventDefault(); if (busy) return;
    const password = document.querySelector('#new-password').value;
    if (password !== document.querySelector('#confirm-password').value) {
      document.querySelector('.auth-message').textContent = 'As senhas não coincidem.'; return;
    }
    if (password.length < 10) return;
    busy = true; const button = event.submitter; button.disabled = true;
    try {
      const { error } = await client.auth.updateUser({ password }); if (error) throw error;
      definingPassword = false; sessionStorage.removeItem('exclusive-define-password');
      currentUserId = null; pendingEmail = ''; loginMode = 'password';
      const { data, error: sessionError } = await client.auth.getSession(); if(sessionError) throw sessionError;
      await openSession(data.session);
    } catch {
      document.querySelector('.auth-message').textContent = 'Não foi possível salvar a senha. Tente outra senha ou reinicie a recuperação.';
    } finally { busy = false; button.disabled = false; }
  };
}
function showLogin(message = '') {
  shell(`<h1>Seu apartamento, suas escolhas</h1><p>${loginMode === 'password' ? 'Entre com seu e-mail e senha.' : 'Primeiro acesso ou recuperação: confirme seu e-mail com um código para definir sua senha.'}</p>
    <form id="login-form"><label for="email">E-mail</label><input id="email" name="email" type="email" autocomplete="email" required maxlength="254" value="${escapeHtml(pendingEmail)}" ${pendingEmail ? 'readonly' : ''}>
    ${pendingEmail ? '<label for="code">Código recebido por e-mail</label><input id="code" name="code" inputmode="numeric" autocomplete="one-time-code" pattern="[0-9]{6}" maxlength="6" minlength="6" required autofocus>' : loginMode === 'password' ? '<label for="password">Senha</label><input id="password" type="password" autocomplete="current-password" required>' : ''}
    <button class="auth-primary" ${busy ? 'disabled' : ''}>${busy ? 'Aguarde…' : pendingEmail ? 'Verificar código' : loginMode === 'password' ? 'Entrar' : 'Receber código'}</button></form>
    ${pendingEmail ? `<button class="auth-link" id="resend" ${busy ? 'disabled' : ''}>Reenviar código</button><button class="auth-link" id="change-email" ${busy ? 'disabled' : ''}>Usar outro e-mail</button>` : ''}
    <button class="auth-link" id="login-mode" ${busy ? 'disabled' : ''}>${loginMode === 'password' ? 'Primeiro acesso / Esqueci minha senha' : 'Voltar para e-mail e senha'}</button><p class="auth-message" role="status">${escapeHtml(message)}</p>${localEmailPreview ? '<p class="auth-local-email">Ambiente de teste: os códigos chegam à <a href="http://127.0.0.1:54324" target="_blank" rel="noopener">caixa de e-mails local</a>, sem entrega à sua caixa pessoal.</p>' : ''}<small>O acesso é liberado pela equipe do Exclusive. Caso seu e-mail tenha mudado, solicite a atualização do cadastro.</small>`);
  document.querySelector('#login-form').addEventListener('submit', async event => {
    event.preventDefault();
    if (busy) return;
    const email = document.querySelector('#email').value.trim().toLowerCase();
    const token = document.querySelector('#code')?.value.trim();
    if (!pendingEmail && loginMode === 'password') {
      const password = document.querySelector('#password').value;
      busy = true; event.submitter.disabled = true;
      try { const {error} = await client.auth.signInWithPassword({email,password}); if(error) throw error; }
      catch { document.querySelector('.auth-message').textContent = 'E-mail ou senha inválidos. Se ainda não tem senha, use Primeiro acesso.'; }
      finally { busy = false; event.submitter.disabled = false; }
      return;
    }
    if (!pendingEmail) { await sendCode(email); return; }
    busy = true;
    showLogin();
    try {
      definingPassword = true;
      sessionStorage.setItem('exclusive-define-password', 'yes');
      const { error } = await client.auth.verifyOtp({ email: pendingEmail, token, type: 'recovery' });
      if (error) throw error;
    } catch {
      definingPassword = false; sessionStorage.removeItem('exclusive-define-password');
      showLogin('Código inválido ou expirado. Confira o e-mail ou solicite um novo código.');
    } finally {
      busy = false;
      if (!currentUserId && !definingPassword) showLogin(document.querySelector('.auth-message')?.textContent || '');
    }
  });
  document.querySelector('#login-mode').onclick = () => { if (busy) return; loginMode = loginMode === 'password' ? 'code' : 'password'; pendingEmail = ''; showLogin(); };
  document.querySelector('#resend')?.addEventListener('click', () => sendCode(pendingEmail));
  document.querySelector('#change-email')?.addEventListener('click', () => { pendingEmail = ''; showLogin(); });
}
async function sendCode(email) {
  if (busy) return;
  if (Date.now() < resendAfter) { showLogin('Aguarde um minuto antes de solicitar outro código.'); return; }
  busy = true;
  showLogin();
  let message;
  try {
    // Recovery works for pre-provisioned, unconfirmed accounts while public
    // signup remains disabled. The recovery endpoint hides unknown addresses.
    const { error } = await client.auth.resetPasswordForEmail(email);
    if (error) throw error;
    pendingEmail = email;
    resendAfter = Date.now() + 60000;
    message = 'Se este e-mail estiver cadastrado, você receberá um código. Confira também a caixa de spam.';
  } catch (error) {
    message = ['over_email_send_rate_limit', 'over_request_rate_limit'].includes(error?.code)
      ? 'O limite de solicitações foi atingido. Aguarde alguns minutos antes de tentar novamente.'
      : 'Não foi possível enviar o código. Tente novamente em instantes; se persistir, entre em contato com a equipe do Exclusive.';
  } finally { busy = false; showLogin(message); }
}
async function signOut() {
  definingPassword = false; sessionStorage.removeItem('exclusive-define-password'); loginMode = 'password';
  ++generation;
  currentUserId = null;
  clearConfigurator();
  pendingEmail = '';
  busy = false;
  shell('<h1>Encerrando sessão…</h1>');
  try {
    const { error } = await client.auth.signOut({ scope: 'local' });
    if (error) throw error;
    showLogin();
  } catch {
    shell('<h1>Não foi possível encerrar a sessão</h1><p>Tente novamente antes de deixar este dispositivo.</p><button id="logout-retry" class="auth-primary">Tentar novamente</button>');
    document.querySelector('#logout-retry').onclick = signOut;
  }
}
async function openSession(session) {
  const userId = session?.user?.id || null;
  if (userId && definingPassword) {
  // Preserva o formulário em eventos repetidos da mesma sessão.
  if (userId === currentUserId && document.querySelector('#password-form')) return;
  ++generation;
  currentUserId = userId;
  busy = false;
  clearConfigurator();
  showPasswordForm();
  return;
  }
  if (!userId) { definingPassword = false; sessionStorage.removeItem('exclusive-define-password'); }
  if (userId && userId === currentUserId) return; // Token refresh must not discard edits.
  const request = ++generation;
  currentUserId = userId;
  clearConfigurator();
  if (!userId) { busy = false; pendingEmail = ''; showLogin(); return; }
  shell('<h1>Carregando suas unidades…</h1>');
  try {
    const account = await client.rpc('current_account_active');
    if (request !== generation) return;
    // Compatibility with the deployed 26-version schema during staged rollout.
    if (account.error && account.error.code !== 'PGRST202') throw account.error;
    const permissionsV2 = !account.error;
    if (permissionsV2 && account.data !== true) {
      shell('<h1>Conta inativa</h1><p>Seu acesso foi desativado. Entre em contato com a equipe do Exclusive.</p><button id="logout" class="auth-primary">Sair</button>');
      document.querySelector('#logout').onclick = signOut;
      return;
    }
    const staffResult = await client.rpc('current_staff_role');
    if (request !== generation) return;
    if (staffResult.error) throw staffResult.error;
    const adapter = await createConfiguratorAdapter({
      client,
      permissionsV2,
      staffRole: staffResult.data,
      onSignOut: signOut
    });
    if (request !== generation) return;
    if (!adapter.units.length && !staffResult.data) {
      shell('<h1>Acesso em preparação</h1><p>Seu login foi reconhecido, mas ainda não há unidades liberadas para você. Entre em contato com a equipe do Exclusive.</p><button id="logout" class="auth-primary">Sair</button>');
      document.querySelector('#logout').onclick = signOut;
      return;
    }
    adapter.allowPreview = import.meta.env.DEV && import.meta.env.MODE === 'official';
    mountConfigurator(adapter);
  } catch (error) {
    if (request !== generation) return;
    console.error('Falha ao carregar unidades:', error.message);
    shell('<h1>Não foi possível carregar suas unidades</h1><p>Verifique a conexão e tente novamente.</p><button id="retry" class="auth-primary">Tentar novamente</button><button id="logout" class="auth-link">Sair</button>');
    document.querySelector('#retry').onclick = () => { currentUserId = null; openSession(session); };
    document.querySelector('#logout').onclick = signOut;
  }
}
if (!url || !key) {
  shell('<h1>Acesso em preparação</h1><p>O serviço de acesso ainda não foi configurado neste ambiente.</p>');
} else {
  shell('<h1>Verificando acesso…</h1>');
  client = createClient(url, key);
  client.auth.onAuthStateChange((_event, session) => { setTimeout(() => openSession(session), 0); });
}
