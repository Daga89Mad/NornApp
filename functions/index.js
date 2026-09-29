// functions/index.js
//
// Envía notificaciones push (FCM) de NornApp.
//
// Piezas:
//  1. reminderDispatcher  → cada minuto, dispara el push del recordatorio
//                            (notification_at / alarm_at) a los destinatarios.
//  2. onSharedEventWrite  → avisa al instante cuando te comparten un evento.
//  3. onSharedTaskWrite   → avisa al instante cuando te comparten una tarea.
//  4. notifyFriendRequest → avisa cuando alguien te envía una solicitud de
//                            amistad.                                   (NUEVO)
//  5. notifyDateChange    → avisa cuando alguien mueve de día una tarea, menú
//                            o entrenamiento compartido.                (NUEVO)
//
// Modelo de datos esperado:
//  events/{id}: { owner_id, shared_with: [uid], title,
//                 has_notification, notification_at (Timestamp),
//                 has_alarm, alarm_at (Timestamp), solo_para_mi }
//  weekly_tasks/{id}: { owner_id, shared_with: [uid], title, date }
//  friend_requests/{id}: { from_uid, from_name, from_email, to_uid, status }
//  date_change_requests/{id}: { item_id, item_type, item_title, owner_id,
//                               from_uid, from_name, to_uid,
//                               old_date, new_date }
//  user_profiles/{uid}: { fcm_tokens: [token, …], fcm_token (antiguo) }
//
// ─────────────────────────────────────────────────────────────────────────────
// BUG CORREGIDO (no llegaban notificaciones, sobre todo en iPhone):
//   La app guarda los tokens en el ARRAY 'fcm_tokens' (uno por dispositivo),
//   pero aquí solo se leía el campo antiguo 'fcm_token'. Si ese campo estaba
//   vacío (""), el usuario no recibía NADA aunque tuviera tokens válidos.
//   Ahora se leen los dos y se envía a todos los dispositivos del usuario.
//   Los tokens caducados se limpian solos del array tras el primer envío.
// ─────────────────────────────────────────────────────────────────────────────

const { setGlobalOptions } = require('firebase-functions/v2');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const {
  onDocumentWritten,
  onDocumentCreated,
} = require('firebase-functions/v2/firestore');
const { logger } = require('firebase-functions');
// API modular de firebase-admin: funciona con tu versión actual y con las
// nuevas (en las recientes ya no existe admin.firestore()/admin.messaging()).
const { initializeApp } = require('firebase-admin/app');
const {
  getFirestore,
  FieldValue,
  Timestamp,
} = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

initializeApp();
const db = getFirestore();
const messaging = getMessaging();

// Ajusta la región a la de tu proyecto si no es us-central1.
setGlobalOptions({ region: 'us-central1', maxInstances: 10 });

// Zona horaria para escribir las fechas ("miércoles, 7 de octubre").
const TIME_ZONE = 'Europe/Madrid';

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

/// Devuelve [{ uid, token, legacy }] de TODOS los dispositivos de los
/// destinatarios: el array 'fcm_tokens' y, por compatibilidad, 'fcm_token'.
async function getTokensForUids(uids) {
  const unique = [...new Set(uids)].filter(Boolean);
  if (unique.length === 0) return [];

  const refs = unique.map((uid) => db.collection('user_profiles').doc(uid));
  const snaps = await db.getAll(...refs);

  const result = [];
  snaps.forEach((snap) => {
    if (!snap.exists) return;
    const seen = new Set();
    const list = snap.get('fcm_tokens');
    if (Array.isArray(list)) {
      for (const t of list) {
        if (typeof t === 'string' && t.length > 0 && !seen.has(t)) {
          seen.add(t);
          result.push({ uid: snap.id, token: t, legacy: false });
        }
      }
    }
    const old = snap.get('fcm_token');
    if (typeof old === 'string' && old.length > 0 && !seen.has(old)) {
      result.push({ uid: snap.id, token: old, legacy: true });
    }
  });
  return result;
}

/// Solo estos errores significan "este token ya no existe".
/// ('messaging/invalid-argument' NO: también salta si el problema es el
/// mensaje, y borraría tokens buenos de todos los dispositivos.)
const DEAD_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
]);

