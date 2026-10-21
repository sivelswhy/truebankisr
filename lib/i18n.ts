import type { Lang } from './categories.ts';

export type { Lang };

// Error codes sent by the API; the UI turns them into sentences.
export type ErrorCode =
  | 'INVALID_PASSWORD'
  | 'CHANGE_PASSWORD'
  | 'ACCOUNT_BLOCKED'
  | 'TIMEOUT'
  | 'BROWSER'
  | 'NO_ACCOUNT'
  | 'GENERIC'
  | 'FILL_BOTH'
  | 'NOT_SIGNED_IN'
  | 'SERVER_DOWN'
  | 'UNKNOWN';

const en = {
  appName: 'True Balance',
  lede: 'See what you can really spend: your Leumi balance minus the Max charges still to come.',
  bankLeumi: 'Bank Leumi',
  max: 'Max',
  username: 'Username',
  password: 'Password',
  required: 'Required',
  showPassword: 'Show password',
  hidePassword: 'Hide password',
  leumiHint: 'The username and password you use on leumi.co.il.',
  maxHint: 'The username and password you use on max.co.il.',
  connect: 'Connect',
  connecting: 'Connecting to Leumi and Max…',
  connectingNote: 'Signing in to both sites. This can take up to a minute.',
  privacyNote: 'Your credentials are encrypted and stay on this computer. They’re only used to read your balance and card charges.',
  tryDemo: 'Try with sample data',
  loading: 'Loading…',
  demo: 'Demo',
  refresh: 'Refresh',
  couldntRefresh: 'Couldn’t refresh.',
  reallyAvailable: 'Really available',
  reallyAvailableAfter: 'Really available after Max on {date}',
  overdrawn: 'You’ll be overdrawn on the debit date unless money comes in first.',
  leumiBalance: 'Leumi balance',
  available: 'Available',
  withLater: 'With later installments already committed: {amount}.',
  foreign: '{count} foreign-currency charge(s) not included.',
  byCategory: 'By category',
  debited: 'Debited {date}',
  pending: 'Pending',
  installment: '{n} of {total}',
  updated: 'Updated {time}',
  fetching: 'Fetching from Leumi and Max…',
  pullToRefresh: 'Pull down to refresh',
  noData: 'No data yet.',
  noDataHint: 'Pull down or tap refresh to log into Leumi and Max.',
  noDataLoading: 'Logging into Leumi and Max. This can take up to a minute.',
  disconnect: 'Disconnect accounts',
  disconnectConfirm: 'Disconnect and forget credentials',
  disconnecting: 'Disconnecting…',
  exitDemo: 'Exit demo',
  cancel: 'Cancel',
  language: 'Français',
  err: {
    INVALID_PASSWORD: '{name} didn’t accept this username or password.',
    CHANGE_PASSWORD: '{name} asks you to change your password. Do it on their site, then sign in here again.',
    ACCOUNT_BLOCKED: 'Your {name} account is blocked. Contact {name}.',
    TIMEOUT: '{name} took too long to respond. Try again.',
    BROWSER: 'The built-in browser couldn’t start on this computer. Run `npx puppeteer browsers install chrome`.',
    NO_ACCOUNT: 'No {name} account with a balance was found.',
    GENERIC: 'Couldn’t reach {name}. Try again in a moment.',
    FILL_BOTH: 'Fill in both accounts.',
    NOT_SIGNED_IN: 'Not signed in.',
    SERVER_DOWN: 'Can’t reach the app server. Is it running?',
    UNKNOWN: 'Something went wrong. Try again.',
  } satisfies Record<ErrorCode, string>,
};

type Dict = typeof en;

