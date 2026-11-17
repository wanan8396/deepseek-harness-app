import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/web/web_target.dart';
import 'compose_inbox.dart';

/// A request to open a webpage destination, optionally filling its composer.
class WebOpenRequest {
  WebOpenRequest(this.target, {this.compose});

  final DshWebTarget target;
  final ComposeRequest? compose;
}

/// The latest webpage request that its home has not taken yet.
class WebOpenController extends Notifier<WebOpenRequest?> {
  @override
  WebOpenRequest? build() => null;

  void request(DshWebTarget target, {ComposeRequest? compose}) => state = WebOpenRequest(target, compose: compose);

  /// A newer request remains pending when an earlier one is consumed.
  void taken(WebOpenRequest request) {
    if (identical(state, request)) state = null;
  }
}

final webOpenProvider = NotifierProvider<WebOpenController, WebOpenRequest?>(WebOpenController.new);
