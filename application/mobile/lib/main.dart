import 'package:flutter/widgets.dart';

import 'src/app/app.dart';
import 'src/app/bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await bootstrapNimna();
  runApp(NimnaApp(services: services));
}
