import 'dart:convert';
import 'package:flutter/material.dart';

class ServiceType {
  static const String generic = 'generic';
  static const String proxmox = 'proxmox';
  static const String glances = 'glances';

  static String label(String type) {
    switch (type) {
      case proxmox:
        return 'Proxmox';
      case glances:
        return 'Docker';
      default:
        return 'Generički servis';
    }
  }

  static List<String> get all => [generic, proxmox, glances];
}

class Service {
  final int? id;
  final String name;
  final String host;
  final int? port;
  final String status;
  final String? notes;
  final String serviceType;
  final String? apiToken;
  final String? configJson;

  Service({
    this.id,
    required this.name,
    required this.host,
    this.port,
    this.status = 'pokrenuto',
    this.notes,
    this.serviceType = ServiceType.generic,
    this.apiToken,
    this.configJson,
  });

  //Parsira configJson string iz baze u Map<String, String>
  //Npr. '{"node":"pve","vmid":"100"}' postaje {'node': 'pve', 'vmid': '100'}
  Map<String, String> get parsedConfig {
    if (configJson == null || configJson!.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(configJson!) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  Service copyWith({
    int? id,
    String? name,
    String? host,
    int? port,
    String? status,
    String? notes,
    String? serviceType,
    String? apiToken,
    String? configJson,
  }) {
    return Service(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      serviceType: serviceType ?? this.serviceType,
      apiToken: apiToken ?? this.apiToken,
      configJson: configJson ?? this.configJson,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'status': status,
    'notes': notes,
    'service_type': serviceType,
    'api_token': apiToken,
    'config_json': configJson,
  };

  factory Service.fromMap(Map<String, dynamic> map) => Service(
    id: map['id'] as int?,
    name: map['name'] as String,
    host: map['host'] as String,
    port: map['port'] as int?,
    status: map['status'] as String,
    notes: map['notes'] as String?,
    serviceType: (map['service_type'] as String?) ?? ServiceType.generic,
    apiToken: map['api_token'] as String?,
    configJson: map['config_json'] as String?,
  );
}

//Mapa dostupnih ikona — ključ se sprema u configJson kao 'icon'
const Map<String, IconData> kServiceIcons = {
  'dns': Icons.dns_rounded,
  'router': Icons.router_rounded,
  'home': Icons.home_rounded,
  'cloud': Icons.cloud_rounded,
  'shield': Icons.shield_rounded,
  'speed': Icons.speed_rounded,
  'storage': Icons.storage_rounded,
  'tv': Icons.tv_rounded,
  'computer': Icons.computer_rounded,
  'lan': Icons.lan_rounded,
  'hub': Icons.device_hub_rounded,
  'monitoring': Icons.monitor_heart_rounded,
};

//Labeli za svaku ikonu koji se prikazuju u padajućem izborniku
const Map<String, String> kServiceIconLabels = {
  'dns': 'Server',
  'router': 'Router',
  'home': 'Dom',
  'cloud': 'Cloud',
  'shield': 'Firewall',
  'speed': 'Brzina',
  'storage': 'Disk',
  'tv': 'Media',
  'computer': 'PC',
  'lan': 'LAN',
  'hub': 'Hub',
  'monitoring': 'Monitor',
};

//Vraća IconData za zadani ključ, a ako ključ ne postoji vraća dns ikonu kao fallback
IconData serviceIconData(String? key) {
  if (key == null) return Icons.dns_rounded;
  return kServiceIcons[key] ?? Icons.dns_rounded;
}