const fr: Dict = {
  appName: 'True Balance',
  lede: 'Vois ce que tu peux vraiment dépenser : ton solde Leumi moins les dépenses Max encore à venir.',
  bankLeumi: 'Banque Leumi',
  max: 'Max',
  username: 'Identifiant',
  password: 'Mot de passe',
  required: 'Obligatoire',
  showPassword: 'Afficher le mot de passe',
  hidePassword: 'Masquer le mot de passe',
  leumiHint: 'L’identifiant et le mot de passe que tu utilises sur leumi.co.il.',
  maxHint: 'L’identifiant et le mot de passe que tu utilises sur max.co.il.',
  connect: 'Se connecter',
  connecting: 'Connexion à Leumi et Max…',
  connectingNote: 'Connexion aux deux sites. Ça peut prendre jusqu’à une minute.',
  privacyNote: 'Tes identifiants sont chiffrés et restent sur cet ordinateur. Ils servent uniquement à lire ton solde et tes dépenses carte.',
  tryDemo: 'Essayer avec des données d’exemple',
  loading: 'Chargement…',
  demo: 'Démo',
  refresh: 'Actualiser',
  couldntRefresh: 'Impossible d’actualiser.',
  reallyAvailable: 'Vraiment disponible',
  reallyAvailableAfter: 'Vraiment disponible après Max le {date}',
  overdrawn: 'Tu seras à découvert le jour du prélèvement, sauf si de l’argent arrive avant.',
  leumiBalance: 'Solde Leumi',
  available: 'Disponible',
  withLater: 'En comptant les échéances suivantes déjà engagées : {amount}.',
  foreign: '{count} dépense(s) en devise étrangère non incluse(s).',
  byCategory: 'Par catégorie',
  debited: 'Prélevé le {date}',
  pending: 'En attente',
  installment: '{n} sur {total}',
  updated: 'Mis à jour {time}',
  fetching: 'Récupération depuis Leumi et Max…',
  pullToRefresh: 'Tire vers le bas pour actualiser',
  noData: 'Pas encore de données.',
  noDataHint: 'Tire vers le bas ou touche Actualiser pour te connecter à Leumi et Max.',
  noDataLoading: 'Connexion à Leumi et Max. Ça peut prendre jusqu’à une minute.',
  disconnect: 'Déconnecter les comptes',
  disconnectConfirm: 'Déconnecter et oublier les identifiants',
  disconnecting: 'Déconnexion…',
  exitDemo: 'Quitter la démo',
  cancel: 'Annuler',
  language: 'English',
  err: {
    INVALID_PASSWORD: '{name} n’a pas accepté cet identifiant ou ce mot de passe.',
    CHANGE_PASSWORD: '{name} te demande de changer ton mot de passe. Fais-le sur leur site, puis reconnecte-toi ici.',
    ACCOUNT_BLOCKED: 'Ton compte {name} est bloqué. Contacte {name}.',
    TIMEOUT: '{name} a mis trop de temps à répondre. Réessaie.',
    BROWSER: 'Le navigateur intégré n’a pas pu démarrer sur cet ordinateur. Lance `npx puppeteer browsers install chrome`.',
    NO_ACCOUNT: 'Aucun compte {name} avec un solde n’a été trouvé.',
    GENERIC: 'Impossible de joindre {name}. Réessaie dans un instant.',
    FILL_BOTH: 'Remplis les deux comptes.',
    NOT_SIGNED_IN: 'Non connecté.',
    SERVER_DOWN: 'Impossible de joindre le serveur de l’app. Est-il lancé ?',
    UNKNOWN: 'Une erreur est survenue. Réessaie.',
  },
};

export const dictionaries: Record<Lang, Dict> = { en, fr };

export function format(template: string, params: Record<string, string | number> = {}): string {
  return template.replace(/\{(\w+)\}/g, (_, k) => String(params[k] ?? `{${k}}`));
}

export function detectLang(): Lang {
  try {
    const saved = localStorage.getItem('lang');
    if (saved === 'en' || saved === 'fr') return saved;
  } catch {}
  return typeof navigator !== 'undefined' && navigator.language.toLowerCase().startsWith('fr') ? 'fr' : 'en';
}

const locales: Record<Lang, string> = { en: 'en-IL', fr: 'fr-FR' };

export function formatters(lang: Lang) {
  const shekel = new Intl.NumberFormat(locales[lang], { style: 'currency', currency: 'ILS' });
  const rtf = new Intl.RelativeTimeFormat(lang, { numeric: 'auto' });
  return {
    // Typographic minus, and never split the sign from the amount.
    ils: (n: number) => shekel.format(n === 0 ? 0 : n).replace('-', '−'), // n === 0 also catches −0
    day: (iso: string) =>
      new Date(`${iso.slice(0, 10)}T12:00:00Z`).toLocaleDateString(locales[lang], { day: 'numeric', month: 'short' }),
    // "19 Oct, 16:03" when the bank gave the time (Leumi, and Max once processed, only give the day).
    dayTime: (iso: string) => {
      const opts = { timeZone: 'Asia/Jerusalem', day: 'numeric', month: 'short' } as const;
      const time = new Date(iso).toLocaleTimeString(locales[lang], { timeZone: 'Asia/Jerusalem', hour: '2-digit', minute: '2-digit', hour12: false });
      return /^0?0:00$/.test(time)
        ? new Date(iso).toLocaleDateString(locales[lang], opts)
        : new Date(iso).toLocaleString(locales[lang], { ...opts, hour: '2-digit', minute: '2-digit', hour12: false });
    },
    ago: (iso: string) => {
      const minutes = Math.round((new Date(iso).getTime() - Date.now()) / 60_000);
      if (Math.abs(minutes) < 60) return rtf.format(minutes, 'minute');
      const hours = Math.round(minutes / 60);
      if (Math.abs(hours) < 24) return rtf.format(hours, 'hour');
      return rtf.format(Math.round(hours / 24), 'day');
    },
  };
}
