/// In-repo MIME derivation for the allowed attachment types (spec §5.1). No
/// `mime` package — a tiny const map over the picked extension keeps the
/// dependency set boring (SESSION-11 intake §2). Locale-independent.
library;

/// The attachment types Nimna accepts: images (compressed + EXIF-stripped) and
/// PDF documents. Anything else the picker rejects before this point.
const Map<String, String> allowedMimeByExtension = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'gif': 'image/gif',
  'pdf': 'application/pdf',
};

/// The extensions the file picker offers for the "file" attach path (documents
/// only — images use the photo path).
const List<String> documentExtensions = ['pdf'];

/// The extensions the photo picker offers.
const List<String> imageExtensions = ['jpg', 'jpeg', 'png', 'webp', 'gif'];

/// Derives a MIME from a filename/extension, or null if not an allowed type.
String? mimeForExtension(String? filenameOrExt) {
  if (filenameOrExt == null) {
    return null;
  }
  final dot = filenameOrExt.lastIndexOf('.');
  final ext = (dot >= 0 ? filenameOrExt.substring(dot + 1) : filenameOrExt)
      .toLowerCase();
  return allowedMimeByExtension[ext];
}

/// True for image MIMEs (the edge-to-edge bubble; the compress/strip pipeline).
bool isImageMime(String mime) => mime.startsWith('image/');

/// A safe file extension for a MIME — the export suggested-name suffix (no
/// original filename is ever persisted or transmitted, spec §5.1 privacy).
String extensionForMime(String mime) {
  switch (mime) {
    case 'image/jpeg':
      return 'jpg';
    case 'image/png':
      return 'png';
    case 'image/webp':
      return 'webp';
    case 'image/gif':
      return 'gif';
    case 'application/pdf':
      return 'pdf';
    default:
      return 'bin';
  }
}
