import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';

export const getSelectedColorScheme = () =>
  LocalStorage.get(LOCAL_STORAGE_KEYS.COLOR_SCHEME) || 'auto';

// Single write path for appearance ('light' | 'dark' | 'auto'). Persists the
// choice, flips body.dark via setColorTheme, and keeps html[data-theme] in
// sync (Patra CSS keys off both). Used by the command bar AND the profile
// settings Appearance section — the one canonical mechanism.
export const setAppearance = theme => {
  LocalStorage.set(LOCAL_STORAGE_KEYS.COLOR_SCHEME, theme);
  const isOSOnDarkMode = window.matchMedia(
    '(prefers-color-scheme: dark)'
  ).matches;
  setColorTheme(isOSOnDarkMode);
  document.documentElement.setAttribute(
    'data-theme',
    document.body.classList.contains('dark') ? 'dark' : 'light'
  );
};

export const setColorTheme = isOSOnDarkMode => {
  const selectedColorScheme =
    LocalStorage.get(LOCAL_STORAGE_KEYS.COLOR_SCHEME) || 'auto';
  if (
    (selectedColorScheme === 'auto' && isOSOnDarkMode) ||
    selectedColorScheme === 'dark'
  ) {
    document.body.classList.add('dark');
    document.documentElement.style.setProperty('color-scheme', 'dark');
  } else {
    document.body.classList.remove('dark');
    document.documentElement.style.setProperty('color-scheme', 'light');
  }
};
