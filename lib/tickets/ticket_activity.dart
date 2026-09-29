import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:schedule_rules/schedule_rules.dart';

import 'ticket_context.dart';
import 'ticket_gateway.dart';
import 'ticket_pages.dart';

/// A deliberately small, memory-only record of diagnostic actions.
///
/// Its API accepts labels and stable codes only. In particular, it has no API
/// that accepts form values or request bodies.
final class TicketActivityLog {
  TicketActivityLog({this.limit = 8}) : assert(limit > 0);

  final int limit;
  final List<String> _actions = [];

  void screenVisited(String screen) => _add('Screen: $screen');
  void rpcCalled(String name) => _add('RPC: $name');
  void refusalRecorded(String code) => _add('Refusal: $code');
  void rpcFailed(String name, int statusCode) =>
      _add('RPC error: $name (HTTP $statusCode)');
  void networkFailed(String name) => _add('RPC error: $name (network)');
  void clear() => _actions.clear();

  List<String> snapshot() => List.unmodifiable(_actions);

  void _add(String action) {
    if (_actions.lastOrNull == action) return;
    _actions.add(action);
    if (_actions.length > limit) _actions.removeAt(0);
  }
}

/// Observes RPC endpoint names and stable refusal codes without inspecting or
/// retaining request bodies, which may contain text a person typed.
final class TicketActivityHttpClient extends http.BaseClient {
  TicketActivityHttpClient(this._inner, this._actions);

  final http.Client _inner;
  final TicketActivityLog _actions;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final rpcName = _rpcName(request.url);
    if (rpcName == null) return _inner.send(request);

    _actions.rpcCalled(rpcName);
    try {
      final response = await _inner.send(request);
      if (response.statusCode < 400) return response;

      final bytes = await response.stream.toBytes();
      final refusalCode = _refusalCode(bytes);
      if (refusalCode != null) {
        _actions.refusalRecorded(refusalCode);
      } else {
        _actions.rpcFailed(rpcName, response.statusCode);
      }
      return http.StreamedResponse(
        Stream.value(bytes),
        response.statusCode,
        contentLength: bytes.length,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } catch (_) {
      _actions.networkFailed(rpcName);
      rethrow;
    }
  }

  @override
  void close() => _inner.close();

  String? _rpcName(Uri uri) {
    final segments = uri.pathSegments;
    final rpc = segments.indexOf('rpc');
    return rpc >= 0 && rpc + 1 < segments.length ? segments[rpc + 1] : null;
  }

  String? _refusalCode(List<int> bytes) {
    try {
      final json = jsonDecode(utf8.decode(bytes));
      final code = json is Map<String, dynamic> ? json['code'] : null;
      return code is String && RegExp(r'^P\d{4}$').hasMatch(code) ? code : null;
    } catch (_) {
      return null;
    }
  }
}

final class TicketLauncher {
  const TicketLauncher({required this.gateway, required this.actions});

  final TicketGateway gateway;
  final TicketActivityLog actions;

  Future<void> openRefusal(
    BuildContext context, {
    required Refusal refusal,
    required String screen,
    DateTime? month,
    VoidCallback? onAccessRejected,
  }) {
    actions
      ..screenVisited(screen)
      ..refusalRecorded(refusal.code);
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'Put in a ticket'),
        builder: (_) => PutInTicketPage(
          gateway: gateway,
          initialKind: TicketKind.problem,
          onAccessRejected: onAccessRejected,
          attachedContext: captureTicketContext(
            screen: screen,
            month: month,
            refusalCode: refusal.code,
            recentActions: actions.snapshot(),
          ),
        ),
      ),
    );
  }
}

class TicketLauncherScope extends InheritedWidget {
  const TicketLauncherScope({
    super.key,
    required this.launcher,
    required super.child,
  });

  final TicketLauncher launcher;

  static TicketLauncher? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<TicketLauncherScope>()
      ?.launcher;

  @override
  bool updateShouldNotify(TicketLauncherScope oldWidget) =>
      launcher != oldWidget.launcher;
}
