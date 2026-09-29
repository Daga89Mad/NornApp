// functions/notify_social.js
//
// Notificaciones push "sociales" de NornApp:
//
//   · notifyFriendRequest → cuando alguien te envía una solicitud de amistad.
//   · notifyDateChange    → cuando alguien mueve de día una tarea, menú o
//                           entrenamiento compartido. Le llega a cada persona
//                           que tiene que aceptar o rechazar el cambio
//                           (el dueño y el resto con quien está compartido).
//
// Usan los mismos tokens que tus funciones actuales:
//   user_profiles/{uid}.fcm_tokens (array) + fcm_token (antiguo, por si acaso)
// y el mismo canal de Android que la app: 'fc_push'.
//
// La app escribe los documentos; estas funciones se disparan solas al crearse
// (Admin SDK: no pasan por las reglas de Firestore).
//
// INTEGRACIÓN en functions/index.js (una línea, al final):
//   Object.assign(exports, require('./notify_social'));

const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const logger = require('firebase-functions/logger');
// API modular de firebase-admin (v10 en adelante; la antigua admin.firestore()
// ya no existe en las versiones recientes).
const { initializeApp, getApps } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

if (getApps().length === 0) initializeApp();

// ── Ajustes ─────────────────────────────────────────────────────────────────

// IMPORTANTE: la MISMA región que tus funciones actuales (notifyTaskCreated).
// La ves en la consola de Firebase → Functions, columna "Región".
const REGION = 'europe-west1';

// Zona horaria para escribir las fechas ("miércoles, 7 de octubre").
const TIME_ZONE = 'Europe/Madrid';

const ANDROID_CHANNEL_ID = 'fc_push';

// ── Textos ──────────────────────────────────────────────────────────────────

const TYPE_LABELS = {
  tasks: { the: 'la tarea', your: 'tu tarea' },
  menus: { the: 'el menú', your: 'tu menú' },
  trainings: { the: 'el entrenamiento', your: 'tu entrenamiento' },
};

function typeLabels(itemType) {
  return TYPE_LABELS[itemType] || TYPE_LABELS.tasks;
}

/** Timestamp de Firestore → "miércoles, 7 de octubre" en hora de España. */
function formatDay(ts) {
  if (!ts || typeof ts.toDate !== 'function') return '';
  return new Intl.DateTimeFormat('es-ES', {
    timeZone: TIME_ZONE,
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  }).format(ts.toDate());
}

/** Texto de la notificación de solicitud de amistad. */
function buildFriendRequestMessage(req) {
  const who =
    (req.from_name || '').trim() ||
    (req.from_email || '').trim() ||
    'Alguien';
  return {
    title: '👋 Nueva solicitud de amistad',
    body: `${who} quiere añadirte como amigo en NornApp.`,
  };
}

/** Texto de la notificación de cambio de día. */
function buildDateChangeMessage(change) {
  const who = (change.from_name || '').trim() || 'Alguien';
  const labels = typeLabels(change.item_type);
  const isOwner = change.to_uid && change.to_uid === change.owner_id;
  const title = (change.item_title || '').trim();
  const from = formatDay(change.old_date);
  const to = formatDay(change.new_date);
  const days = from && to ? ` del ${from} al ${to}` : '';

  if (isOwner) {
    return {
      title: `📅 ${who} ha movido ${labels.your}`,
      body:
        `${title ? `«${title}»` : 'Se ha cambiado de día'}${days}. ` +
        'Entra para aceptar o rechazar el cambio.',
    };
  }
  return {
    title: `📅 ${who} propone mover ${labels.the}`,
    body: `${title ? `«${title}»` : 'Un elemento compartido'}${days}.`,
  };
}

// ── Envío ───────────────────────────────────────────────────────────────────

/** Tokens FCM de un usuario (array nuevo + campo antiguo). */
async function tokensFor(uid) {
  const snap = await getFirestore().collection('user_profiles').doc(uid).get();
  if (!snap.exists) return [];
  const data = snap.data() || {};
  const tokens = new Set(Array.isArray(data.fcm_tokens) ? data.fcm_tokens : []);
  if (typeof data.fcm_token === 'string' && data.fcm_token) {
    tokens.add(data.fcm_token);
  }
  return [...tokens].filter((t) => typeof t === 'string' && t.length > 0);
}

const INVALID_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

/**
 * Envía la notificación a todos los dispositivos de [uid] y limpia los
 * tokens que ya no existen (app desinstalada, sesión cerrada…).
 * [collapseKey] hace que un aviso nuevo del mismo asunto sustituya al
 * anterior en vez de apilarse.
 */
async function sendToUser(uid, { title, body }, data, collapseKey) {
  const tokens = await tokensFor(uid);
  if (tokens.length === 0) {
    logger.info(`Sin tokens para ${uid}: no se envía`, { data });
    return;
  }

  const message = {
    tokens,
    notification: { title, body },
    data, // todos los valores deben ser strings
    android: {
      priority: 'high',
      notification: {
        channelId: ANDROID_CHANNEL_ID,
        ...(collapseKey ? { tag: collapseKey } : {}),
      },
    },
    apns: {
      headers: collapseKey
        ? { 'apns-collapse-id': collapseKey.slice(0, 64) }
        : {},
      payload: { aps: { sound: 'default' } },
    },
  };

  // sendEachForMulticast (admin ≥ 11.7); sendMulticast en versiones antiguas.
  const messaging = getMessaging();
  const res = await (messaging.sendEachForMulticast || messaging.sendMulticast)
    .call(messaging, message);

  const invalid = [];
  res.responses.forEach((r, i) => {
    if (!r.success && r.error && INVALID_TOKEN_CODES.has(r.error.code)) {
      invalid.push(tokens[i]);
    }
  });
  if (invalid.length > 0) {
    await getFirestore()
      .collection('user_profiles')
      .doc(uid)
      .update({ fcm_tokens: FieldValue.arrayRemove(...invalid) })
      .catch((e) => logger.warn('No se pudieron limpiar tokens', e));
  }
  logger.info(
    `Push a ${uid}: ${res.successCount} ok, ${res.failureCount} fallidos`,
    { data },
  );
}

// ── Triggers ────────────────────────────────────────────────────────────────

exports.notifyFriendRequest = onDocumentCreated(
  { document: 'friend_requests/{requestId}', region: REGION },
  async (event) => {
    const req = event.data && event.data.data();
    if (!req) return;
    if (req.status !== 'pending') return;
    if (!req.to_uid || req.to_uid === req.from_uid) return;

    await sendToUser(
      req.to_uid,
      buildFriendRequestMessage(req),
      { type: 'friend_request', request_id: event.params.requestId },
      `fr_${req.from_uid || event.params.requestId}`,
    );
  },
);

exports.notifyDateChange = onDocumentCreated(
  { document: 'date_change_requests/{changeId}', region: REGION },
  async (event) => {
    const change = event.data && event.data.data();
    if (!change) return;
    if (!change.to_uid || change.to_uid === change.from_uid) return;

    await sendToUser(
      change.to_uid,
      buildDateChangeMessage(change),
      {
        type: 'date_change',
        item_type: String(change.item_type || 'tasks'),
        item_id: String(change.item_id || ''),
      },
      `dc_${change.item_id || event.params.changeId}`,
    );
  },
);

// Solo para pruebas. No enumerable: Object.assign(exports, …) no lo copia,
// así que no llega a index.js ni al despliegue.
Object.defineProperty(module.exports, '_test', {
  value: { buildFriendRequestMessage, buildDateChangeMessage, formatDay },
  enumerable: false,
});