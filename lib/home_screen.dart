import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'service_edit_screen.dart';
import 'service.dart';
import 'service_repository.dart';
import 'service_detail_screen.dart';
import 'settings_screen.dart';
import 'main.dart';

class HomeScreen extends StatefulWidget {
  final ServiceRepository repository;
  const HomeScreen({super.key, required this.repository});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Service>> _servicesFuture;

  //Mapa koja pamti dostupnost svakog servisa, ključ je ID servisa
  final Map<int, bool?> _reachability = {};
  Timer? _pingTimer;

  @override
  void initState() {
    super.initState();
    _servicesFuture = widget.repository.getAllServices();
    _startPinging();
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    super.dispose();
  }

  //Pokreće periodični ping svakih 5 sekundi za sve servise u listi
  void _startPinging() {
    _pingAll();
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pingAll());
  }

  Future<void> _pingAll() async {
    final services = await widget.repository.getAllServices();
    for (final service in services) {
      if (service.id == null) continue;
      _checkReachability(service);
    }
  }

  //TCP socket ping — ako se veza otvori servis je dostupan, inače nije
  Future<void> _checkReachability(Service service) async {
    try {
      final socket = await Socket.connect(
        service.host,
        service.port ?? 80,
        timeout: const Duration(seconds: 2),
      );
      socket.destroy();
      if (mounted) setState(() => _reachability[service.id!] = true);
    } catch (_) {
      if (mounted) setState(() => _reachability[service.id!] = false);
    }
  }

  void _loadServices() {
    final future = widget.repository.getAllServices();
    setState(() {
      _servicesFuture = future;
    });
    _pingAll();
  }

  void _openServiceDetails(Service service) async {
    await Navigator.of(context).pushNamed(
      ServiceDetailScreen.routeName,
      arguments: ServiceDetailArgs(serviceId: service.id!),
    );
    _loadServices();
  }

  void _openCreateService() async {
    await Navigator.of(context).pushNamed(
      ServiceEditScreen.routeName,
      arguments: ServiceEditArgs(existingService: null),
    );
    _loadServices();
  }

  void _openSettings() async {
    await Navigator.of(context).pushNamed(SettingsScreen.routeName);
    _loadServices();
  }

  //Zelena = dostupan, crvena = nedostupan, siva = još se provjerava
  Color _statusColor(int? serviceId) {
    if (serviceId == null) return Colors.grey;
    final reachable = _reachability[serviceId];
    if (reachable == null) return Colors.grey;
    return reachable ? Colors.green : Colors.red;
  }

  //Boja pozadine ikone ovisi o tipu servisa — Proxmox plava, Docker zelena, ostalo neutralno
  Color _iconBgColor(String serviceType, BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (serviceType) {
      case ServiceType.proxmox:
        return isDark ? const Color(0xFF1A3A5C) : const Color(0xFFBBDEFB);
      case ServiceType.glances:
        return isDark ? const Color(0xFF1A3A2C) : const Color(0xFFC8E6C9);
      default:
        return isDark ? const Color(0xFF1A2A3C) : const Color(0xFFE3F2FD);
    }
  }

  Color _iconColor(String serviceType, BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (serviceType) {
      case ServiceType.proxmox:
        return isDark ? AppColors.accent : AppColors.primary;
      case ServiceType.glances:
        return isDark ? Colors.green[300]! : Colors.green[700]!;
      default:
        return isDark ? AppColors.accent : AppColors.primaryDark;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Homelab Helper'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: IconButton(
              icon: const Icon(Icons.settings_rounded),
              onPressed: _openSettings,
              tooltip: 'Postavke',
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<Service>>(
        future: _servicesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(
              child: Text('Greška učitavanja servisa: ${snapshot.error}'),
            );
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            //Prazno stanje, poruka i ikona kad nema dodanih servisa
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.dns_outlined,
                    size: 64,
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nema dodanih servisa.',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.5),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Pritisnuti + za dodavanje prvog servisa.',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.35),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            );
          } else {
            final services = snapshot.data!;
            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: services.length,
              itemBuilder: (context, index) {
                final service = services[index];
                final iconKey = service.parsedConfig['icon'];

                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 5),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _openServiceDetails(service),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          //Ikona servisa s obojenom pozadinom ovisno o tipu
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: _iconBgColor(service.serviceType, context),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              serviceIconData(iconKey),
                              color: _iconColor(service.serviceType, context),
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          //Naziv servisa i tip kao podnaslov
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  service.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  ServiceType.label(service.serviceType),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface.withOpacity(0.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          //Statusno svjetlo, krug u boji ovisno o dostupnosti
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Icon(
                              Icons.circle,
                              color: _statusColor(service.id),
                              size: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          }
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreateService,
        tooltip: 'Dodaj servis',
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}
