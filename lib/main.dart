import 'package:flutter/material.dart';

import 'app.dart';
import 'store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await Store.open();
  await store.sync(DateTime.now());
  runApp(PerpulApp(store: store));
}
