import 'package:go_router/go_router.dart';

import 'habit_detail_page.dart';
import 'habit_form_page.dart';
import 'habit_urge_page.dart';
import 'habits_page.dart';

/// `/habits`, `/habits/new`, `/habits/:id`, `/habits/:id/edit`,
/// `/habits/:id/urge` — each page sits behind "Kunci Kebiasaan".
final List<GoRoute> habitRoutes = [
  GoRoute(path: '/habits', builder: (_, _) => const HabitsPage()),
  GoRoute(path: '/habits/new', builder: (_, _) => const HabitFormPage()),
  GoRoute(
    path: '/habits/:id',
    builder: (_, s) => HabitDetailPage(id: s.pathParameters['id']!),
  ),
  GoRoute(
    path: '/habits/:id/edit',
    builder: (_, s) => HabitFormPage(id: s.pathParameters['id']),
  ),
  GoRoute(
    path: '/habits/:id/urge',
    builder: (_, s) => HabitUrgePage(id: s.pathParameters['id']!),
  ),
];
