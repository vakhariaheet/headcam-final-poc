import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/secure_credential_store.dart';

final secureCredentialStoreProvider = Provider<SecureCredentialStore>((ref) {
  return SecureCredentialStore();
});
