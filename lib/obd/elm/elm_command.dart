import 'dart:async';

import 'package:obdrive/obd/elm/elm_response.dart';

class ElmCommand {
  final String command;
  final Duration timeout;
  final int generationId;
  final Completer<ElmResponse> completer = Completer<ElmResponse>();

  ElmCommand({
    required this.command,
    required this.timeout,
    required this.generationId,
  });
}
