import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/youtube_api_client.dart';
import 'user_auth_provider.dart';

enum AuthPlatform { youtube, facebook }

final youtubeApiClientProvider = Provider((ref) => YouTubeApiClient());

class BroadcastChannelsState {
  const BroadcastChannelsState({
    this.googleConnected = false,
    this.metaConnected = false,
    this.channelName,
    this.busy = false,
    this.error,
  });
  final bool googleConnected;
  final bool metaConnected;
  final String? channelName;
  final bool busy;
  final String? error;
  bool get hasAnyChannel => googleConnected;
}

class BroadcastChannelsNotifier extends Notifier<BroadcastChannelsState> {
  bool _disposed = false;
  int _epoch = 0;
  @override
  BroadcastChannelsState build() {
    ref.watch(userAuthProvider.select((s) => s.currentUser?.id));
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      ++_epoch;
    });
    Future.microtask(refresh);
    return const BroadcastChannelsState();
  }

  Future<String> _token() async {
    final token = await ref.read(userSessionStoreProvider).readToken();
    if (token == null) throw StateError('Sign in first.');
    return token;
  }

  Future<void> refresh() async {
    final epoch = ++_epoch;
    try {
      final token = await ref.read(userSessionStoreProvider).readToken();
      if (token == null || _disposed || epoch != _epoch) return;
      final data = await ref
          .read(youtubeApiClientProvider)
          .request('GET', 'connection', token);
      if (_disposed || epoch != _epoch) return;
      state = BroadcastChannelsState(
        googleConnected: data['connected'] == true,
        channelName:
            (data['channel'] as Map<String, dynamic>?)?['channel_name']
                as String?,
      );
    } catch (_) {
      if (!_disposed && epoch == _epoch) {
        state = const BroadcastChannelsState(
          error: 'Could not refresh YouTube connection.',
        );
      }
    }
  }

  Future<void> signInWithGoogle() async {
    if (state.busy) return;
    final epoch = ++_epoch;
    state = const BroadcastChannelsState(busy: true);
    try {
      final data = await ref
          .read(youtubeApiClientProvider)
          .request('POST', 'connect', await _token());
      if (_disposed || epoch != _epoch) return;
      final uri = Uri.parse(data['authorizationUrl'] as String);
      if (uri.scheme != 'https' ||
          uri.host != 'accounts.google.com' ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Could not open Google sign-in.');
      }
      if (!_disposed && epoch == _epoch) state = const BroadcastChannelsState();
    } catch (error) {
      if (!_disposed && epoch == _epoch) {
        state = BroadcastChannelsState(error: error.toString());
      }
    }
  }

  Future<void> disconnectYouTube() async {
    if (state.busy) return;
    final epoch = ++_epoch;
    state = BroadcastChannelsState(
      googleConnected: state.googleConnected,
      channelName: state.channelName,
      busy: true,
    );
    try {
      await ref
          .read(youtubeApiClientProvider)
          .request('DELETE', 'connection', await _token());
      if (!_disposed && epoch == _epoch) state = const BroadcastChannelsState();
    } catch (error) {
      if (!_disposed && epoch == _epoch) {
        state = BroadcastChannelsState(
          googleConnected: state.googleConnected,
          channelName: state.channelName,
          error: error.toString(),
        );
      }
    }
  }
}

final broadcastChannelsProvider =
    NotifierProvider<BroadcastChannelsNotifier, BroadcastChannelsState>(
      BroadcastChannelsNotifier.new,
    );