/// Envía un multicast y limpia los tokens inválidos de user_profiles.
/// [collapseKey]: un aviso nuevo del mismo asunto sustituye al anterior.
/// [timeSensitive]: rompe el modo Concentración en iPhone (recordatorios).
async function sendToTokens(
  entries,
  { title, body, data, collapseKey, timeSensitive = true },
) {
  if (entries.length === 0) return { successCount: 0, failureCount: 0 };

  const tokens = entries.map((e) => e.token);
  const message = {
    tokens,
    notification: { title, body },
    data: Object.fromEntries(
      Object.entries(data || {}).map(([k, v]) => [k, String(v)]),
    ),
    android: {
      priority: 'high',
      notification: {
        channelId: 'fc_push', // mismo canal que usa PushNotificationService
        sound: 'default',
        ...(collapseKey ? { tag: collapseKey } : {}),
      },
    },
    apns: {
      headers: {
        'apns-priority': '10',
        'apns-push-type': 'alert',
        ...(collapseKey
          ? { 'apns-collapse-id': collapseKey.slice(0, 64) }
          : {}),
      },
      payload: {
        aps: {
          alert: { title, body },
          sound: 'default',
          'interruption-level': timeSensitive ? 'time-sensitive' : 'active',
        },
      },
    },
  };

  const resp = await messaging.sendEachForMulticast(message);

  // Limpieza de tokens caducados/no registrados (agrupada por usuario).
  const deadByUid = new Map();
  resp.responses.forEach((r, i) => {
    if (r.success) return;
    const code = r.error && r.error.code;
    if (!DEAD_TOKEN_CODES.has(code)) {
      logger.warn(`FCM fallo (${code}) para ${entries[i].uid}`);
      return;
    }
    const e = entries[i];
    if (!deadByUid.has(e.uid)) deadByUid.set(e.uid, { list: [], legacy: false });
    const d = deadByUid.get(e.uid);
    if (e.legacy) d.legacy = true;
    else d.list.push(e.token);
  });

  const cleanups = [];
  for (const [uid, d] of deadByUid) {
    const update = {};
    if (d.list.length > 0) update.fcm_tokens = FieldValue.arrayRemove(...d.list);
    if (d.legacy) update.fcm_token = FieldValue.delete();
    cleanups.push(
      db.collection('user_profiles').doc(uid).update(update).catch(() => {}),
    );
  }
  await Promise.all(cleanups);

  logger.info(`FCM enviado: ok=${resp.successCount} fail=${resp.failureCount}`);
  return resp;
}

