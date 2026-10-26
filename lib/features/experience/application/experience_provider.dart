import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/offline_draft.dart';

enum ModuleSetupState { notStarted, inProgress, configured, skipped }

class OnboardingProgress {
  const OnboardingProgress({
    this.step = 0,
    this.completed = false,
    this.modules = const {},
  });
  final int step;
  final bool completed;
  final Map<String, ModuleSetupState> modules;

  OnboardingProgress copyWith({
    int? step,
    bool? completed,
    Map<String, ModuleSetupState>? modules,
  }) => OnboardingProgress(
    step: step ?? this.step,
    completed: completed ?? this.completed,
    modules: modules ?? this.modules,
  );
}

class ExperienceStore {
  static const _progressKey = 'l4.onboarding.progress';
  static const _draftsKey = 'l4.offline.drafts';

  Future<OnboardingProgress> loadProgress() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_progressKey);
    if (raw == null) return const OnboardingProgress();
    final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final modules = Map<String, dynamic>.from(json['modules'] as Map? ?? {});
    return OnboardingProgress(
      step: json['step'] as int? ?? 0,
      completed: json['completed'] as bool? ?? false,
      modules: modules.map(
        (key, value) =>
            MapEntry(key, ModuleSetupState.values.byName(value as String)),
      ),
    );
  }

  Future<void> saveProgress(OnboardingProgress progress) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _progressKey,
      jsonEncode({
        'step': progress.step,
        'completed': progress.completed,
        'modules': progress.modules.map(
          (key, value) => MapEntry(key, value.name),
        ),
      }),
    );
  }

  Future<List<OfflineDraft>> loadDrafts() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_draftsKey);
    if (raw == null) return const [];
    return (jsonDecode(raw) as List)
        .map(
          (item) =>
              OfflineDraft.fromJson(Map<String, Object?>.from(item as Map)),
        )
        .toList(growable: false);
  }

  Future<void> saveDrafts(List<OfflineDraft> drafts) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _draftsKey,
      jsonEncode(drafts.map((draft) => draft.toJson()).toList()),
    );
  }

  /// Privacy boundary: local household/member state is removed on logout or
  /// revocation. Language remains a device preference.
  Future<void> purgePrivateState() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_progressKey);
    await preferences.remove(_draftsKey);
  }
}

final experienceStoreProvider = Provider((ref) => ExperienceStore());

final onboardingProgressProvider = FutureProvider<OnboardingProgress>(
  (ref) => ref.watch(experienceStoreProvider).loadProgress(),
);

final offlineDraftsProvider = FutureProvider<List<OfflineDraft>>(
  (ref) => ref.watch(experienceStoreProvider).loadDrafts(),
);
