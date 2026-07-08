// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'nimna';

  @override
  String get channelListEmptyHeadline => 'Aún no hay líneas.';

  @override
  String get channelListEmptyBody =>
      'Crea un código Nimna, o introduce uno que te hayan dado.';

  @override
  String get channelListStatusQuiet => 'En silencio';

  @override
  String get actionCreateCode => 'Crear un código';

  @override
  String get actionEnterCode => 'Introducir un código';

  @override
  String get chat_messageActionReply => 'Responder';

  @override
  String get chat_messageActionReact => 'Reaccionar';

  @override
  String get chat_messageActionDelete => 'Eliminar';

  @override
  String get chat_replyingToLabel => 'Respondiendo a';

  @override
  String get chat_replyCancelA11y => 'Cancelar respuesta';

  @override
  String get chat_replyTombstone => 'El mensaje ya no está disponible.';

  @override
  String get chat_replyPreviewPhoto => 'Foto';

  @override
  String get chat_replyPreviewDocument => 'Documento';

  @override
  String chat_reactionOwnA11y(String emoji) {
    return 'Has reaccionado con $emoji. Toca para quitarla.';
  }

  @override
  String chat_reactionPeerA11y(String emoji) {
    return 'Ha reaccionado con $emoji.';
  }

  @override
  String get chat_reactionPickMoreA11y => 'Elegir otro emoji';

  @override
  String get pairing_selfJoinOwnCode =>
      'Este es tu propio código Nimna — compártelo con la otra persona.';

  @override
  String get pairing_createTitle => 'Crear un código';

  @override
  String get pairing_createIntro =>
      'Un código empareja tu teléfono con otro. Compártelo como quieras — en persona es lo más seguro.';

  @override
  String get pairing_ttlLabel => 'El código funciona durante';

  @override
  String get pairing_ttlHint =>
      'Cuanto más corto, más seguro. Un solo uso, en cualquier caso.';

  @override
  String pairing_ttlHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours horas',
      one: '1 hora',
    );
    return '$_temp0';
  }

  @override
  String get pairing_offlineError =>
      'Estás sin conexión. Un código necesita que el relay esté a la escucha — inténtalo de nuevo cuando tengas conexión.';

  @override
  String get pairing_shareBriefing =>
      'Funciona una vez, caduca en 24 h — compártelo como una contraseña.';

  @override
  String get pairing_eitherFormPairs =>
      'Las palabras o el cuadro — cualquiera de los dos te empareja.';

  @override
  String get pairing_copyAction => 'Copiar';

  @override
  String get pairing_shareAction => 'Compartir…';

  @override
  String get pairing_codeCopiedToast => 'Código copiado.';

  @override
  String get pairing_shareAsText => 'Compartir el código como texto';

  @override
  String get pairing_shareQrAsImage => 'Compartir el QR como imagen';

  @override
  String get pairing_copyCode => 'Copiar código';

  @override
  String get pairing_waitingForJoin => 'Esperando a que se una…';

  @override
  String pairing_waitLifetime(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours horas',
      one: '1 hora',
    );
    return 'Tu código funciona durante $_temp0 — vuelve cuando quieras. El emparejamiento se completa cuando estéis aquí los dos.';
  }

  @override
  String get pairing_cancelCode => 'Cancelar este código';

  @override
  String get pairing_stopWaitingConfirm =>
      '¿Dejar de esperar? El código deja de funcionar.';

  @override
  String get pairing_notNow => 'Ahora no';

  @override
  String get pairing_expiredHeadline => 'Este código caducó sin usarse.';

  @override
  String get pairing_expiredBody =>
      'No se creó nada. Crea uno nuevo cuando quieras.';

  @override
  String get pairing_makeNewCode => 'Crear un código nuevo';

  @override
  String get pairing_spentBody =>
      'Eso no se completó. El código está gastado — crea uno nuevo.';

  @override
  String get settings_title => 'Ajustes';

  @override
  String get settings_rowAppLock => 'Bloqueo de la app';

  @override
  String get settings_rowAppLockOff =>
      'Desactivado — un PIN o tu cara, antes de que se muestre nada';

  @override
  String get settings_rowAppLockOn => 'Activado';

  @override
  String get settings_rowAppLockOnBiometric => 'Activado — PIN + Face ID';

  @override
  String get settings_rowNotifications => 'Notificaciones';

  @override
  String get settings_rowNotificationsCaption =>
      'Por línea, desactivadas salvo que las actives';

  @override
  String get settings_rowRelay => 'Relay';

  @override
  String get settings_rowRelayCaption => 'relay.nimna.app';

  @override
  String get settings_rowLicenses => 'Licencias';

  @override
  String get settings_rowWipeEverything => 'Borrarlo todo';

  @override
  String get settings_rowWipeEverythingCaption =>
      'Cada línea, cada mensaje — este teléfono.';

  @override
  String get lock_choosePinTitle => 'Elige un PIN';

  @override
  String get lock_choosePinCaption =>
      'Cuando está bloqueada, la pantalla solo muestra el símbolo y este teclado. Nada más — ni siquiera cuántas líneas tienes.';

  @override
  String get lock_confirmPinTitle => 'Introdúcelo otra vez';

  @override
  String get lock_confirmPinMismatch => 'No coinciden — empieza de nuevo.';

  @override
  String get lock_actionNext => 'Siguiente';

  @override
  String get lock_enterPinTitle => 'Introduce tu PIN';

  @override
  String get lock_actionTurnOff => 'Desactivar';

  @override
  String get lock_biometricToggleLabel => 'Desbloquear con Face ID';

  @override
  String get lock_biometricToggleCaption =>
      'Recomendado. Si falla, usa tu PIN.';

  @override
  String get lock_noRecoveryCaption =>
      'No hay forma de recuperar un PIN olvidado — no hay ninguna cuenta que demuestre que eres tú. Olvidarlo significa reinstalar, lo que borra las líneas de este teléfono.';

  @override
  String get lock_biometricPromptReason => 'Desbloquea tus líneas.';

  @override
  String get lock_keypadDeleteA11y => 'Borrar';

  @override
  String get wipe_fullTitle => '¿Borrarlo todo?';

  @override
  String get wipe_fullTitleEmphasis => 'todo';

  @override
  String get wipe_fullBody =>
      'Las claves y los mensajes se destruyen en este teléfono. No hay copia de seguridad en ningún sitio, por diseño — nada puede recuperarlos.';

  @override
  String get wipe_holdToWipe => 'Mantén pulsado para borrar';

  @override
  String get wipe_fullHoldCaption =>
      'Mantén pulsado 2½ segundos. Suelta para cancelar.';

  @override
  String get wipe_actionKeep => 'Conservar';

  @override
  String get wipe_channelTitle => '¿Borrar esta línea?';

  @override
  String get wipe_channelBody =>
      'Las claves y los mensajes de esta línea se destruyen en este teléfono. Nada puede recuperarlos.';

  @override
  String get wipe_channelPeerNote =>
      'Su teléfono conserva su lado a menos que también lo borre.';

  @override
  String get wipe_channelHoldCaption =>
      'Mantén pulsado 1,5 segundos. Suelta para conservarlo todo.';

  @override
  String get wipe_channelWipedToast => 'Línea borrada.';

  @override
  String get pairing_joinTitle => 'Introducir un código';

  @override
  String get pairing_joinIntro =>
      'Los códigos vienen de la otra persona. Cada uno funciona una sola vez.';

  @override
  String get pairing_joinPaste => 'Pegar';

  @override
  String get pairing_joinScan => 'Escanear';

  @override
  String get pairing_joinUpload => 'Subir';

  @override
  String get pairing_joinAction => 'Unirse';

  @override
  String get pairing_joinOffline =>
      'Estás sin conexión. Para unirte necesitas conexión.';

  @override
  String get pairing_joinScanTitle => 'Escanea su código';

  @override
  String get pairing_joinScanCaption =>
      'Apunta con la cámara al código de su pantalla.';

  @override
  String get pairing_joinScanEnterInstead => 'Introducirlo en su lugar';

  @override
  String get pairing_joinCameraDenied =>
      'Sin acceso a la cámara — escribe el código a mano.';

  @override
  String get pairing_joinNoQrInFile => 'No hay ningún código en ese archivo.';

  @override
  String get pairing_joinFoundThem => 'Aquí están.';

  @override
  String get pairing_joinSettingUp => 'Preparando la línea…';

  @override
  String get pairing_joinCodeSpentNote =>
      'El código ha cumplido su función. No volverá a funcionar para nadie.';

  @override
  String get pairing_joinSpentBody =>
      'Eso no se completó. El código está gastado — pídele que cree uno nuevo.';

  @override
  String get pairing_noMatchError =>
      'Ese código no coincide con nada. Los códigos caducan — pídele que cree uno nuevo.';

  @override
  String get pairing_clearAction => 'Borrar';

  @override
  String get pairing_verifyTitle => 'Llama a la otra persona y compara';

  @override
  String get pairing_verifyBody =>
      'Léele estas tres palabras a la otra persona. Si coinciden, la línea es solo para los dos.';

  @override
  String get pairing_verifyMatch => 'Coinciden';

  @override
  String get pairing_verifyMismatch => 'No coinciden';

  @override
  String get pairing_mismatchTitle => 'Las palabras no coincidieron.';

  @override
  String get pairing_mismatchBody =>
      'Eso puede significar que alguien se interpuso entre los dos durante el emparejamiento. Este emparejamiento se ha descartado — no se ha guardado nada.';

  @override
  String get pairing_mismatchShareSafer =>
      'Crea un código nuevo y compártelo por un medio más seguro. En persona es lo más seguro.';

  @override
  String get pairing_readyTitle => 'La línea es tuya.';

  @override
  String get pairing_nameLineLabel => 'Ponle nombre a esta línea';

  @override
  String get pairing_nameLineCaption =>
      'Las etiquetas viven solo en este teléfono. Nunca se envían a ningún sitio.';

  @override
  String get pairing_doneAction => 'Hecho';

  @override
  String get pairing_goBack => 'Volver';

  @override
  String get billing_headline => 'Uno de los dos compra la línea.';

  @override
  String get billing_subhead => 'El otro nunca paga.';

  @override
  String get billing_pointSubscriptionTitle => 'Una suscripción al año.';

  @override
  String get billing_pointSubscriptionCaption =>
      'Tantas líneas como quieras crear.';

  @override
  String get billing_pointPermanenceTitle => 'Cada línea es tuya para siempre.';

  @override
  String get billing_pointPermanenceCaption =>
      'Si caduca, todo lo que hayas creado sigue funcionando — solo esperan las líneas nuevas.';

  @override
  String get billing_pointNoAccountTitle => 'Sin cuenta.';

  @override
  String get billing_pointNoAccountCaption =>
      'El recibo queda entre tú y la tienda.';

  @override
  String get billing_pointJoiningFreeTitle => 'Unirse siempre es gratis.';

  @override
  String get billing_pointJoiningFreeCaption =>
      'La persona a la que invitas nunca ve esta pantalla.';

  @override
  String billing_ctaStart(String price) {
    return '$price — empezar';
  }

  @override
  String get billing_restore => 'Restaurar';

  @override
  String get billing_noIdentityFootnote => 'Nunca sabemos quién eres.';

  @override
  String get billing_restoreChecking => 'Comprobando con la tienda…';

  @override
  String get billing_restoreSuccessToast => 'Compra restaurada.';

  @override
  String get billing_subscriptionStartedToast => 'Suscripción iniciada.';

  @override
  String get billing_restoreNothing =>
      'La tienda no tiene ninguna suscripción para esta cuenta.';

  @override
  String get billing_storeUnreachable =>
      'No se pudo contactar con la tienda. Inténtalo de nuevo en un momento.';

  @override
  String get billing_reconnectToVerify =>
      'Vuelve a conectarte para verificar tu suscripción.';

  @override
  String get billing_tryAgain => 'Reintentar';

  @override
  String billing_autoRenewDisclosure(String store) {
    return 'Una suscripción anual. Se renueva automáticamente y se cobra a tu cuenta de $store hasta que la canceles — cuando quieras, en los ajustes de tu cuenta. Las líneas que ya hayas creado siguen siendo tuyas en cualquier caso.';
  }

  @override
  String get billing_termsLabel => 'Términos de uso';

  @override
  String get billing_privacyLabel => 'Política de privacidad';

  @override
  String get session_lineOnline => 'En la línea';

  @override
  String get session_lineOffline => 'Fuera de la línea';

  @override
  String get session_lineLost => 'Se cortó la línea.';

  @override
  String get session_lineDropped => 'Se cortó la línea. Intentando reconectar…';

  @override
  String get session_lineRecovered => 'Ya estáis aquí los dos.';

  @override
  String get session_peerHungUp => 'Ha colgado.';

  @override
  String get session_youHungUp => 'Has colgado.';

  @override
  String get chat_hangUp => 'Colgar';

  @override
  String get chat_waitingHeader => 'EN ESPERA — SOLO EN TU TELÉFONO';

  @override
  String get chat_peerOfflineHeadline => 'Ahora mismo no está en la línea.';

  @override
  String get chat_peerOfflineBody =>
      'Todo lo que escribas espera aquí — solo en tu teléfono — y se envía cuando estéis los dos en la línea.';

  @override
  String get chat_expiryDisclaimer =>
      'Su app lo borrará a su hora, y la tuya también.\nUn temporizador no puede deshacer que algo se haya leído — una captura de pantalla sigue siendo una captura de pantalla. Es una cortesía entre los dos, no una garantía.';

  @override
  String get chat_timerOff => 'Desactivado';

  @override
  String chat_timerMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes min',
      one: '1 min',
    );
    return '$_temp0';
  }

  @override
  String chat_timerHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours h',
      one: '1 h',
    );
    return '$_temp0';
  }

  @override
  String get chat_timerButtonA11y => 'Temporizador de desaparición';

  @override
  String get chat_composerA11y => 'Mensaje';

  @override
  String get chat_sendA11y => 'Enviar';

  @override
  String get chat_deliveryWaitingA11y => 'En espera. Solo en tu teléfono.';

  @override
  String get chat_deliverySentA11y => 'Enviado.';

  @override
  String get chat_deliveryDeliveredA11y => 'Entregado.';

  @override
  String get media_attachA11y => 'Añadir una foto o un archivo';

  @override
  String get media_pickPhoto => 'Foto';

  @override
  String get media_pickFile => 'Archivo';

  @override
  String get media_overCapError =>
      'Eso supera los 5 MB — la línea transporta documentos, no archivos enormes. Prueba con un archivo más pequeño.';

  @override
  String get media_metadataStripNotice =>
      'Las fotos se limpian antes de sellarse — la ubicación, el dispositivo y la hora se eliminan en tu teléfono, antes del cifrado.';

  @override
  String get media_compressionNote =>
      'Se envían más pequeñas por defecto. La calidad original está a un toque.';

  @override
  String get media_originalQualityToggle => 'Calidad original';

  @override
  String get media_exportAction => 'Exportar';

  @override
  String get media_exportConfirm =>
      'Esto lo copia fuera de Nimna — al almacenamiento propio de tu teléfono.';

  @override
  String get media_exportRollNote =>
      'Nada de lo que recibes llega a tu carrete. Se queda dentro de Nimna hasta que decides sacarlo.';

  @override
  String get media_exportCancel => 'Volver';

  @override
  String media_viewerReceivedTime(String time) {
    return 'Recibido $time';
  }

  @override
  String get media_sendingA11y => 'Enviando.';

  @override
  String get media_receivingA11y => 'Recibiendo.';

  @override
  String get media_documentA11y => 'Documento.';

  @override
  String get media_imageA11y => 'Foto.';

  @override
  String get media_documentKindPdf => 'PDF';

  @override
  String get media_documentKindFile => 'Archivo';

  @override
  String media_sizeMegabytes(String size) {
    return '$size MB';
  }

  @override
  String media_sizeKilobytes(String size) {
    return '$size KB';
  }

  @override
  String media_documentMeta(String kind, String size) {
    return '$kind · $size';
  }

  @override
  String get knock_waitingTitle =>
      'Has llamado. Si descuelga en el próximo minuto, la línea se abre.';

  @override
  String get knock_waitingCaption =>
      'Con una llamada basta — no se repetirá por sí sola.';

  @override
  String get knock_noAnswer => 'Sin respuesta.';

  @override
  String get knock_knock => 'Llamar';

  @override
  String get knock_again => 'Volver a llamar';

  @override
  String get knock_staleHint =>
      'Sin respuesta desde hace un rato. Si ha perdido el teléfono, esta línea no puede volver — tendrías que emparejarte de nuevo con un código nuevo.';

  @override
  String knock_incomingKnocking(String label) {
    return '$label está llamando.';
  }

  @override
  String get knock_pickUp => 'Descolgar';

  @override
  String get knock_ignore => 'Ignorar';

  @override
  String get push_toggleLabel => 'Avisarme cuando llamen';

  @override
  String get push_tradeOff =>
      'Desactivado: nada de esta línea toca nunca Apple ni Google.';

  @override
  String get push_tradeOn =>
      'Activado: una llamada puede despertar este teléfono a través de su servicio de notificaciones, con dos palabras — «Actividad nueva». Sin línea, sin nombre, sin mensaje — y el relay olvida la dirección en cuanto se usa.';

  @override
  String get screenshot_systemLinePeer => 'Ha hecho una captura de pantalla.';

  @override
  String get screenshot_systemLineOwn =>
      'Has hecho una captura de pantalla. Se le ha avisado.';

  @override
  String get screenshot_onboardingDisclosure =>
      'Nimna no puede impedir una captura de pantalla. Siempre se lo dirá a la otra persona.\nSolo detecta lo que ocurre dentro de la app — una segunda cámara apuntando a una pantalla es invisible para cualquier software. Se dice desde el principio, para que los dos conozcan las condiciones.';

  @override
  String get screenshot_onboardingAndroidCaveat =>
      'En Android 13 y versiones anteriores, aquí no se puede detectar una captura de pantalla — solo Android 14 en adelante, y el iPhone, pueden avisar a la otra persona.';

  @override
  String get sensitive_veilCaption => 'Contenido sensible — toca para ver.';

  @override
  String get sensitive_whisperQuestion =>
      'Esto parece contenido sensible — ¿enviar de todos modos?';

  @override
  String get sensitive_whisperSendAnyway => 'Enviar de todos modos';

  @override
  String get sensitive_whisperGoBack => 'Volver';

  @override
  String get push_newActivityBody => 'Actividad nueva';

  @override
  String get channelSettings_subtitle =>
      'Ajustes de la línea — solo este teléfono';

  @override
  String get onboarding_whatItIsHeadline =>
      'Una línea privada entre dos personas.';

  @override
  String get onboarding_whatItIsBody =>
      'Sin cuentas. Sin nube. Los mensajes viven en los dos teléfonos, en ningún otro sitio.';

  @override
  String get onboarding_pairingHeadline => 'Emparéjate una vez con un código.';

  @override
  String get onboarding_pairingBody =>
      'Emparéjate una vez con un código Nimna que compartes como quieras — leído en voz alta, en papel o como el QR que se muestra justo al lado.\nDespués, el código desaparece para siempre. La línea es tuya.';

  @override
  String get onboarding_cannotSeeHeadline => 'Lo que no podemos ver';

  @override
  String get onboarding_cannotSeeBody =>
      'No podemos leer tus mensajes. Tampoco podemos recuperarlos.\nNo hay nada que entregar, porque no se guarda nada.';

  @override
  String get onboarding_cannotSeeRelayNote =>
      'El relay sí ve las horas de conexión, las direcciones IP y los tamaños de los mensajes — nunca el contenido. Los detalles están en Ajustes → Relay.';

  @override
  String get onboarding_next => 'Siguiente';

  @override
  String get onboarding_skip => 'Omitir';

  @override
  String get onboarding_start => 'Empezar';

  @override
  String knock_lapsesInSeconds(int seconds) {
    return 'Caduca en $seconds s';
  }

  @override
  String get settings_readReceiptsLabel => 'Confirmaciones de lectura';

  @override
  String get settings_readReceiptsCaption =>
      'Verá «Visto» bajo los mensajes que hayas leído. Solo en esta línea.';

  @override
  String get settings_typingLabel => 'Indicador de escritura';

  @override
  String get settings_typingCaption =>
      'Verá cuando estés escribiendo. Solo en esta línea.';

  @override
  String get session_readReceiptSeen => 'Visto';

  @override
  String get settings_rowDiagnostics => 'Compartir diagnósticos';

  @override
  String get settings_rowDiagnosticsCaption =>
      'Solo códigos de evento y horas — nunca tus mensajes. Nada sale de tu teléfono a menos que lo envíes.';

  @override
  String get diag_shareTitle => 'Diagnósticos';

  @override
  String get diag_shareExplainer =>
      'Es un registro técnico de lo que hizo la app — códigos de evento y horas, nada más. No contiene mensajes, ni nombres, ni códigos, ni direcciones, y no puede contenerlos. Se queda en tu teléfono a menos que decidas compartirlo.';

  @override
  String get diag_shareAction => 'Compartir el registro';

  @override
  String get diag_shareEmpty => 'Aún no hay nada que compartir.';

  @override
  String get notifications_emptyBody =>
      'Las notificaciones se activan por línea. Aún no tienes ninguna.';
}
