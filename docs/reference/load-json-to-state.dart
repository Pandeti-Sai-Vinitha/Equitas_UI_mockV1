import 'dart:convert';
import 'package:flutter/services.dart';

class AssetBundleRepository {
  static Future> loadJsonAsset(String fileName) async {
    final String path = 'assets/mock_data/$fileName';
    final String content = await rootBundle.loadString(path);
    return jsonDecode(content) as Map<String, dynamic>;
  }

  static Future<Persona> getSalariedPersona() async {
    final data = await loadJsonAsset('salaried_persona.json');
    return Persona.fromJson(data['data']['persona'], data['data']['financialSummary']);
  }

  static Future<Persona> getBusinessPersona() async {
    final data = await loadJsonAsset('business_persona.json');
    return Persona.fromJson(data['data']['persona'], data['data']['financialSummary']);
  }
}