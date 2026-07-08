// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'nimna';

  @override
  String get channelListEmptyHeadline => 'Aucune ligne pour l\'instant.';

  @override
  String get channelListEmptyBody =>
      'Créez un code Nimna, ou saisissez celui qu\'on vous a donné.';

  @override
  String get channelListStatusQuiet => 'Silencieuse';

  @override
  String get actionCreateCode => 'Créer un code';

  @override
  String get actionEnterCode => 'Saisir un code';

  @override
  String get chat_messageActionReply => 'Répondre';

  @override
  String get chat_messageActionReact => 'Réagir';

  @override
  String get chat_messageActionDelete => 'Supprimer';

  @override
  String get chat_replyingToLabel => 'En réponse à';

  @override
  String get chat_replyCancelA11y => 'Annuler la réponse';

  @override
  String get chat_replyTombstone => 'Message plus disponible.';

  @override
  String get chat_replyPreviewPhoto => 'Photo';

  @override
  String get chat_replyPreviewDocument => 'Document';

  @override
  String chat_reactionOwnA11y(String emoji) {
    return 'Vous avez réagi $emoji. Touchez pour retirer.';
  }

  @override
  String chat_reactionPeerA11y(String emoji) {
    return 'L\'autre personne a réagi $emoji.';
  }

  @override
  String get chat_reactionPickMoreA11y => 'Choisir un autre emoji';

  @override
  String get pairing_selfJoinOwnCode =>
      'C\'est votre propre code Nimna — partagez-le avec l\'autre personne.';

  @override
  String get pairing_createTitle => 'Créer un code';

  @override
  String get pairing_createIntro =>
      'Un code associe votre téléphone à un seul autre. Partagez-le comme vous voulez — en personne, c\'est le plus sûr.';

  @override
  String get pairing_ttlLabel => 'Le code fonctionne pendant';

  @override
  String get pairing_ttlHint =>
      'Plus court, plus sûr. Une seule utilisation, dans tous les cas.';

  @override
  String pairing_ttlHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours heures',
      one: '1 heure',
    );
    return '$_temp0';
  }

  @override
  String get pairing_offlineError =>
      'Vous êtes hors connexion. Un code a besoin que le relais soit à l\'écoute — réessayez dès que vous avez une connexion.';

  @override
  String get pairing_shareBriefing =>
      'Fonctionne une fois, expire dans 24 h — partagez-le comme un mot de passe.';

  @override
  String get pairing_eitherFormPairs =>
      'Les mots ou le carré — l\'un comme l\'autre vous associe.';

  @override
  String get pairing_copyAction => 'Copier';

  @override
  String get pairing_shareAction => 'Partager…';

  @override
  String get pairing_codeCopiedToast => 'Code copié.';

  @override
  String get pairing_shareAsText => 'Partager le code en texte';

  @override
  String get pairing_shareQrAsImage => 'Partager le QR en image';

  @override
  String get pairing_copyCode => 'Copier le code';

  @override
  String get pairing_waitingForJoin =>
      'En attente que l\'autre personne rejoigne…';

  @override
  String pairing_waitLifetime(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours heures',
      one: '1 heure',
    );
    return 'Votre code fonctionne pendant $_temp0 — revenez quand vous voulez. L\'association se termine quand vous êtes tous les deux là.';
  }

  @override
  String get pairing_cancelCode => 'Annuler ce code';

  @override
  String get pairing_stopWaitingConfirm =>
      'Arrêter d\'attendre ? Le code cesse de fonctionner.';

  @override
  String get pairing_notNow => 'Pas maintenant';

  @override
  String get pairing_expiredHeadline => 'Ce code a expiré sans être utilisé.';

  @override
  String get pairing_expiredBody =>
      'Rien n\'a été créé. Faites-en un nouveau quand vous voulez.';

  @override
  String get pairing_makeNewCode => 'Créer un nouveau code';

  @override
  String get pairing_spentBody =>
      'Ça ne s\'est pas terminé. Le code est épuisé — créez-en un nouveau.';

  @override
  String get settings_title => 'Réglages';

  @override
  String get settings_rowAppLock => 'Verrouillage de l\'app';

  @override
  String get settings_rowAppLockOff =>
      'Désactivé — un code PIN ou votre visage, avant que rien ne s\'affiche';

  @override
  String get settings_rowAppLockOn => 'Activé';

  @override
  String get settings_rowAppLockOnBiometric => 'Activé — code PIN + Face ID';

  @override
  String get settings_rowNotifications => 'Notifications';

  @override
  String get settings_rowNotificationsCaption =>
      'Par ligne, désactivées sauf si vous les activez';

  @override
  String get settings_rowRelay => 'Relais';

  @override
  String get settings_rowRelayCaption => 'relay.nimna.app';

  @override
  String get settings_rowLicenses => 'Licences';

  @override
  String get settings_rowWipeEverything => 'Tout effacer';

  @override
  String get settings_rowWipeEverythingCaption =>
      'Chaque ligne, chaque message — ce téléphone.';

  @override
  String get lock_choosePinTitle => 'Choisir un code PIN';

  @override
  String get lock_choosePinCaption =>
      'Une fois verrouillé, l\'écran n\'affiche que le symbole et ce clavier. Rien d\'autre — pas même le nombre de lignes que vous avez.';

  @override
  String get lock_confirmPinTitle => 'Saisissez-le à nouveau';

  @override
  String get lock_confirmPinMismatch => 'Ça ne correspond pas — recommencez.';

  @override
  String get lock_actionNext => 'Suivant';

  @override
  String get lock_enterPinTitle => 'Saisissez votre code PIN';

  @override
  String get lock_actionTurnOff => 'Désactiver';

  @override
  String get lock_biometricToggleLabel => 'Déverrouiller avec Face ID';

  @override
  String get lock_biometricToggleCaption =>
      'Recommandé. À défaut, votre code PIN.';

  @override
  String get lock_noRecoveryCaption =>
      'Il n\'existe aucun moyen de récupérer un code PIN oublié — il n\'y a pas de compte pour prouver que c\'est bien vous. L\'oublier signifie réinstaller, ce qui efface les lignes de ce téléphone.';

  @override
  String get lock_biometricPromptReason => 'Déverrouillez vos lignes.';

  @override
  String get lock_keypadDeleteA11y => 'Supprimer';

  @override
  String get wipe_fullTitle => 'Tout effacer ?';

  @override
  String get wipe_fullTitleEmphasis => 'Tout';

  @override
  String get wipe_fullBody =>
      'Les clés et les messages sont détruits sur ce téléphone. Il n\'existe aucune sauvegarde, nulle part, par conception — rien ne peut les ramener.';

  @override
  String get wipe_holdToWipe => 'Maintenez pour effacer';

  @override
  String get wipe_fullHoldCaption =>
      'Maintenez pendant 2,5 secondes. Relâchez pour annuler.';

  @override
  String get wipe_actionKeep => 'Garder';

  @override
  String get wipe_channelTitle => 'Effacer cette ligne ?';

  @override
  String get wipe_channelBody =>
      'Les clés et les messages de cette ligne sont détruits sur ce téléphone. Rien ne peut les ramener.';

  @override
  String get wipe_channelPeerNote =>
      'Son téléphone conserve son côté, à moins que l\'autre personne l\'efface aussi.';

  @override
  String get wipe_channelHoldCaption =>
      'Maintenez pendant 1,5 seconde. Relâchez pour tout garder.';

  @override
  String get wipe_channelWipedToast => 'Ligne effacée.';

  @override
  String get pairing_joinTitle => 'Saisir un code';

  @override
  String get pairing_joinIntro =>
      'Les codes viennent de l\'autre personne. Chacun fonctionne une seule fois.';

  @override
  String get pairing_joinPaste => 'Coller';

  @override
  String get pairing_joinScan => 'Scanner';

  @override
  String get pairing_joinUpload => 'Importer';

  @override
  String get pairing_joinAction => 'Rejoindre';

  @override
  String get pairing_joinOffline =>
      'Vous êtes hors connexion. Rejoindre nécessite une connexion.';

  @override
  String get pairing_joinScanTitle => 'Scanner son code';

  @override
  String get pairing_joinScanCaption =>
      'Pointez votre caméra vers le code sur son écran.';

  @override
  String get pairing_joinScanEnterInstead => 'Le saisir plutôt';

  @override
  String get pairing_joinCameraDenied =>
      'Pas d\'accès à la caméra — saisissez le code plutôt.';

  @override
  String get pairing_joinNoQrInFile => 'Aucun code dans ce fichier.';

  @override
  String get pairing_joinFoundThem => 'Trouvé.';

  @override
  String get pairing_joinSettingUp => 'Mise en place de la ligne…';

  @override
  String get pairing_joinCodeSpentNote =>
      'Le code a fait son travail. Il ne fonctionnera plus, pour personne.';

  @override
  String get pairing_joinSpentBody =>
      'Ça ne s\'est pas terminé. Le code est épuisé — demandez à l\'autre personne d\'en créer un nouveau.';

  @override
  String get pairing_noMatchError =>
      'Ce code ne correspond à rien. Les codes expirent — demandez à l\'autre personne d\'en créer un nouveau.';

  @override
  String get pairing_clearAction => 'Effacer';

  @override
  String get pairing_verifyTitle => 'Appelez l\'autre personne et comparez';

  @override
  String get pairing_verifyBody =>
      'Lisez-vous ces trois mots l\'un à l\'autre. S\'ils correspondent, la ligne n\'est qu\'à vous deux.';

  @override
  String get pairing_verifyMatch => 'Ils correspondent';

  @override
  String get pairing_verifyMismatch => 'Ils ne correspondent pas';

  @override
  String get pairing_mismatchTitle => 'Les mots ne correspondaient pas.';

  @override
  String get pairing_mismatchBody =>
      'Cela peut signifier que quelqu\'un s\'est glissé entre vous pendant l\'association. Cette association a été jetée — rien n\'a été conservé.';

  @override
  String get pairing_mismatchShareSafer =>
      'Créez un nouveau code et partagez-le dans un endroit plus sûr. En personne, c\'est le plus sûr.';

  @override
  String get pairing_readyTitle => 'La ligne est à vous.';

  @override
  String get pairing_nameLineLabel => 'Nommez cette ligne';

  @override
  String get pairing_nameLineCaption =>
      'Les étiquettes restent uniquement sur ce téléphone. Elles ne sont jamais envoyées où que ce soit.';

  @override
  String get pairing_doneAction => 'Terminé';

  @override
  String get pairing_goBack => 'Revenir en arrière';

  @override
  String get billing_headline => 'L\'un de vous achète la ligne.';

  @override
  String get billing_subhead => 'L\'autre ne paie jamais.';

  @override
  String get billing_pointSubscriptionTitle => 'Un abonnement par an.';

  @override
  String get billing_pointSubscriptionCaption =>
      'Autant de lignes que vous voulez créer.';

  @override
  String get billing_pointPermanenceTitle =>
      'Chaque ligne est à vous pour de bon.';

  @override
  String get billing_pointPermanenceCaption =>
      'En cas d\'interruption, tout ce que vous avez créé continue de fonctionner — seules les nouvelles lignes attendent.';

  @override
  String get billing_pointNoAccountTitle => 'Pas de compte.';

  @override
  String get billing_pointNoAccountCaption =>
      'Le reçu reste entre vous et la boutique.';

  @override
  String get billing_pointJoiningFreeTitle => 'Rejoindre est toujours gratuit.';

  @override
  String get billing_pointJoiningFreeCaption =>
      'La personne que vous invitez ne voit jamais cet écran.';

  @override
  String billing_ctaStart(String price) {
    return '$price — commencer';
  }

  @override
  String get billing_restore => 'Restaurer';

  @override
  String get billing_noIdentityFootnote =>
      'Nous ne savons jamais qui vous êtes.';

  @override
  String get billing_restoreChecking => 'Vérification auprès de la boutique…';

  @override
  String get billing_restoreSuccessToast => 'Achat restauré.';

  @override
  String get billing_subscriptionStartedToast => 'Abonnement activé.';

  @override
  String get billing_restoreNothing =>
      'La boutique n\'a aucun abonnement pour ce compte.';

  @override
  String get billing_storeUnreachable =>
      'Impossible de joindre la boutique. Réessayez dans un instant.';

  @override
  String get billing_reconnectToVerify =>
      'Reconnectez-vous pour vérifier votre abonnement.';

  @override
  String get billing_tryAgain => 'Réessayer';

  @override
  String billing_autoRenewDisclosure(String store) {
    return 'Un abonnement annuel. Il se renouvelle tout seul et débite votre compte $store jusqu\'à ce que vous l\'annuliez — à tout moment, dans les réglages de votre compte. Les lignes que vous avez déjà créées restent à vous dans tous les cas.';
  }

  @override
  String get billing_termsLabel => 'Conditions d\'utilisation';

  @override
  String get billing_privacyLabel => 'Politique de confidentialité';

  @override
  String get session_lineOnline => 'Sur la ligne';

  @override
  String get session_lineOffline => 'Pas sur la ligne';

  @override
  String get session_lineLost => 'La ligne a été coupée.';

  @override
  String get session_lineDropped =>
      'La ligne a été coupée. Tentative de reconnexion…';

  @override
  String get session_lineRecovered => 'Vous êtes tous les deux là.';

  @override
  String get session_peerHungUp => 'L\'autre a raccroché.';

  @override
  String get session_youHungUp => 'Vous avez raccroché.';

  @override
  String get chat_hangUp => 'Raccrocher';

  @override
  String get chat_waitingHeader =>
      'EN ATTENTE — SUR VOTRE TÉLÉPHONE UNIQUEMENT';

  @override
  String get chat_peerOfflineHeadline =>
      'L\'autre personne n\'est pas sur la ligne pour le moment.';

  @override
  String get chat_peerOfflineBody =>
      'Tout ce que vous écrivez attend ici — sur votre téléphone uniquement — et part quand vous êtes tous les deux sur la ligne.';

  @override
  String get chat_expiryDisclaimer =>
      'Son app le supprimera à l\'heure prévue, et la vôtre aussi.\nUn minuteur ne peut pas revenir sur ce qui a été lu — une capture d\'écran reste une capture d\'écran. C\'est une courtoisie entre vous deux, pas une garantie.';

  @override
  String get chat_timerOff => 'Désactivé';

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
  String get chat_timerButtonA11y => 'Minuteur de disparition';

  @override
  String get chat_composerA11y => 'Message';

  @override
  String get chat_sendA11y => 'Envoyer';

  @override
  String get chat_deliveryWaitingA11y =>
      'En attente. Sur votre téléphone uniquement.';

  @override
  String get chat_deliverySentA11y => 'Envoyé.';

  @override
  String get chat_deliveryDeliveredA11y => 'Distribué.';

  @override
  String get media_attachA11y => 'Ajouter une photo ou un fichier';

  @override
  String get media_pickPhoto => 'Photo';

  @override
  String get media_pickFile => 'Fichier';

  @override
  String get media_overCapError =>
      'Ça dépasse 5 Mo — la ligne transporte des documents, pas des archives. Essayez un fichier plus petit.';

  @override
  String get media_metadataStripNotice =>
      'Les photos sont nettoyées avant d\'être scellées — le lieu, l\'appareil et l\'heure sont retirés sur votre téléphone, avant le chiffrement.';

  @override
  String get media_compressionNote =>
      'Envoyées plus légères par défaut. La qualité d\'origine est à portée d\'un bouton.';

  @override
  String get media_originalQualityToggle => 'Qualité d\'origine';

  @override
  String get media_exportAction => 'Exporter';

  @override
  String get media_exportConfirm =>
      'Cela le copie hors de Nimna — vers le stockage de votre téléphone.';

  @override
  String get media_exportRollNote =>
      'Rien de ce que vous recevez ne touche votre pellicule. Ça reste dans Nimna jusqu\'à ce que vous choisissiez de l\'en sortir.';

  @override
  String get media_exportCancel => 'Revenir en arrière';

  @override
  String media_viewerReceivedTime(String time) {
    return 'Reçu le $time';
  }

  @override
  String get media_sendingA11y => 'Envoi en cours.';

  @override
  String get media_receivingA11y => 'Réception en cours.';

  @override
  String get media_documentA11y => 'Document.';

  @override
  String get media_imageA11y => 'Photo.';

  @override
  String get media_documentKindPdf => 'PDF';

  @override
  String get media_documentKindFile => 'Fichier';

  @override
  String media_sizeMegabytes(String size) {
    return '$size Mo';
  }

  @override
  String media_sizeKilobytes(String size) {
    return '$size Ko';
  }

  @override
  String media_documentMeta(String kind, String size) {
    return '$kind · $size';
  }

  @override
  String get knock_waitingTitle =>
      'Vous avez frappé. Si l\'autre décroche dans la minute qui suit, la ligne s\'ouvre.';

  @override
  String get knock_waitingCaption =>
      'Un seul coup suffit — il ne se répétera pas tout seul.';

  @override
  String get knock_noAnswer => 'Pas de réponse.';

  @override
  String get knock_knock => 'Frapper';

  @override
  String get knock_again => 'Frapper à nouveau';

  @override
  String get knock_staleHint =>
      'Pas de réponse depuis un moment. Si l\'autre a perdu son téléphone, cette ligne ne peut pas revenir — il faudrait vous associer à nouveau avec un nouveau code.';

  @override
  String knock_incomingKnocking(String label) {
    return '$label frappe.';
  }

  @override
  String get knock_pickUp => 'Décrocher';

  @override
  String get knock_ignore => 'Ignorer';

  @override
  String get push_toggleLabel => 'Me prévenir quand l\'autre frappe';

  @override
  String get push_tradeOff =>
      'Désactivé : rien de cette ligne ne passe jamais par Apple ou Google.';

  @override
  String get push_tradeOn =>
      'Activé : un coup peut réveiller ce téléphone via leur service de notifications, en portant deux mots — « Nouvelle activité » Pas de ligne, pas de nom, pas de message — et le relais oublie l\'adresse dès qu\'elle est utilisée.';

  @override
  String get screenshot_systemLinePeer =>
      'L\'autre personne a fait une capture d\'écran.';

  @override
  String get screenshot_systemLineOwn =>
      'Vous avez fait une capture d\'écran. L\'autre personne en a été informée.';

  @override
  String get screenshot_onboardingDisclosure =>
      'Nimna ne peut pas empêcher une capture d\'écran. Elle préviendra toujours l\'autre personne.\nElle ne remarque que ce qui se passe à l\'intérieur de l\'app — un second appareil photo pointé sur un écran est invisible pour n\'importe quel logiciel. Dit d\'emblée, pour que vous connaissiez tous les deux les conditions.';

  @override
  String get screenshot_onboardingAndroidCaveat =>
      'Sur Android 13 et versions antérieures, une capture d\'écran ne peut pas être remarquée ici — seuls Android 14 et plus récent, ainsi que l\'iPhone, peuvent prévenir l\'autre personne.';

  @override
  String get sensitive_veilCaption =>
      'Contenu sensible — touchez pour afficher.';

  @override
  String get sensitive_whisperQuestion =>
      'Cela ressemble à du contenu sensible — envoyer quand même ?';

  @override
  String get sensitive_whisperSendAnyway => 'Envoyer quand même';

  @override
  String get sensitive_whisperGoBack => 'Revenir en arrière';

  @override
  String get push_newActivityBody => 'Nouvelle activité';

  @override
  String get channelSettings_subtitle =>
      'Réglages de la ligne — ce téléphone uniquement';

  @override
  String get onboarding_whatItIsHeadline =>
      'Une ligne privée entre deux personnes.';

  @override
  String get onboarding_whatItIsBody =>
      'Pas de comptes. Pas de cloud. Les messages vivent sur vos deux téléphones, nulle part ailleurs.';

  @override
  String get onboarding_pairingHeadline =>
      'Associez-vous une seule fois, avec un code.';

  @override
  String get onboarding_pairingBody =>
      'Associez-vous une seule fois avec un code Nimna que vous partagez comme vous voulez — lu à voix haute, sur papier, ou sous forme du QR affiché juste à côté.\nEnsuite, le code disparaît pour de bon. La ligne est à vous.';

  @override
  String get onboarding_cannotSeeHeadline => 'Ce que nous ne pouvons pas voir';

  @override
  String get onboarding_cannotSeeBody =>
      'Nous ne pouvons pas lire vos messages. Nous ne pouvons pas non plus les récupérer.\nIl n\'y a rien à remettre, parce que rien n\'est conservé.';

  @override
  String get onboarding_cannotSeeRelayNote =>
      'Le relais voit bien les heures de connexion, les adresses IP et la taille des messages — jamais le contenu. Détails dans Réglages → Relais.';

  @override
  String get onboarding_next => 'Suivant';

  @override
  String get onboarding_skip => 'Passer';

  @override
  String get onboarding_start => 'Commencer';

  @override
  String knock_lapsesInSeconds(int seconds) {
    return 'Expire dans $seconds s';
  }

  @override
  String get settings_readReceiptsLabel => 'Accusés de lecture';

  @override
  String get settings_readReceiptsCaption =>
      'L\'autre verra « Vu » sous les messages que vous avez lus. Cette ligne uniquement.';

  @override
  String get settings_typingLabel => 'Indicateur de saisie';

  @override
  String get settings_typingCaption =>
      'L\'autre verra quand vous écrivez. Cette ligne uniquement.';

  @override
  String get session_readReceiptSeen => 'Vu';

  @override
  String get settings_rowDiagnostics => 'Partager les diagnostics';

  @override
  String get settings_rowDiagnosticsCaption =>
      'Uniquement des codes d\'événement et des horodatages — jamais vos messages. Rien ne quitte votre téléphone sans que vous l\'envoyiez.';

  @override
  String get diag_shareTitle => 'Diagnostics';

  @override
  String get diag_shareExplainer =>
      'C\'est un relevé technique de ce que l\'app a fait — des codes d\'événement et des horaires, rien de plus. Aucun message, aucun nom, aucun code, aucune adresse ne s\'y trouve, et il ne peut pas en contenir. Il reste sur votre téléphone, sauf si vous choisissez de le partager.';

  @override
  String get diag_shareAction => 'Partager le journal';

  @override
  String get diag_shareEmpty => 'Rien à partager pour l\'instant.';

  @override
  String get notifications_emptyBody =>
      'Les notifications s\'activent par ligne. Vous n\'en avez aucune pour l\'instant.';
}
