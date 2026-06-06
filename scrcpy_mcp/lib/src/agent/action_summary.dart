import 'response_parser.dart';

/// A compact one-line rendering of [action] for the INFO step-index log,
/// e.g. `Tap(897,939)`, `Swipe(499,702→499,263)`, `Wait(2 seconds)`.
String actionSummary(PhoneAction action) {
  String quote(String s) {
    const max = 20;
    final flat = s.replaceAll('\n', ' ');
    final clipped = flat.length > max ? '${flat.substring(0, max)}…' : flat;
    return '"$clipped"';
  }

  switch (action) {
    case FinishAction(:final message):
      return 'Finish(${quote(message)})';
    case DoAction():
      String coord(List<int>? p) => p == null ? '?' : '${p[0]},${p[1]}';
      switch (action.action) {
        case 'Tap':
        case 'Long Press':
        case 'Double Tap':
          return '${action.action}(${coord(action.element)})';
        case 'Swipe':
          return 'Swipe(${coord(action.start)}→${coord(action.end)})';
        case 'Type':
        case 'Type_Name':
          return '${action.action}(${quote(action.text ?? '')})';
        case 'Launch':
          return 'Launch(${action.app ?? '?'})';
        case 'Wait':
          return 'Wait(${action.duration ?? '?'})';
        default:
          // Back / Home / Interact / Take_over / Note / Call_API …
          return action.message == null
              ? action.action
              : '${action.action}(${quote(action.message!)})';
      }
  }
}
