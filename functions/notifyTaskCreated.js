// functions/notifyTaskCreated.js
//
// Cloud Function (Gen 2) — envía un push cuando se CREA una tarea/evento
// COMPARTIDO en la colección `events`. Versión JavaScript (CommonJS) para
// encajar con tu index.js actual (junto a reminderDispatcher).
//
// ── Integración (una sola línea en index.js) ────────────────────────────────
//   exports.notifyTaskCreated = require("./notifyTaskCreated").notifyTaskCreated;
//   ↑ ponla DESPUÉS de tu initializeApp() / admin.initializeApp() en index.js.
//
// No toca tu reminderDispatcher. El initializeApp() de aquí está GUARDADO: si
// tu index.js ya inicializa admin, no vuelve a inicializar.
//
// ── Requisitos de versión ───────────────────────────────────────────────────
//   • firebase-admin v10+ (API modular: require("firebase-admin/app"), etc.)
//   • firebase-functions con soporte v2 (v4.3+). Casi seguro ya lo cumples.
//   Si el deploy se queja de versiones, actualiza; pero OJO: firebase-admin 14
//   exige runtime Node 22 (engines.node en package.json), lo que afectaría
//   también a reminderDispatcher. Con tus versiones actuales no hace falta.

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { logger } = require("firebase-functions/v2");
const { getApps, initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

// Init idempotente: seguro aunque index.js ya haya llamado a initializeApp().
if (getApps().length === 0) initializeApp();

// Debe coincidir con el canal Android del cliente
// (push_notification_service.dart → _fcmChannelId = 'fc_push').
const ANDROID_CHANNEL_ID = "fc_push";

// Ajusta la región si tus otras functions usan otra. Pueden convivir funciones
// en regiones distintas sin problema.
const REGION = "europe-west1";

const notifyTaskCreated = onDocumentCreated(
  { document: "events/{eventId}", region: REGION },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const eventId = event.params.eventId;
    const data = snap.data() || {};

    // 1. Filtros: privado o sin compartir → nada que notificar.
    if (data.solo_para_mi === true) return;

    const ownerId = data.owner_id || "";
    const sharedWith = Array.isArray(data.shared_with) ? data.shared_with : [];
    const destinatarios = sharedWith.filter((uid) => uid && uid !== ownerId);
    if (destinatarios.length === 0) return;

    const db = getFirestore();

    // 2. Nombre del creador para el título (best-effort).
    let creador = data.creator || "";
    if (!creador && ownerId) {
      try {
        const perfil = await db.collection("user_profiles").doc(ownerId).get();
        creador = (perfil.data() || {}).name || "";
      } catch (_) {
        /* si no hay nombre, usamos un genérico */
      }
    }
    if (!creador) creador = "Alguien";

    const titulo = data.title || "Nueva tarea";
    const categoria = data.category || "";
    const notiTitulo = `${creador} te ha compartido una tarea`;
    const notiCuerpo = categoria ? `${titulo} · ${categoria}` : titulo;

    // 3. Enviar a cada destinatario. Best-effort: un fallo no aborta el resto.
    const resultados = await Promise.allSettled(
      destinatarios.map((uid) =>
        enviarADestinatario(db, uid, {
          titulo: notiTitulo,
          cuerpo: notiCuerpo,
          eventId,
        })
      )
    );

    const enviados = resultados.filter((r) => r.status === "fulfilled").length;
    logger.info("notifyTaskCreated", {
      eventId,
      ownerId,
      destinatarios: destinatarios.length,
      enviados,
    });
  }
);

async function enviarADestinatario(db, uid, aviso) {
  const perfilRef = db.collection("user_profiles").doc(uid);
  const perfilSnap = await perfilRef.get();
  if (!perfilSnap.exists) return;

  const perfil = perfilSnap.data() || {};
  const tokens = new Set();

  // Formato nuevo (array) + antiguo (string) para no romper installs sin migrar.
  if (Array.isArray(perfil.fcm_tokens)) {
    for (const t of perfil.fcm_tokens) {
      if (typeof t === "string" && t.trim()) tokens.add(t);
    }
  }
  const legacy = perfil.fcm_token;
  if (typeof legacy === "string" && legacy.trim()) tokens.add(legacy);

  if (tokens.size === 0) return;

  const lista = [...tokens];
  const mensaje = {
    tokens: lista,
    notification: { title: aviso.titulo, body: aviso.cuerpo },
    // El payload de datos permite al cliente navegar al evento al pulsar.
    data: { tipo: "tarea_creada", eventId: aviso.eventId },
    android: {
      priority: "high",
      notification: { channelId: ANDROID_CHANNEL_ID, sound: "default" },
    },
    apns: {
      // iOS 13+ exige apns-push-type. "alert" + prioridad 10 = banner visible.
      headers: { "apns-push-type": "alert", "apns-priority": "10" },
      payload: { aps: { sound: "default" } },
    },
  };

  const resp = await getMessaging().sendEachForMulticast(mensaje);
  if (resp.failureCount === 0) return;

  // 4. Podar tokens inválidos del perfil.
  const invalidos = [];
  resp.responses.forEach((r, i) => {
    if (r.success) return;
    const code = (r.error && r.error.code) || "";
    if (
      code === "messaging/registration-token-not-registered" ||
      code === "messaging/invalid-registration-token" ||
      code === "messaging/invalid-argument"
    ) {
      invalidos.push(lista[i]);
    } else {
      logger.warn("push falló (no se poda el token)", { uid, code });
    }
  });

  if (invalidos.length === 0) return;

  try {
    await perfilRef.update({ fcm_tokens: FieldValue.arrayRemove(...invalidos) });
    if (typeof legacy === "string" && invalidos.includes(legacy)) {
      await perfilRef.update({ fcm_token: FieldValue.delete() });
    }
  } catch (e) {
    logger.warn("no se pudieron podar tokens", { uid, e: String(e) });
  }
}

module.exports = { notifyTaskCreated };