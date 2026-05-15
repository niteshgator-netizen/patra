/** Labels shared by all API-backed games (fallback after this map = humanized field name). */
export const CREDENTIAL_FIELD_LABELS = {
  agent_id: 'Agent ID',
  secret_key: 'API Secret Key',
  api_base_url: 'API Base URL',
  app_id: 'App ID',
  app_secret: 'App Secret',
};

/** Optional per-game, per-field help under credential inputs (`${slug}:${fieldName}`). */
export const CREDENTIAL_FIELD_HELP = {
  'game_vault:agent_id': 'From Game Vault → System Settings → agentid',
  'game_vault:secret_key': 'From Game Vault → Download → API Secret Key',
  'game_vault:api_base_url': 'Usually https://apius.gamevault999.com unless your operator uses a different API host.',

  'juwa:agent_id': 'From your Juwa agent portal (ht.juwa777.com).',
  'juwa:secret_key': 'API secret from the Juwa agent portal.',
  'juwa:api_base_url': 'Usually https://ht.juwa777.com — change only if your tenant uses another API host.',

  'vegas_sweeps:agent_id': 'From your Vegas Sweeps agent / distributor panel.',
  'vegas_sweeps:secret_key': 'API secret key paired with your Agent ID.',
  'vegas_sweeps:api_base_url': 'Usually https://apius.lasvegassweeps.com — confirm with your provider if unsure.',

  'juwa_2:agent_id': 'From your Juwa 2.0 agent portal.',
  'juwa_2:secret_key': 'API secret from the Juwa 2.0 agent portal.',
  'juwa_2:api_base_url': 'Usually https://apiinterface.juwa2.xin — change only if your operator uses a different API host.',

  'juwa2:agent_id': 'From your Juwa 2.0 agent portal.',
  'juwa2:secret_key': 'API secret from the Juwa 2.0 agent portal.',
  'juwa2:api_base_url': 'Usually https://apiinterface.juwa2.xin — change only if your operator uses a different API host.',
};

/** Optional display tweaks for game cards / modal header (merged over API payload). */
export const GAME_UI_BY_SLUG = {
  vegas_sweeps: {
    name: 'Vegas Sweeps',
    logo_emoji: '🎲',
  },
  juwa_2: {
    name: 'Juwa 2',
    logo_emoji: '🐉',
  },
  juwa2: {
    name: 'Juwa 2',
    logo_emoji: '🐉',
  },
};

export function humanizeCredentialFieldName(name) {
  if (!name || typeof name !== 'string') return '';
  return name
    .split(/_+/)
    .filter(Boolean)
    .map(part => part.charAt(0).toUpperCase() + part.slice(1).toLowerCase())
    .join(' ');
}

export function labelForCredentialField(fieldName) {
  return CREDENTIAL_FIELD_LABELS[fieldName] || humanizeCredentialFieldName(fieldName);
}

export function helpForCredentialField(slug, fieldName) {
  if (!slug || !fieldName) return '';
  return CREDENTIAL_FIELD_HELP[`${slug}:${fieldName}`] || '';
}

export function inferCredentialFieldType(fieldName, explicitType) {
  if (explicitType === 'password' || explicitType === 'text') return explicitType;
  if (!fieldName) return 'text';
  if (/secret|password|token|key/i.test(fieldName) && fieldName !== 'api_base_url') {
    return 'password';
  }
  return 'text';
}

/**
 * Normalize API `required_fields` (array of strings or `{ name, type?, ... }`) into
 * `{ name, label, type, help }` for the configure modal.
 */
export function normalizeGameCredentialFields(game, { slug } = {}) {
  const raw = Array.isArray(game?.required_fields) ? game.required_fields : [];
  const gameSlug = slug || game?.slug || '';

  return raw
    .map(entry => {
      const name =
        typeof entry === 'string'
          ? entry
          : entry && (entry.name || entry.field || entry.key);
      if (!name) return null;

      const explicitType = typeof entry === 'object' && entry.type ? entry.type : null;
      const type = inferCredentialFieldType(name, explicitType);

      return {
        name,
        label: labelForCredentialField(name),
        type,
        help: helpForCredentialField(gameSlug, name),
      };
    })
    .filter(Boolean);
}

export function mergeGameUiMetadata(game) {
  if (!game || !game.slug) return game;
  const extra = GAME_UI_BY_SLUG[game.slug];
  return extra ? { ...game, ...extra } : game;
}
