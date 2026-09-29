import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/channel_connection_store.dart';

enum AuthPlatform { youtube, facebook }

final channelConnectionStoreProvider = Provider<ChannelConnectionStore>(
  (ref) => ChannelConnectionStore(),
);

class BroadcastChannelsState {
  const BroadcastChannelsState({
    this.googleConnected = false,
    this.metaConnected = false,
  });

  final bool googleConnected;
  final bool metaConnected;

  bool get hasAnyChannel => googleConnected || metaConnected;

  BroadcastChannelsState copyWith({
    bool? googleConnected,
    bool? metaConnected,
  }) => BroadcastChannelsState(
    googleConnected: googleConnected ?? this.googleConnected,
    metaConnected: metaConnected ?? this.metaConnected,
  );
}

/// Broadcast destination channels: "Sign in with Google (YouTube Data API
/// v3 live scope)" and "Meta OAuth (Facebook Pages API)". Stubbed here —
/// real OAuth needs API credentials this environment doesn't have, so
/// connecting a channel just flips local state after a simulated delay —
/// but that state is persisted per account ([ChannelConnectionStore]) so
/// it survives app restarts: connecting a channel is a one-time, user-level
/// action, not something repeated before every broadcast.
///
/// Not to be confused with real UmpireHat account auth — see
/// state/user_auth_provider.dart.
class BroadcastChannelsNotifier extends Notifier<BroadcastChannelsState> {
  late final ChannelConnectionStore _store = ref.read(
    channelConnectionStoreProvider,
  );

  @override
  BroadcastChannelsState build() {
    Future.microtask(_loadPersisted);
    return const BroadcastChannelsState();
  }

  Future<void> _loadPersisted() async {
    final saved = await _store.load();
    state = BroadcastChannelsState(
      googleConnected: saved.google,
      metaConnected: saved.meta,
    );
  }

  Future<void> signInWithGoogle() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    state = state.copyWith(googleConnected: true);
    await _store.setGoogleConnected(true);
  }

  Future<void> signInWithMeta() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    state = state.copyWith(metaConnected: true);
    await _store.setMetaConnected(true);
  }
}

final broadcastChannelsProvider =
    NotifierProvider<BroadcastChannelsNotifier, BroadcastChannelsState>(
      BroadcastChannelsNotifier.new,
    );
