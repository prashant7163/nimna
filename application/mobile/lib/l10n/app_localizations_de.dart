// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'nimna';

  @override
  String get channelListEmptyHeadline => 'Noch keine Leitungen.';

  @override
  String get channelListEmptyBody =>
      'Erstelle einen Nimna-Code oder gib einen ein, den du bekommen hast.';

  @override
  String get channelListStatusQuiet => 'Still';

  @override
  String get actionCreateCode => 'Code erstellen';

  @override
  String get actionEnterCode => 'Code eingeben';

  @override
  String get chat_messageActionReply => 'Antworten';

  @override
  String get chat_messageActionReact => 'Reagieren';

  @override
  String get chat_messageActionDelete => 'Löschen';

  @override
  String get chat_replyingToLabel => 'Antwort an';

  @override
  String get chat_replyCancelA11y => 'Antwort abbrechen';

  @override
  String get chat_replyTombstone => 'Nachricht nicht mehr verfügbar.';

  @override
  String get chat_replyPreviewPhoto => 'Foto';

  @override
  String get chat_replyPreviewDocument => 'Dokument';

  @override
  String chat_reactionOwnA11y(String emoji) {
    return 'Du hast mit $emoji reagiert. Zum Entfernen tippen.';
  }

  @override
  String chat_reactionPeerA11y(String emoji) {
    return 'Die andere Person hat mit $emoji reagiert.';
  }

  @override
  String get chat_reactionPickMoreA11y => 'Anderes Emoji wählen';

  @override
  String get pairing_selfJoinOwnCode =>
      'Das ist dein eigener Nimna-Code — teile ihn mit der anderen Person.';

  @override
  String get pairing_createTitle => 'Code erstellen';

  @override
  String get pairing_createIntro =>
      'Ein Code koppelt dein Telefon mit genau einem anderen. Teile ihn, wie du magst — persönlich ist am sichersten.';

  @override
  String get pairing_ttlLabel => 'Code gilt für';

  @override
  String get pairing_ttlHint =>
      'Kürzer ist sicherer. So oder so nur einmal nutzbar.';

  @override
  String pairing_ttlHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours Stunden',
      one: '1 Stunde',
    );
    return '$_temp0';
  }

  @override
  String get pairing_offlineError =>
      'Du bist offline. Ein Code braucht das Relay, das auf ihn wartet — versuch es erneut, wenn du verbunden bist.';

  @override
  String get pairing_shareBriefing =>
      'Funktioniert einmal, läuft in 24 Std. ab — teile ihn wie ein Passwort.';

  @override
  String get pairing_eitherFormPairs =>
      'Die Wörter oder das Quadrat — beides koppelt euch.';

  @override
  String get pairing_copyAction => 'Kopieren';

  @override
  String get pairing_shareAction => 'Teilen…';

  @override
  String get pairing_codeCopiedToast => 'Code kopiert.';

  @override
  String get pairing_shareAsText => 'Code als Text teilen';

  @override
  String get pairing_shareQrAsImage => 'QR als Bild teilen';

  @override
  String get pairing_copyCode => 'Code kopieren';

  @override
  String get pairing_waitingForJoin =>
      'Warten, bis die andere Person beitritt …';

  @override
  String pairing_waitLifetime(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours Stunden',
      one: '1 Stunde',
    );
    return 'Dein Code gilt für $_temp0 — komm jederzeit wieder. Die Kopplung ist abgeschlossen, wenn ihr beide da seid.';
  }

  @override
  String get pairing_cancelCode => 'Diesen Code verwerfen';

  @override
  String get pairing_stopWaitingConfirm =>
      'Nicht mehr warten? Der Code wird ungültig.';

  @override
  String get pairing_notNow => 'Jetzt nicht';

  @override
  String get pairing_expiredHeadline => 'Dieser Code ist ungenutzt abgelaufen.';

  @override
  String get pairing_expiredBody =>
      'Es wurde nichts erstellt. Mach einen neuen, wann immer du bereit bist.';

  @override
  String get pairing_makeNewCode => 'Neuen Code erstellen';

  @override
  String get pairing_spentBody =>
      'Das ist nicht zu Ende gegangen. Der Code ist verbraucht — mach einen neuen.';

  @override
  String get settings_title => 'Einstellungen';

  @override
  String get settings_rowAppLock => 'App-Sperre';

  @override
  String get settings_rowAppLockOff =>
      'Aus — eine PIN oder dein Gesicht, bevor irgendetwas zu sehen ist';

  @override
  String get settings_rowAppLockOn => 'An';

  @override
  String get settings_rowAppLockOnBiometric => 'An — PIN + Face ID';

  @override
  String get settings_rowNotifications => 'Benachrichtigungen';

  @override
  String get settings_rowNotificationsCaption =>
      'Pro Leitung, aus, bis du sie einschaltest';

  @override
  String get settings_rowRelay => 'Relay';

  @override
  String get settings_rowRelayCaption => 'relay.nimna.app';

  @override
  String get settings_rowLicenses => 'Lizenzen';

  @override
  String get settings_rowWipeEverything => 'Alles löschen';

  @override
  String get settings_rowWipeEverythingCaption =>
      'Jede Leitung, jede Nachricht — dieses Telefon.';

  @override
  String get lock_choosePinTitle => 'PIN wählen';

  @override
  String get lock_choosePinCaption =>
      'Im gesperrten Zustand zeigt der Bildschirm nur das Symbol und dieses Tastenfeld. Sonst nichts — nicht einmal, wie viele Leitungen du hast.';

  @override
  String get lock_confirmPinTitle => 'Noch einmal eingeben';

  @override
  String get lock_confirmPinMismatch =>
      'Die stimmen nicht überein — fang neu an.';

  @override
  String get lock_actionNext => 'Weiter';

  @override
  String get lock_enterPinTitle => 'PIN eingeben';

  @override
  String get lock_actionTurnOff => 'Ausschalten';

  @override
  String get lock_biometricToggleLabel => 'Mit Face ID entsperren';

  @override
  String get lock_biometricToggleCaption =>
      'Empfohlen. Fällt auf deine PIN zurück.';

  @override
  String get lock_noRecoveryCaption =>
      'Eine vergessene PIN lässt sich nicht wiederherstellen — es gibt kein Konto, mit dem du dich als du ausweisen könntest. Sie zu vergessen bedeutet neu installieren, was die Leitungen auf diesem Telefon löscht.';

  @override
  String get lock_biometricPromptReason => 'Entsperre deine Leitungen.';

  @override
  String get lock_keypadDeleteA11y => 'Löschen';

  @override
  String get wipe_fullTitle => 'Alles löschen?';

  @override
  String get wipe_fullTitleEmphasis => 'Alles';

  @override
  String get wipe_fullBody =>
      'Schlüssel und Nachrichten werden auf diesem Telefon vernichtet. Es gibt kein Backup, nirgends, so gewollt — nichts kann sie zurückholen.';

  @override
  String get wipe_holdToWipe => 'Zum Löschen halten';

  @override
  String get wipe_fullHoldCaption => '2½ Sekunden halten. Loslassen bricht ab.';

  @override
  String get wipe_actionKeep => 'Behalten';

  @override
  String get wipe_channelTitle => 'Diese Leitung löschen?';

  @override
  String get wipe_channelBody =>
      'Schlüssel und Nachrichten dieser Leitung werden auf diesem Telefon vernichtet. Nichts kann sie zurückholen.';

  @override
  String get wipe_channelPeerNote =>
      'Das Telefon der anderen Person behält seine Seite, außer sie löscht ebenfalls.';

  @override
  String get wipe_channelHoldCaption =>
      '1,5 Sekunden halten. Loslassen behält alles.';

  @override
  String get wipe_channelWipedToast => 'Leitung gelöscht.';

  @override
  String get pairing_joinTitle => 'Code eingeben';

  @override
  String get pairing_joinIntro =>
      'Codes kommen von der anderen Person. Jeder funktioniert einmal.';

  @override
  String get pairing_joinPaste => 'Einfügen';

  @override
  String get pairing_joinScan => 'Scannen';

  @override
  String get pairing_joinUpload => 'Hochladen';

  @override
  String get pairing_joinAction => 'Beitreten';

  @override
  String get pairing_joinOffline =>
      'Du bist offline. Beitreten braucht eine Verbindung.';

  @override
  String get pairing_joinScanTitle => 'Code der anderen Person scannen';

  @override
  String get pairing_joinScanCaption =>
      'Richte deine Kamera auf den Code auf ihrem Bildschirm.';

  @override
  String get pairing_joinScanEnterInstead => 'Stattdessen eingeben';

  @override
  String get pairing_joinCameraDenied =>
      'Kein Kamerazugriff — gib den Code stattdessen ein.';

  @override
  String get pairing_joinNoQrInFile => 'Kein Code in dieser Datei.';

  @override
  String get pairing_joinFoundThem => 'Gefunden.';

  @override
  String get pairing_joinSettingUp => 'Leitung wird eingerichtet …';

  @override
  String get pairing_joinCodeSpentNote =>
      'Der Code hat seine Aufgabe erfüllt. Er funktioniert für niemanden noch einmal.';

  @override
  String get pairing_joinSpentBody =>
      'Das ist nicht zu Ende gegangen. Der Code ist verbraucht — bitte die andere Person um einen neuen.';

  @override
  String get pairing_noMatchError =>
      'Dieser Code passte zu nichts. Codes laufen ab — bitte die andere Person um einen neuen.';

  @override
  String get pairing_clearAction => 'Leeren';

  @override
  String get pairing_verifyTitle => 'Ruf sie an und vergleicht';

  @override
  String get pairing_verifyBody =>
      'Lest euch diese drei Wörter gegenseitig vor. Wenn sie übereinstimmen, gehört die Leitung euch allein.';

  @override
  String get pairing_verifyMatch => 'Sie stimmen überein';

  @override
  String get pairing_verifyMismatch => 'Sie stimmen nicht überein';

  @override
  String get pairing_mismatchTitle => 'Die Wörter stimmten nicht überein.';

  @override
  String get pairing_mismatchBody =>
      'Das kann bedeuten, dass sich beim Koppeln jemand zwischen euch geschaltet hat. Diese Kopplung wurde verworfen — nichts wurde behalten.';

  @override
  String get pairing_mismatchShareSafer =>
      'Erstell einen neuen Code und teile ihn über einen sichereren Weg. Persönlich ist am sichersten.';

  @override
  String get pairing_readyTitle => 'Die Leitung gehört dir.';

  @override
  String get pairing_nameLineLabel => 'Diese Leitung benennen';

  @override
  String get pairing_nameLineCaption =>
      'Bezeichnungen bleiben nur auf diesem Telefon. Sie werden nie irgendwohin gesendet.';

  @override
  String get pairing_doneAction => 'Fertig';

  @override
  String get pairing_goBack => 'Zurück';

  @override
  String get billing_headline => 'Einer von euch kauft die Leitung.';

  @override
  String get billing_subhead => 'Die andere Person zahlt nie.';

  @override
  String get billing_pointSubscriptionTitle => 'Ein Abo pro Jahr.';

  @override
  String get billing_pointSubscriptionCaption =>
      'So viele Leitungen, wie du erstellen magst.';

  @override
  String get billing_pointPermanenceTitle =>
      'Jede Leitung gehört dir für immer.';

  @override
  String get billing_pointPermanenceCaption =>
      'Läuft das Abo aus, funktioniert alles, was du erstellt hast, weiter — nur neue Leitungen warten.';

  @override
  String get billing_pointNoAccountTitle => 'Kein Konto.';

  @override
  String get billing_pointNoAccountCaption =>
      'Der Kaufbeleg bleibt zwischen dir und dem Store.';

  @override
  String get billing_pointJoiningFreeTitle => 'Beitreten ist immer kostenlos.';

  @override
  String get billing_pointJoiningFreeCaption =>
      'Die Person, die du einlädst, sieht diesen Bildschirm nie.';

  @override
  String billing_ctaStart(String price) {
    return '$price — starten';
  }

  @override
  String get billing_restore => 'Wiederherstellen';

  @override
  String get billing_noIdentityFootnote => 'Wir erfahren nie, wer du bist.';

  @override
  String get billing_restoreChecking => 'Wird mit dem Store geprüft …';

  @override
  String get billing_restoreSuccessToast => 'Kauf wiederhergestellt.';

  @override
  String get billing_subscriptionStartedToast => 'Abo gestartet.';

  @override
  String get billing_restoreNothing =>
      'Der Store hat kein Abo für dieses Konto.';

  @override
  String get billing_storeUnreachable =>
      'Der Store war nicht erreichbar. Versuch es gleich noch einmal.';

  @override
  String get billing_reconnectToVerify =>
      'Verbinde dich wieder, um dein Abo zu prüfen.';

  @override
  String get billing_tryAgain => 'Erneut versuchen';

  @override
  String billing_autoRenewDisclosure(String store) {
    return 'Ein Abo pro Jahr. Es verlängert sich von selbst und belastet dein $store-Konto, bis du kündigst — jederzeit, in deinen Kontoeinstellungen. Bereits erstellte Leitungen bleiben so oder so deine.';
  }

  @override
  String get billing_termsLabel => 'Nutzungsbedingungen';

  @override
  String get billing_privacyLabel => 'Datenschutzerklärung';

  @override
  String get session_lineOnline => 'In der Leitung';

  @override
  String get session_lineOffline => 'Nicht in der Leitung';

  @override
  String get session_lineLost => 'Die Leitung ist abgebrochen.';

  @override
  String get session_lineDropped =>
      'Die Leitung ist abgebrochen. Wird wieder verbunden …';

  @override
  String get session_lineRecovered => 'Ihr seid beide da.';

  @override
  String get session_peerHungUp => 'Die andere Person hat aufgelegt.';

  @override
  String get session_youHungUp => 'Du hast aufgelegt.';

  @override
  String get chat_hangUp => 'Auflegen';

  @override
  String get chat_waitingHeader => 'WARTET — NUR AUF DEINEM TELEFON';

  @override
  String get chat_peerOfflineHeadline =>
      'Die andere Person ist gerade nicht in der Leitung.';

  @override
  String get chat_peerOfflineBody =>
      'Was du schreibst, wartet hier — nur auf deinem Telefon — und geht raus, sobald ihr beide da seid.';

  @override
  String get chat_expiryDisclaimer =>
      'Die App der anderen Person löscht dies planmäßig, deine ebenfalls.\nEin Timer kann Gelesenes nicht rückgängig machen — ein Screenshot bleibt ein Screenshot. Es ist eine Höflichkeit zwischen euch beiden, keine Garantie.';

  @override
  String get chat_timerOff => 'Aus';

  @override
  String chat_timerMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes Min.',
      one: '1 Min.',
    );
    return '$_temp0';
  }

  @override
  String chat_timerHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours Std.',
      one: '1 Std.',
    );
    return '$_temp0';
  }

  @override
  String get chat_timerButtonA11y => 'Timer für verschwindende Nachrichten';

  @override
  String get chat_composerA11y => 'Nachricht';

  @override
  String get chat_sendA11y => 'Senden';

  @override
  String get chat_deliveryWaitingA11y => 'Wartet. Nur auf deinem Telefon.';

  @override
  String get chat_deliverySentA11y => 'Gesendet.';

  @override
  String get chat_deliveryDeliveredA11y => 'Zugestellt.';

  @override
  String get media_attachA11y => 'Foto oder Datei hinzufügen';

  @override
  String get media_pickPhoto => 'Foto';

  @override
  String get media_pickFile => 'Datei';

  @override
  String get media_overCapError =>
      'Das ist über 5 MB — die Leitung trägt Dokumente, keine Archive. Versuch eine kleinere Datei.';

  @override
  String get media_metadataStripNotice =>
      'Fotos werden bereinigt, bevor sie versiegelt werden — Ort, Gerät und Zeit werden auf deinem Telefon entfernt, vor der Verschlüsselung.';

  @override
  String get media_compressionNote =>
      'Standardmäßig kleiner gesendet. Originalqualität ist nur einen Schalter entfernt.';

  @override
  String get media_originalQualityToggle => 'Originalqualität';

  @override
  String get media_exportAction => 'Exportieren';

  @override
  String get media_exportConfirm =>
      'Das kopiert es aus Nimna heraus — in den eigenen Speicher deines Telefons.';

  @override
  String get media_exportRollNote =>
      'Nichts, was du empfängst, landet in deiner Fotogalerie. Es bleibt in Nimna, bis du dich entscheidest, es herauszunehmen.';

  @override
  String get media_exportCancel => 'Zurück';

  @override
  String media_viewerReceivedTime(String time) {
    return 'Empfangen $time';
  }

  @override
  String get media_sendingA11y => 'Wird gesendet.';

  @override
  String get media_receivingA11y => 'Wird empfangen.';

  @override
  String get media_documentA11y => 'Dokument.';

  @override
  String get media_imageA11y => 'Foto.';

  @override
  String get media_documentKindPdf => 'PDF';

  @override
  String get media_documentKindFile => 'Datei';

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
      'Angeklopft. Wenn die andere Person in der nächsten Minute abnimmt, öffnet sich die Leitung.';

  @override
  String get knock_waitingCaption =>
      'Einmal anklopfen genügt — es wiederholt sich nicht von selbst.';

  @override
  String get knock_noAnswer => 'Keine Antwort.';

  @override
  String get knock_knock => 'Anklopfen';

  @override
  String get knock_again => 'Erneut anklopfen';

  @override
  String get knock_staleHint =>
      'Seit einer Weile keine Antwort. Falls die andere Person ihr Telefon verloren hat, kann diese Leitung nicht zurückkommen — du würdest mit einem neuen Code erneut koppeln.';

  @override
  String knock_incomingKnocking(String label) {
    return '$label klopft an.';
  }

  @override
  String get knock_pickUp => 'Abnehmen';

  @override
  String get knock_ignore => 'Ignorieren';

  @override
  String get push_toggleLabel =>
      'Benachrichtige mich, wenn die andere Person anklopft';

  @override
  String get push_tradeOff =>
      'Aus: Nichts über diese Leitung berührt jemals Apple oder Google.';

  @override
  String get push_tradeOn =>
      'An: Ein Anklopfen kann dieses Telefon über ihren Benachrichtigungsdienst wecken und trägt zwei Wörter — „Neue Aktivität.“ Keine Leitung, kein Name, keine Nachricht — und das Relay vergisst die Adresse in dem Moment, in dem sie genutzt wird.';

  @override
  String get screenshot_systemLinePeer =>
      'Die andere Person hat einen Screenshot gemacht.';

  @override
  String get screenshot_systemLineOwn =>
      'Du hast einen Screenshot gemacht. Die andere Person wurde informiert.';

  @override
  String get screenshot_onboardingDisclosure =>
      'Nimna kann einen Screenshot nicht verhindern. Es meldet ihn der anderen Person immer.\nEs bemerkt nur, was innerhalb der App passiert — eine zweite Kamera, die auf einen Bildschirm gerichtet ist, ist für jede Software unsichtbar. Vorab gesagt, damit ihr beide die Bedingungen kennt.';

  @override
  String get screenshot_onboardingAndroidCaveat =>
      'Unter Android 13 und älter kann ein Screenshot hier nicht bemerkt werden — nur Android 14 und neuer sowie das iPhone können es der anderen Person mitteilen.';

  @override
  String get sensitive_veilCaption => 'Sensibler Inhalt — zum Ansehen tippen.';

  @override
  String get sensitive_whisperQuestion =>
      'Das sieht nach sensiblem Inhalt aus — trotzdem senden?';

  @override
  String get sensitive_whisperSendAnyway => 'Trotzdem senden';

  @override
  String get sensitive_whisperGoBack => 'Zurück';

  @override
  String get push_newActivityBody => 'Neue Aktivität';

  @override
  String get channelSettings_subtitle =>
      'Leitungseinstellungen — nur dieses Telefon';

  @override
  String get onboarding_whatItIsHeadline =>
      'Eine private Leitung zwischen zwei Menschen.';

  @override
  String get onboarding_whatItIsBody =>
      'Keine Konten. Keine Cloud. Nachrichten leben auf euren beiden Telefonen, sonst nirgends.';

  @override
  String get onboarding_pairingHeadline => 'Einmal koppeln mit einem Code.';

  @override
  String get onboarding_pairingBody =>
      'Kopple dein Telefon einmal mit einem Nimna-Code, den du teilst, wie du magst — vorgelesen, auf Papier oder als QR direkt daneben.\nDanach ist der Code für immer weg. Die Leitung gehört dir.';

  @override
  String get onboarding_cannotSeeHeadline => 'Was wir nicht sehen können';

  @override
  String get onboarding_cannotSeeBody =>
      'Wir können deine Nachrichten nicht lesen. Wir können sie auch nicht wiederherstellen.\nEs gibt nichts herauszugeben, weil nichts aufbewahrt wird.';

  @override
  String get onboarding_cannotSeeRelayNote =>
      'Das Relay sieht sehr wohl Verbindungszeiten, IP-Adressen und Nachrichtengrößen — nie den Inhalt. Details unter Einstellungen → Relay.';

  @override
  String get onboarding_next => 'Weiter';

  @override
  String get onboarding_skip => 'Überspringen';

  @override
  String get onboarding_start => 'Starten';

  @override
  String knock_lapsesInSeconds(int seconds) {
    return 'Läuft in $seconds s ab';
  }

  @override
  String get settings_readReceiptsLabel => 'Lesebestätigungen';

  @override
  String get settings_readReceiptsCaption =>
      'Die andere Person sieht „Gesehen“ unter Nachrichten, die du gelesen hast. Nur diese Leitung.';

  @override
  String get settings_typingLabel => 'Schreibanzeige';

  @override
  String get settings_typingCaption =>
      'Die andere Person sieht, wenn du schreibst. Nur diese Leitung.';

  @override
  String get session_readReceiptSeen => 'Gesehen';

  @override
  String get settings_rowDiagnostics => 'Diagnose teilen';

  @override
  String get settings_rowDiagnosticsCaption =>
      'Nur Ereigniscodes und Zeiten — nie deine Nachrichten. Nichts verlässt dein Telefon, außer du sendest es.';

  @override
  String get diag_shareTitle => 'Diagnose';

  @override
  String get diag_shareExplainer =>
      'Dies ist eine technische Aufzeichnung dessen, was die App getan hat — Ereigniscodes und Zeiten, mehr nicht. Keine Nachrichten, keine Namen, keine Codes, keine Adressen sind darin, und es kann sie auch gar nicht enthalten. Es bleibt auf deinem Telefon, außer du entscheidest dich, es zu teilen.';

  @override
  String get diag_shareAction => 'Protokoll teilen';

  @override
  String get diag_shareEmpty => 'Noch nichts zu teilen.';

  @override
  String get notifications_emptyBody =>
      'Benachrichtigungen werden pro Leitung eingeschaltet. Du hast noch keine.';
}
