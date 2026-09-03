import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_settings.dart';
import '../services/storage_service.dart';

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings()) {
    _init();
  }

  Future<void> _init() async {
    final loaded = await StorageService.loadSettings();
    state = loaded;
  }

  Future<void> setEngine(DetectionEngine engine) async {
    state = state.copyWith(engine: engine);
    await StorageService.saveSettings(state);
  }

  Future<void> setSensitivity(double sensitivity) async {
    state = state.copyWith(sensitivity: sensitivity);
    await StorageService.saveSettings(state);
  }

  Future<void> setRadiusRange(double minRadius, double maxRadius) async {
    state = state.copyWith(minRadius: minRadius, maxRadius: maxRadius);
    await StorageService.saveSettings(state);
  }

  Future<void> setSolidityThreshold(double threshold) async {
    state = state.copyWith(solidityThreshold: threshold);
    await StorageService.saveSettings(state);
  }

  Future<void> setOutlierFraction(double fraction) async {
    state = state.copyWith(outlierFraction: fraction);
    await StorageService.saveSettings(state);
  }

  Future<void> setCustomModel(String path, String name) async {
    state = state.copyWith(
      customModelPath: path,
      customModelName: name,
    );
    await StorageService.saveSettings(state);
  }

  Future<void> clearCustomModel() async {
    state = state.copyWith(clearModel: true);
    await StorageService.saveSettings(state);
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});
