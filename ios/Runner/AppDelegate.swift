import Flutter
import UIKit
import UserNotifications
import FirebaseCore
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Inicializa Firebase en el lado nativo (necesario para que el puente
    // APNs -> FCM funcione de forma fiable). Si ya estaba, no se repite.
    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
    }

    // Delegado de notificaciones ANTES de registrar los plugins: así
    // firebase_messaging y flutter_local_notifications pueden mostrar avisos
    // con la app abierta y recibir los toques en la notificación.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate

    GeneratedPluginRegistrant.register(with: self)

    // Registrarse en APNs. Sin esto, iOS no genera token APNs y FCM no entrega.
    application.registerForRemoteNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Entrega el token APNs a Firebase Messaging.
  // CORREGIDO: la llamada a super usaba un nombre de método que no existe
  // ("didRegisterForRemoteNotifications:"); el correcto termina en
  // "WithDeviceToken".
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(
      application,
      didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
    )
  }

  // Útil para diagnosticar: si APNs falla al registrar, lo verás en los logs
  // de Xcode (típico: falta la capacidad "Push Notifications").
  // CORREGIDO: igual que arriba, el nombre correcto termina en "WithError".
  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("APNs registro FALLÓ: \(error)")
    super.application(
      application,
      didFailToRegisterForRemoteNotificationsWithError: error
    )
  }
}