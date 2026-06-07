// functions/index.js
//
// Envía notificaciones push (FCM) a los UIDs que están en `shared_with`.
//
// Piezas:
//  1. reminderDispatcher  → cada minuto, dispara el push del recordatorio
//                            (notification_at / alarm_at) a los destinatarios.
//  2. onSharedEventWrite  → avisa al instante cuando te comparten un evento.
//  3. onSharedTaskWrite   → avisa al instante cuando te comparten una tarea.
//
// Modelo de datos esperado:
//  events/{id}: { owner_id, shared_with: [uid], title,
//                 has_notification, notification_at (Timestamp),
//                 has_alarm, alarm_at (Timestamp), solo_para_mi }
//  weekly_tasks/{id}: { owner_id, shared_with: [uid], title, date }
//  user_profiles/{uid}: { fcm_token }

const { setGlobalOptions } = require('firebase-functions/v2');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { logger } = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();
const messaging = admin.messaging();

// Ajusta la región a la de tu proyecto si no es us-central1.
setGlobalOptions({ region: 'us-central1', maxInstances: 10 });

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

/// Devuelve [{ uid, token }] de los destinatarios con token FCM válido.
async function getTokensForUids(uids) {
  const unique = [...new Set(uids)].filter(Boolean);
  if (unique.length === 0) return [];

  const refs = unique.map((uid) => db.collection('user_profiles').doc(uid));
  const snaps = await db.getAll(...refs);

  const result = [];
  snaps.forEach((snap) => {
    if (!snap.exists) return;
    const token = snap.get('fcm_token');
    if (typeof token === 'string' && token.length > 0) {
      result.push({ uid: snap.id, token });
    }
  });
  return result;
}

/// Envía un multicast y limpia los tokens inválidos de user_profiles.
async function sendToTokens(entries, { title, body, data }) {
  if (entries.length === 0) return { successCount: 0, failureCount: 0 };

  const tokens = entries.map((e) => e.token);
  const message = {
    tokens,
    notification: { title, body },
    data: Object.fromEntries(
      Object.entries(data || {}).map(([k, v]) => [k, String(v)])
    ),
    android: {
      priority: 'high',
      notification: {
        channelId: 'fc_push', // mismo canal que usa PushNotificationService
        sound: 'default',
      },
    },
    apns: {
      headers: {
        'apns-priority': '10',
        'apns-push-type': 'alert',
      },
      payload: {
        aps: {
          alert: { title, body },
          sound: 'default',
          'interruption-level': 'time-sensitive',
        },
      },
    },
  };

  const resp = await messaging.sendEachForMulticast(message);

  // Limpieza de tokens caducados/no registrados.
  const cleanups = [];
  resp.responses.forEach((r, i) => {
    if (r.success) return;
    const code = r.error && r.error.code;
    if (
      code === 'messaging/registration-token-not-registered' ||
      code === 'messaging/invalid-registration-token' ||
      code === 'messaging/invalid-argument'
    ) {
      const uid = entries[i].uid;
      cleanups.push(
        db
          .collection('user_profiles')
          .doc(uid)
          .update({ fcm_token: admin.firestore.FieldValue.delete() })
          .catch(() => {})
      );
    }
  });
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
  const now = admin.firestore.Timestamp.now();
  // Mira 1 hora hacia atrás por si algún run se saltó; deduplica con flags.
  const lookback = admin.firestore.Timestamp.fromMillis(
    now.toMillis() - 60 * 60 * 1000
  );

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
    (uid) => uid && uid !== owner && !beforeShared.includes(uid)
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
    (uid) => uid && uid !== owner && !beforeShared.includes(uid)
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
// UTIL
// ─────────────────────────────────────────────────────────────────────────────

function timestampsEqual(a, b) {
  const am = a && typeof a.toMillis === 'function' ? a.toMillis() : null;
  const bm = b && typeof b.toMillis === 'function' ? b.toMillis() : null;
  return am === bm;
}