/// Destinatarios reales = shared_with menos el propietario.
function recipientsOf(data) {
  const owner = data.owner_id || '';
  const shared = Array.isArray(data.shared_with) ? data.shared_with : [];
  return shared.filter((uid) => uid && uid !== owner);
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. DISPATCHER PROGRAMADO — recordatorios al destinatario (app cerrada incluida)
// ─────────────────────────────────────────────────────────────────────────────

exports.reminderDispatcher = onSchedule('every 1 minutes', async () => {
  const now = Timestamp.now();
  // Mira 1 hora hacia atrás por si algún run se saltó; deduplica con flags.
  const lookback = Timestamp.fromMillis(now.toMillis() - 60 * 60 * 1000);

  await dispatchDue('notification_at', 'has_notification', 'notif_pushed', {
    now,
    lookback,
    bodyPrefix: 'Recordatorio',
  });

  await dispatchDue('alarm_at', 'has_alarm', 'alarm_pushed', {
    now,
    lookback,
    bodyPrefix: 'Alarma',
  });
});

async function dispatchDue(timeField, flagField, pushedField, opts) {
  const { now, lookback, bodyPrefix } = opts;

  // Consulta por rango sobre un solo campo → no necesita índice compuesto.
  const snap = await db
    .collection('events')
    .where(timeField, '>', lookback)
    .where(timeField, '<=', now)
    .get();

  if (snap.empty) return;

  for (const doc of snap.docs) {
    const data = doc.data();
    if (data[flagField] !== true) continue; // recordatorio desactivado
    if (data[pushedField] === true) continue; // ya enviado
    if (data.solo_para_mi === true) continue; // privado del dueño

    const recipients = recipientsOf(data);
    if (recipients.length === 0) {
      await doc.ref.update({ [pushedField]: true });
      continue;
    }

    try {
      const entries = await getTokensForUids(recipients);
      if (entries.length > 0) {
        await sendToTokens(entries, {
          title: data.title || bodyPrefix,
          body: `${bodyPrefix} compartido`,
          data: { eventId: doc.id, type: 'reminder' },
        });
      }
    } catch (e) {
      logger.error(`Error enviando recordatorio ${doc.id}: ${e}`);
      continue; // no marcamos como enviado para reintentar en el próximo run
    }

    await doc.ref.update({ [pushedField]: true });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. AVISO INMEDIATO AL COMPARTIR UN EVENTO
// ─────────────────────────────────────────────────────────────────────────────

exports.onSharedEventWrite = onDocumentWritten('events/{eventId}', async (event) => {
  const before = event.data.before.exists ? event.data.before.data() : null;
  const after = event.data.after.exists ? event.data.after.data() : null;
  if (!after) return; // borrado

  const beforeShared = before && Array.isArray(before.shared_with)
    ? before.shared_with
    : [];
  const afterShared = Array.isArray(after.shared_with) ? after.shared_with : [];

  // Reabre el envío del recordatorio si el dueño cambió la hora.
  const reset = {};
  if (before && !timestampsEqual(before.notification_at, after.notification_at)) {
    reset.notif_pushed = false;
  }
  if (before && !timestampsEqual(before.alarm_at, after.alarm_at)) {
    reset.alarm_pushed = false;
  }
  if (Object.keys(reset).length > 0) {
    await event.data.after.ref.update(reset).catch(() => {});
  }

  // UIDs añadidos en este cambio (a quienes se les acaba de compartir).
  const owner = after.owner_id || '';
  const newUids = afterShared.filter(
    (uid) => uid && uid !== owner && !beforeShared.includes(uid),
  );
  if (newUids.length === 0) return;

  const entries = await getTokensForUids(newUids);
  if (entries.length === 0) return;

  await sendToTokens(entries, {
    title: 'Evento compartido',
    body: `Te han compartido: ${after.title || 'un evento'}`,
    data: { eventId: event.params.eventId, type: 'shared_event' },
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 3. AVISO INMEDIATO AL COMPARTIR UNA TAREA
// ─────────────────────────────────────────────────────────────────────────────

exports.onSharedTaskWrite = onDocumentWritten('weekly_tasks/{taskId}', async (event) => {
  const before = event.data.before.exists ? event.data.before.data() : null;
  const after = event.data.after.exists ? event.data.after.data() : null;
  if (!after) return;

  const beforeShared = before && Array.isArray(before.shared_with)
    ? before.shared_with
    : [];
  const afterShared = Array.isArray(after.shared_with) ? after.shared_with : [];

  const owner = after.owner_id || '';
  const newUids = afterShared.filter(
    (uid) => uid && uid !== owner && !beforeShared.includes(uid),
  );
  if (newUids.length === 0) return;

  const entries = await getTokensForUids(newUids);
  if (entries.length === 0) return;

  await sendToTokens(entries, {
    title: 'Tarea compartida',
    body: `Te han compartido: ${after.title || 'una tarea'}`,
    data: { taskId: event.params.taskId, type: 'shared_task' },
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// 4. SOLICITUD DE AMISTAD (NUEVO)
// ─────────────────────────────────────────────────────────────────────────────

function buildFriendRequestMessage(req) {
  const who =
    (req.from_name || '').trim() || (req.from_email || '').trim() || 'Alguien';
  return {
    title: '👋 Nueva solicitud de amistad',
    body: `${who} quiere añadirte como amigo en NornApp.`,
  };
}

exports.notifyFriendRequest = onDocumentCreated(
  'friend_requests/{requestId}',
  async (event) => {
    const req = event.data && event.data.data();
    if (!req || req.status !== 'pending') return;
    if (!req.to_uid || req.to_uid === req.from_uid) return;

    const entries = await getTokensForUids([req.to_uid]);
    if (entries.length === 0) return;

    await sendToTokens(entries, {
      ...buildFriendRequestMessage(req),
      data: { type: 'friend_request', request_id: event.params.requestId },
      collapseKey: `fr_${req.from_uid || event.params.requestId}`,
      timeSensitive: false,
    });
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// 5. CAMBIO DE DÍA DE ALGO COMPARTIDO (NUEVO)
// ─────────────────────────────────────────────────────────────────────────────
// La app crea un documento por cada persona que tiene que responder (el dueño
// y el resto con quien está compartido): a cada una le llega su aviso.

const TYPE_LABELS = {
  tasks: { the: 'la tarea', your: 'tu tarea' },
  menus: { the: 'el menú', your: 'tu menú' },
  trainings: { the: 'el entrenamiento', your: 'tu entrenamiento' },
};

/// Timestamp → "miércoles, 7 de octubre" en hora de España.
function formatDay(ts) {
  if (!ts || typeof ts.toDate !== 'function') return '';
  return new Intl.DateTimeFormat('es-ES', {
    timeZone: TIME_ZONE,
    weekday: 'long',
    day: 'numeric',
    month: 'long',
  }).format(ts.toDate());
}

function buildDateChangeMessage(change) {
  const who = (change.from_name || '').trim() || 'Alguien';
  const labels = TYPE_LABELS[change.item_type] || TYPE_LABELS.tasks;
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

exports.notifyDateChange = onDocumentCreated(
  'date_change_requests/{changeId}',
  async (event) => {
    const change = event.data && event.data.data();
    if (!change) return;
    if (!change.to_uid || change.to_uid === change.from_uid) return;

    const entries = await getTokensForUids([change.to_uid]);
    if (entries.length === 0) return;

    await sendToTokens(entries, {
      ...buildDateChangeMessage(change),
      data: {
        type: 'date_change',
        item_type: change.item_type || 'tasks',
        item_id: change.item_id || '',
      },
      collapseKey: `dc_${change.item_id || event.params.changeId}`,
      timeSensitive: false,
    });
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// UTIL
// ─────────────────────────────────────────────────────────────────────────────

function timestampsEqual(a, b) {
  const am = a && typeof a.toMillis === 'function' ? a.toMillis() : null;
  const bm = b && typeof b.toMillis === 'function' ? b.toMillis() : null;
  return am === bm;
}