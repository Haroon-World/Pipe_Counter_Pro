import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings.dart';

class StorageService {
  static const _keyEngine = 'pref_engine';
  static const _keySensitivity = 'pref_sensitivity';
  static const _keyMinRadius = 'pref_min_radius';
  static const _keyMaxRadius = 'pref_max_radius';
  static const _keySolidityThreshold = 'pref_solidity_threshold';
  static const _keyOutlierFraction = 'pref_outlier_fraction';
  static const _keyModelPath = 'pref_model_path';
  static const _keyModelName = 'pref_model_name';

  static Future<AppSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final engineStr = prefs.getString(_keyEngine) ?? DetectionEngine.classicalCV.name;
    final engine = DetectionEngine.values.firstWhere(
      (e) => e.name == engineStr,
      orElse: () => DetectionEngine.classicalCV,
    );

    final sensitivity = prefs.getDouble(_keySensitivity) ?? 0.50;
    final minRadius = prefs.getDouble(_keyMinRadius) ?? 4.0;
    final maxRadius = prefs.getDouble(_keyMaxRadius) ?? 32.0;
    final solidityThreshold = prefs.getDouble(_keySolidityThreshold) ?? 0.85;
    final outlierFraction = prefs.getDouble(_keyOutlierFraction) ?? 0.12;
    final modelPath = prefs.getString(_keyModelPath);
    final modelName = prefs.getString(_keyModelName);

    return AppSettings(
      engine: engine,
      sensitivity: sensitivity,
      minRadius: minRadius,
      maxRadius: maxRadius,
      solidityThreshold: solidityThreshold,
      outlierFraction: outlierFraction,
      customModelPath: modelPath,
      customModelName: modelName,
    );
  }

  static Future<void> saveSettings(AppSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEngine, settings.engine.name);
    await prefs.setDouble(_keySensitivity, settings.sensitivity);
    await prefs.setDouble(_keyMinRadius, settings.minRadius);
    await prefs.setDouble(_keyMaxRadius, settings.maxRadius);
    await prefs.setDouble(_keySolidityThreshold, settings.solidityThreshold);
    await prefs.setDouble(_keyOutlierFraction, settings.outlierFraction);

    if (settings.customModelPath != null) {
      await prefs.setString(_keyModelPath, settings.customModelPath!);
    } else {
      await prefs.remove(_keyModelPath);
    }

    if (settings.customModelName != null) {
      await prefs.setString(_keyModelName, settings.customModelName!);
    } else {
      await prefs.remove(_keyModelName);
    }
  }
}
