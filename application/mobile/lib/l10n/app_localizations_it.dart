// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appTitle => 'nimna';

  @override
  String get channelListEmptyHeadline => 'Ancora nessuna linea.';

  @override
  String get channelListEmptyBody =>
      'Crea un codice Nimna, oppure inseriscine uno che ti hanno dato.';

  @override
  String get channelListStatusQuiet => 'Silenzio';

  @override
  String get actionCreateCode => 'Crea un codice';

  @override
  String get actionEnterCode => 'Inserisci un codice';

  @override
  String get chat_messageActionReply => 'Rispondi';

  @override
  String get chat_messageActionReact => 'Reagisci';

  @override
  String get chat_messageActionDelete => 'Elimina';

  @override
  String get chat_replyingToLabel => 'In risposta a';

  @override
  String get chat_replyCancelA11y => 'Annulla risposta';

  @override
  String get chat_replyTombstone => 'Messaggio non più disponibile.';

  @override
  String get chat_replyPreviewPhoto => 'Foto';

  @override
  String get chat_replyPreviewDocument => 'Documento';

  @override
  String chat_reactionOwnA11y(String emoji) {
    return 'Hai reagito con $emoji. Tocca per rimuovere.';
  }

  @override
  String chat_reactionPeerA11y(String emoji) {
    return 'Ha reagito con $emoji.';
  }

  @override
  String get chat_reactionPickMoreA11y => 'Scegli un\'altra emoji';

  @override
  String get pairing_selfJoinOwnCode =>
      'Questo è il tuo codice Nimna — condividilo con l\'altra persona.';

  @override
  String get pairing_createTitle => 'Crea un codice';

  @override
  String get pairing_createIntro =>
      'Un codice abbina il tuo telefono a un altro. Condividilo come preferisci — di persona è più sicuro.';

  @override
  String get pairing_ttlLabel => 'Il codice vale per';

  @override
  String get pairing_ttlHint =>
      'Più breve è più sicuro. Un solo utilizzo, in ogni caso.';

  @override
  String pairing_ttlHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours ore',
      one: '1 ora',
    );
    return '$_temp0';
  }

  @override
  String get pairing_offlineError =>
      'Sei offline. Un codice ha bisogno che il relay sia in ascolto — riprova quando sei connesso.';

  @override
  String get pairing_shareBriefing =>
      'Vale una sola volta, scade tra 24h — condividilo come una password.';

  @override
  String get pairing_eitherFormPairs =>
      'Le parole o il quadrato — l\'uno o l\'altro vi abbina.';

  @override
  String get pairing_copyAction => 'Copia';

  @override
  String get pairing_shareAction => 'Condividi…';

  @override
  String get pairing_codeCopiedToast => 'Codice copiato.';

  @override
  String get pairing_shareAsText => 'Condividi il codice come testo';

  @override
  String get pairing_shareQrAsImage => 'Condividi il QR come immagine';

  @override
  String get pairing_copyCode => 'Copia il codice';

  @override
  String get pairing_waitingForJoin =>
      'In attesa che l\'altra persona si unisca…';

  @override
  String pairing_waitLifetime(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours ore',
      one: '1 ora',
    );
    return 'Il tuo codice vale per $_temp0 — torna quando vuoi. L\'abbinamento si completa quando siete entrambi qui.';
  }

  @override
  String get pairing_cancelCode => 'Annulla questo codice';

  @override
  String get pairing_stopWaitingConfirm =>
      'Smettere di aspettare? Il codice smette di funzionare.';

  @override
  String get pairing_notNow => 'Non ora';

  @override
  String get pairing_expiredHeadline =>
      'Questo codice è scaduto senza essere usato.';

  @override
  String get pairing_expiredBody =>
      'Non è stato creato nulla. Creane uno nuovo quando vuoi.';

  @override
  String get pairing_makeNewCode => 'Crea un nuovo codice';

  @override
  String get pairing_spentBody =>
      'Non si è concluso. Il codice è esaurito — creane uno nuovo.';

  @override
  String get settings_title => 'Impostazioni';

  @override
  String get settings_rowAppLock => 'Blocco dell\'app';

  @override
  String get settings_rowAppLockOff =>
      'Disattivato — un PIN o il tuo volto, prima che appaia qualcosa';

  @override
  String get settings_rowAppLockOn => 'Attivo';

  @override
  String get settings_rowAppLockOnBiometric => 'Attivo — PIN + Face ID';

  @override
  String get settings_rowNotifications => 'Notifiche';

  @override
  String get settings_rowNotificationsCaption =>
      'Per ogni linea, disattivate se non le attivi tu';

  @override
  String get settings_rowRelay => 'Relay';

  @override
  String get settings_rowRelayCaption => 'relay.nimna.app';

  @override
  String get settings_rowLicenses => 'Licenze';

  @override
  String get settings_rowWipeEverything => 'Cancella tutto';

  @override
  String get settings_rowWipeEverythingCaption =>
      'Ogni linea, ogni messaggio — questo telefono.';

  @override
  String get lock_choosePinTitle => 'Scegli un PIN';

  @override
  String get lock_choosePinCaption =>
      'Quando è bloccato, lo schermo mostra solo il simbolo e questo tastierino. Nient\'altro — nemmeno quante linee hai.';

  @override
  String get lock_confirmPinTitle => 'Inseriscilo di nuovo';

  @override
  String get lock_confirmPinMismatch => 'Non coincidono — ricomincia.';

  @override
  String get lock_actionNext => 'Avanti';

  @override
  String get lock_enterPinTitle => 'Inserisci il tuo PIN';

  @override
  String get lock_actionTurnOff => 'Disattiva';

  @override
  String get lock_biometricToggleLabel => 'Sblocca con Face ID';

  @override
  String get lock_biometricToggleCaption =>
      'Consigliato. In alternativa usa il tuo PIN.';

  @override
  String get lock_noRecoveryCaption =>
      'Non c\'è modo di recuperare un PIN dimenticato — non esiste un account per dimostrare che sei tu. Dimenticarlo significa reinstallare, e questo cancella le linee di questo telefono.';

  @override
  String get lock_biometricPromptReason => 'Sblocca le tue linee.';

  @override
  String get lock_keypadDeleteA11y => 'Cancella';

  @override
  String get wipe_fullTitle => 'Cancellare tutto?';

  @override
  String get wipe_fullTitleEmphasis => 'tutto';

  @override
  String get wipe_fullBody =>
      'Le chiavi e i messaggi vengono distrutti su questo telefono. Non esiste alcun backup, da nessuna parte, per scelta — niente può riportarli indietro.';

  @override
  String get wipe_holdToWipe => 'Tieni premuto per cancellare';

  @override
  String get wipe_fullHoldCaption =>
      'Tieni premuto per 2½ secondi. Rilascia per annullare.';

  @override
  String get wipe_actionKeep => 'Tieni';

  @override
  String get wipe_channelTitle => 'Cancellare questa linea?';

  @override
  String get wipe_channelBody =>
      'Le chiavi e i messaggi di questa linea vengono distrutti su questo telefono. Niente può riportarli indietro.';

  @override
  String get wipe_channelPeerNote =>
      'L\'altro telefono conserva la propria parte, a meno che non venga cancellata anche lì.';

  @override
  String get wipe_channelHoldCaption =>
      'Tieni premuto per 1,5 secondi. Rilascia per conservare tutto.';

  @override
  String get wipe_channelWipedToast => 'Linea cancellata.';

  @override
  String get pairing_joinTitle => 'Inserisci un codice';

  @override
  String get pairing_joinIntro =>
      'I codici arrivano dall\'altra persona. Ognuno vale una sola volta.';

  @override
  String get pairing_joinPaste => 'Incolla';

  @override
  String get pairing_joinScan => 'Scansiona';

  @override
  String get pairing_joinUpload => 'Carica';

  @override
  String get pairing_joinAction => 'Unisciti';

  @override
  String get pairing_joinOffline =>
      'Sei offline. Per unirti serve una connessione.';

  @override
  String get pairing_joinScanTitle => 'Scansiona il suo codice';

  @override
  String get pairing_joinScanCaption =>
      'Punta la fotocamera sul codice mostrato sul suo schermo.';

  @override
  String get pairing_joinScanEnterInstead => 'Inseriscilo a mano';

  @override
  String get pairing_joinCameraDenied =>
      'Nessun accesso alla fotocamera — digita il codice a mano.';

  @override
  String get pairing_joinNoQrInFile => 'Nessun codice in quel file.';

  @override
  String get pairing_joinFoundThem => 'Vi siete trovati.';

  @override
  String get pairing_joinSettingUp => 'Preparazione della linea…';

  @override
  String get pairing_joinCodeSpentNote =>
      'Il codice ha svolto il suo compito. Non funzionerà più per nessuno.';

  @override
  String get pairing_joinSpentBody =>
      'Non si è concluso. Il codice è esaurito — chiedi all\'altra persona di crearne uno nuovo.';

  @override
  String get pairing_noMatchError =>
      'Quel codice non corrisponde a nulla. I codici scadono — chiedi all\'altra persona di crearne uno nuovo.';

  @override
  String get pairing_clearAction => 'Cancella';

  @override
  String get pairing_verifyTitle => 'Chiamatevi e confrontate';

  @override
  String get pairing_verifyBody =>
      'Leggetevi a vicenda queste tre parole. Se coincidono, la linea è solo vostra.';

  @override
  String get pairing_verifyMatch => 'Coincidono';

  @override
  String get pairing_verifyMismatch => 'Non coincidono';

  @override
  String get pairing_mismatchTitle => 'Le parole non coincidono.';

  @override
  String get pairing_mismatchBody =>
      'Può significare che qualcuno si è messo in mezzo durante l\'abbinamento. Questo abbinamento è stato scartato — non è stato conservato nulla.';

  @override
  String get pairing_mismatchShareSafer =>
      'Crea un nuovo codice e condividilo in un luogo più sicuro. Di persona è il modo più sicuro.';

  @override
  String get pairing_readyTitle => 'La linea è tua.';

  @override
  String get pairing_nameLineLabel => 'Dai un nome a questa linea';

  @override
  String get pairing_nameLineCaption =>
      'Le etichette restano solo su questo telefono. Non vengono mai inviate da nessuna parte.';

  @override
  String get pairing_doneAction => 'Fatto';

  @override
  String get pairing_goBack => 'Torna indietro';

  @override
  String get billing_headline => 'Uno di voi acquista la linea.';

  @override
  String get billing_subhead => 'L\'altra persona non paga mai.';

  @override
  String get billing_pointSubscriptionTitle => 'Un abbonamento all\'anno.';

  @override
  String get billing_pointSubscriptionCaption =>
      'Tutte le linee che vuoi creare.';

  @override
  String get billing_pointPermanenceTitle => 'Ogni linea è tua per sempre.';

  @override
  String get billing_pointPermanenceCaption =>
      'Se scade, tutto ciò che hai creato continua a funzionare — solo le nuove linee restano in attesa.';

  @override
  String get billing_pointNoAccountTitle => 'Nessun account.';

  @override
  String get billing_pointNoAccountCaption =>
      'La ricevuta resta tra te e lo store.';

  @override
  String get billing_pointJoiningFreeTitle => 'Unirsi è sempre gratis.';

  @override
  String get billing_pointJoiningFreeCaption =>
      'La persona che inviti non vede mai questa schermata.';

  @override
  String billing_ctaStart(String price) {
    return '$price — inizia';
  }

  @override
  String get billing_restore => 'Ripristina';

  @override
  String get billing_noIdentityFootnote => 'Non scopriamo mai chi sei.';

  @override
  String get billing_restoreChecking => 'Verifica con lo store…';

  @override
  String get billing_restoreSuccessToast => 'Acquisto ripristinato.';

  @override
  String get billing_subscriptionStartedToast => 'Abbonamento attivato.';

  @override
  String get billing_restoreNothing =>
      'Lo store non ha alcun abbonamento per questo account.';

  @override
  String get billing_storeUnreachable =>
      'Non è stato possibile raggiungere lo store. Riprova tra un momento.';

  @override
  String get billing_reconnectToVerify =>
      'Riconnettiti per verificare il tuo abbonamento.';

  @override
  String get billing_tryAgain => 'Riprova';

  @override
  String billing_autoRenewDisclosure(String store) {
    return 'Un abbonamento annuale. Si rinnova automaticamente e addebita il costo sul tuo account $store finché non lo annulli — quando vuoi, nelle impostazioni del tuo account. Le linee che hai già creato restano comunque tue.';
  }

  @override
  String get billing_termsLabel => 'Condizioni d\'uso';

  @override
  String get billing_privacyLabel => 'Informativa sulla privacy';

  @override
  String get session_lineOnline => 'In linea';

  @override
  String get session_lineOffline => 'Non in linea';

  @override
  String get session_lineLost => 'La linea è caduta.';

  @override
  String get session_lineDropped => 'La linea è caduta. Provo a riconnettermi…';

  @override
  String get session_lineRecovered => 'Siete entrambi qui.';

  @override
  String get session_peerHungUp => 'Ha riattaccato.';

  @override
  String get session_youHungUp => 'Hai riattaccato.';

  @override
  String get chat_hangUp => 'Riattacca';

  @override
  String get chat_waitingHeader => 'IN ATTESA — SOLO SUL TUO TELEFONO';

  @override
  String get chat_peerOfflineHeadline =>
      'L\'altra persona non è in linea in questo momento.';

  @override
  String get chat_peerOfflineBody =>
      'Tutto ciò che scrivi resta qui — solo sul tuo telefono — e parte quando siete entrambi in linea.';

  @override
  String get chat_expiryDisclaimer =>
      'L\'app dell\'altra persona lo eliminerà come previsto, e anche la tua lo farà.\nUn timer non può annullare il fatto di essere stato letto — uno screenshot resta uno screenshot. È una cortesia tra voi due, non una garanzia.';

  @override
  String get chat_timerOff => 'Nessuno';

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
  String get chat_timerButtonA11y => 'Timer di scomparsa';

  @override
  String get chat_composerA11y => 'Messaggio';

  @override
  String get chat_sendA11y => 'Invia';

  @override
  String get chat_deliveryWaitingA11y => 'In attesa. Solo sul tuo telefono.';

  @override
  String get chat_deliverySentA11y => 'Inviato.';

  @override
  String get chat_deliveryDeliveredA11y => 'Consegnato.';

  @override
  String get media_attachA11y => 'Aggiungi una foto o un file';

  @override
  String get media_pickPhoto => 'Foto';

  @override
  String get media_pickFile => 'File';

  @override
  String get media_overCapError =>
      'Supera i 5 MB — la linea trasporta documenti, non archivi. Prova con un file più piccolo.';

  @override
  String get media_metadataStripNotice =>
      'Le foto vengono ripulite prima di essere sigillate — posizione, dispositivo e ora vengono rimossi sul tuo telefono, prima della cifratura.';

  @override
  String get media_compressionNote =>
      'Inviate più leggere per impostazione predefinita. Per la qualità originale basta un interruttore.';

  @override
  String get media_originalQualityToggle => 'Qualità originale';

  @override
  String get media_exportAction => 'Esporta';

  @override
  String get media_exportConfirm =>
      'Questo lo copia fuori da Nimna — nella memoria del tuo telefono.';

  @override
  String get media_exportRollNote =>
      'Niente di ciò che ricevi finisce nel rullino fotografico. Resta dentro Nimna finché non scegli di portarlo fuori.';

  @override
  String get media_exportCancel => 'Torna indietro';

  @override
  String media_viewerReceivedTime(String time) {
    return 'Ricevuto $time';
  }

  @override
  String get media_sendingA11y => 'Invio in corso.';

  @override
  String get media_receivingA11y => 'Ricezione in corso.';

  @override
  String get media_documentA11y => 'Documento.';

  @override
  String get media_imageA11y => 'Foto.';

  @override
  String get media_documentKindPdf => 'PDF';

  @override
  String get media_documentKindFile => 'File';

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
      'Hai bussato. Se risponde entro un minuto, la linea si apre.';

  @override
  String get knock_waitingCaption =>
      'Basta bussare una volta — non si ripete da solo.';

  @override
  String get knock_noAnswer => 'Nessuna risposta.';

  @override
  String get knock_knock => 'Bussa';

  @override
  String get knock_again => 'Bussa di nuovo';

  @override
  String get knock_staleHint =>
      'Nessuna risposta da un po\'. Se l\'altra persona ha perso il telefono, questa linea non può tornare — dovresti abbinarti di nuovo con un nuovo codice.';

  @override
  String knock_incomingKnocking(String label) {
    return '$label sta bussando.';
  }

  @override
  String get knock_pickUp => 'Rispondi';

  @override
  String get knock_ignore => 'Ignora';

  @override
  String get push_toggleLabel => 'Avvisami quando bussa';

  @override
  String get push_tradeOff =>
      'Disattivato: niente di questa linea tocca mai Apple o Google.';

  @override
  String get push_tradeOn =>
      'Attivato: un colpo può risvegliare questo telefono attraverso il loro servizio di notifiche, portando due parole — \"Nuova attività.\" Nessuna linea, nessun nome, nessun messaggio — e il relay dimentica l\'indirizzo nell\'istante in cui viene usato.';

  @override
  String get screenshot_systemLinePeer => 'Ha fatto uno screenshot.';

  @override
  String get screenshot_systemLineOwn =>
      'Hai fatto uno screenshot. L\'altra persona è stata avvisata.';

  @override
  String get screenshot_onboardingDisclosure =>
      'Nimna non può impedire uno screenshot. Avviserà sempre l\'altra persona.\nNota solo ciò che accade dentro l\'app — una seconda fotocamera puntata su uno schermo è invisibile a qualsiasi software. Detto in chiaro, così sapete entrambi come stanno le cose.';

  @override
  String get screenshot_onboardingAndroidCaveat =>
      'Su Android 13 e versioni precedenti, uno screenshot non può essere rilevato qui — solo Android 14 e successivi, e iPhone, possono avvisare l\'altra persona.';

  @override
  String get sensitive_veilCaption => 'Contenuto sensibile — tocca per vedere.';

  @override
  String get sensitive_whisperQuestion =>
      'Sembra un contenuto sensibile — inviare comunque?';

  @override
  String get sensitive_whisperSendAnyway => 'Invia comunque';

  @override
  String get sensitive_whisperGoBack => 'Torna indietro';

  @override
  String get push_newActivityBody => 'Nuova attività';

  @override
  String get channelSettings_subtitle =>
      'Impostazioni della linea — solo questo telefono';

  @override
  String get onboarding_whatItIsHeadline =>
      'Una linea privata tra due persone.';

  @override
  String get onboarding_whatItIsBody =>
      'Nessun account. Nessun cloud. I messaggi vivono sui vostri due telefoni, da nessun\'altra parte.';

  @override
  String get onboarding_pairingHeadline => 'Abbinati una volta con un codice.';

  @override
  String get onboarding_pairingBody =>
      'Ti abbini una sola volta con un codice Nimna che condividi come preferisci — letto ad alta voce, su carta o come il QR mostrato lì accanto.\nDopodiché, il codice è sparito per sempre. La linea è tua.';

  @override
  String get onboarding_cannotSeeHeadline => 'Ciò che non possiamo vedere';

  @override
  String get onboarding_cannotSeeBody =>
      'Non possiamo leggere i tuoi messaggi. E non possiamo nemmeno recuperarli.\nNon c\'è nulla da consegnare, perché non viene conservato nulla.';

  @override
  String get onboarding_cannotSeeRelayNote =>
      'Il relay vede gli orari di connessione, gli indirizzi IP e le dimensioni dei messaggi — mai il contenuto. I dettagli sono in Impostazioni → Relay.';

  @override
  String get onboarding_next => 'Avanti';

  @override
  String get onboarding_skip => 'Salta';

  @override
  String get onboarding_start => 'Inizia';

  @override
  String knock_lapsesInSeconds(int seconds) {
    return 'Scade tra $seconds s';
  }

  @override
  String get settings_readReceiptsLabel => 'Conferme di lettura';

  @override
  String get settings_readReceiptsCaption =>
      'Vedrà \"Visto\" sotto i messaggi che hai letto. Solo questa linea.';

  @override
  String get settings_typingLabel => 'Indicatore di scrittura';

  @override
  String get settings_typingCaption =>
      'Vedrà quando stai scrivendo. Solo questa linea.';

  @override
  String get session_readReceiptSeen => 'Visto';

  @override
  String get settings_rowDiagnostics => 'Condividi la diagnostica';

  @override
  String get settings_rowDiagnosticsCaption =>
      'Solo codici di eventi e orari — mai i tuoi messaggi. Niente lascia il tuo telefono se non lo invii tu.';

  @override
  String get diag_shareTitle => 'Diagnostica';

  @override
  String get diag_shareExplainer =>
      'Questo è un registro tecnico di ciò che l\'app ha fatto — codici di eventi e orari, nulla di più. Non contiene messaggi, né nomi, né codici, né indirizzi, e non può contenerli. Resta sul tuo telefono a meno che tu non scelga di condividerlo.';

  @override
  String get diag_shareAction => 'Condividi il registro';

  @override
  String get diag_shareEmpty => 'Ancora niente da condividere.';

  @override
  String get notifications_emptyBody =>
      'Le notifiche si attivano per ogni linea. Non ne hai ancora.';
}
