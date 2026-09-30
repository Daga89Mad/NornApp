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
    // CORREGIDO (la app se cerraba al abrirla): FirebaseApp.configure() lee
    // GoogleService-Info.plist de DENTRO de la app. Ese archivo está en la
    // carpeta ios/Runner pero no añadido al proyecto de Xcode, así que no se
    // incluye en la app y configure() provocaba un cierre inmediato.
    // Ahora solo se llama si el archivo está; si no, Firebase se inicia desde
    // Dart (main.dart → DefaultFirebaseOptions), como siempre.
    if FirebaseApp.app() == nil,
       Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
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
  // CORREGIDO: solo si Firebase ya está iniciado (si aún no lo está, el
  // plugin firebase_messaging recibe el mismo token a través de super y lo
  // entrega él).
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    if FirebaseApp.app() != nil {
      Messaging.messaging().apnsToken = deviceToken
    }
    super.application(
      application,
      didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
    )
  }

  // Útil para diagnosticar: si APNs falla al registrar, lo verás en los logs
  // de Xcode (típico: falta la capacidad "Push Notifications").
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