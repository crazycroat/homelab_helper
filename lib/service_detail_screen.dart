import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';

import 'service_repository.dart';
import 'service.dart';
import 'service_edit_screen.dart';
import 'resource_fetcher.dart';

class ServiceDetailArgs {
  final int serviceId;
  ServiceDetailArgs({required this.serviceId});
}

class ServiceDetailScreen extends StatefulWidget {
  static const String routeName = '/service-detail';

  final ServiceRepository repository;
  final int serviceId;

  const ServiceDetailScreen({
    super.key,
    required this.repository,
    required this.serviceId,
  });

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> {
  //Učitani servis iz baze — null dok traje učitavanje
  Service? _service;

  //Prikazuje loading spinner dok se servis dohvaća iz baze
  bool _loading = true;

  //Poruka greške ako dohvat servisa ne uspije
  String? _error;

  //Posljednje dohvaćene statistike resursa (CPU/RAM/Disk)
  ResourceStats? _stats;

  //Prikazuje mali spinner u resource kartici dok traje dohvat
  bool _statsLoading = false;

  //Timer koji automatski osvježava resurse statistike svakih 30 sekundi
  Timer? _refreshTimer;

  //Null = još nije pingalo, true = dostupan, false = nedostupan
  bool? _isReachable;

  //Timer koji pinga servis svakih 10 sekundi i ažurira statusno svjetlo
  Timer? _pingTimer;

  //Blokira gumbe za akcije dok traje izvođenje start/stop/restart
  bool _isActionLoading = false;

  //Poziva se jednom pri kreaciji widgeta — pokreće učitavanje servisa
  @override
  void initState() {
    super.initState();
    _loadService();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _pingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadService() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final service = await widget.repository.getServiceById(widget.serviceId);
      if (service == null) {
        setState(() => _error = 'Servis nije pronađen.');
      } else {
        setState(() => _service = service);

        _pingTimer?.cancel();
        _checkReachability();
        _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
          _checkReachability();
        });

        //pokreće praćenje resursa samo za proxmox i glances tipove
        if (service.serviceType != ServiceType.generic) {
          _startMonitoring();
        }
      }
    } catch (e) {
      setState(() => _error = 'Greška: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  //Pokušava otvoriti TCP socket na host:port servisa
  Future<void> _checkReachability() async {
    if (_service == null) return;
    try {
      final socket = await Socket.connect(
        _service!.host,
        _service!.port ?? 80,
        timeout: const Duration(milliseconds: 500),
      );
      socket.destroy();
      if (mounted) setState(() => _isReachable = true);
    } catch (_) {
      if (mounted) setState(() => _isReachable = false);
    }
  }

  //Pokreće dohvat statistika odmah i postavlja timer za automatsko osvježavanje
  void _startMonitoring() {
    _fetchStats();
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _fetchStats();
    });
  }

  //Poziva ResourceFetcher koji odlučuje koji API koristiti
  Future<void> _fetchStats() async {
    if (_service == null) return;
    setState(() => _statsLoading = true);
    final stats = await ResourceFetcher.fetchStats(_service!);
    if (mounted) {
      setState(() {
        _stats = stats;
        _statsLoading = false;
      });
    }
  }

  //Getter koji određuje podržava li servis akcije upravljanja.
  //Glances mora imati unesen Portainer token, kontejner nije obavezan.
  //WoL se tretira kao akcija — ako je unesena MAC adresa, gumb za paljenje je dostupan.
  bool get _hasActionSupport {
    if (_service == null) return false;
    final config = _service!.parsedConfig;
    //Ako postoji MAC adresa, WoL je dostupan kao akcija paljenja
    if (config['mac_address']?.isNotEmpty == true) return true;
    if (_service!.serviceType == ServiceType.glances) {
      //Gumbi se prikazuju ako je unesen Portainer token — kontejner nije obavezan
      return config['portainer_token']?.isNotEmpty == true;
    }
    if (_service!.serviceType == ServiceType.proxmox) {
      //Proxmox node (bez vmid) podržava shutdown i reboot, VM podržava start/stop/reboot
      return true;
    }
    return false;
  }

  //Getter koji provjerava je li WoL dostupan za ovaj servis.
  //WoL se koristi za paljenje kad je servis ugašen i MAC adresa je unesena.
  bool get _hasWolSupport {
    if (_service == null) return false;
    final config = _service!.parsedConfig;
    return config['mac_address']?.isNotEmpty == true;
  }

  //Šalje akciju start/stop/restart/reboot na servis putem odgovarajućeg API-a.
  //Ako je servis ugašen i MAC adresa je unesena, šalje WoL paket umjesto API poziva.
  //Nakon uspješne akcije čeka 3 sekunde pa osvježava ping i statistike.
  //Vraća poruku greške putem SnackBar-a ako akcija ne uspije.
  Future<void> _performAction(String action) async {
    if (_service == null) return;
    setState(() => _isActionLoading = true);

    String? error;
    final config = _service!.parsedConfig;

    if (action == 'start' && _hasWolSupport) {
      //Ako je MAC unesena i servis je ugašen, koristi WoL za paljenje
      final mac = config['mac_address'] ?? '';
      error = await ResourceFetcher.sendWakeOnLan(mac);
    } else if (_service!.serviceType == ServiceType.glances) {
      final containerName = config['container'] ?? '';
      error = await ResourceFetcher.performContainerAction(
        _service!,
        containerName,
        action,
      );
    } else if (_service!.serviceType == ServiceType.proxmox) {
      error = await ResourceFetcher.performVmAction(_service!, action);
    }

    if (!mounted) return;

    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Akcija je uspješno izvršena.')),
      );
      //Čekamo 3 sekunde da servis ima vremena promijeniti stanje
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      await _checkReachability();
      await _fetchStats();
    }

    if (mounted) setState(() => _isActionLoading = false);
  }

  //otvara ServiceEditScreen
  void _editService() async {
    if (_service == null) return;
    await Navigator.of(context).pushNamed(
      ServiceEditScreen.routeName,
      arguments: ServiceEditArgs(existingService: _service),
    );
    _refreshTimer?.cancel();
    _pingTimer?.cancel();
    await _loadService();
  }

  //Prikazuje dijalog za potvrdu brisanja
  Future<void> _deleteService() async {
    if (_service == null || _service!.id == null) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Potvrda brisanja'),
            content: const Text(
              'Jeste li sigurni da želite obrisati ovaj servis?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Otkaži'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Obriši'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await widget.repository.deleteService(_service!.id!);
    if (!mounted) return;
    //pop() vraća na HomeScreen koji će osvježiti listu servisa
    Navigator.of(context).pop();
  }

  //Vraća boju statusnog svjetla na temelju ping rezultata.
  Color _statusColor() {
    if (_isReachable == null) return Colors.grey;
    return _isReachable! ? Colors.green : Colors.red;
  }

  //Vraća tekst statusa servisa
  String _statusLabel() {
    if (_isReachable == null) return 'Provjera...';
    return _isReachable! ? 'Online' : 'Offline';
  }

  //Gradi UI ekrana
  @override
  Widget build(BuildContext context) {
    final service = _service;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalji servisa'),
        actions: [
          IconButton(
            onPressed: _editService,
            icon: const Icon(Icons.edit_rounded),
          ),
          IconButton(
            onPressed: _deleteService,
            icon: const Icon(Icons.delete_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : service == null
          ? const Center(child: Text('Servis nije pronađen.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                //Header kartica — ikona, naziv i status servisa
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        //Ikona servisa
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(isDark ? 0.2 : 0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            serviceIconData(service.parsedConfig['icon']),
                            color: primaryColor,
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                service.name,
                                style: Theme.of(context).textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                ServiceType.label(service.serviceType),
                                style: TextStyle(
                                  color: primaryColor.withOpacity(0.7),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        //Status badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: _statusColor().withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _statusColor().withOpacity(0.4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.circle,
                                color: _statusColor(),
                                size: 8,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _statusLabel(),
                                style: TextStyle(
                                  color: _statusColor(),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                //Informacijska kartica — host i napomene
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    child: Column(
                      children: [
                        //Host informacija — prikazuje host:port ili samo host
                        ListTile(
                          leading: Icon(Icons.lan_rounded, color: primaryColor),
                          title: const Text(
                            'Host',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            service.port != null
                                ? '${service.host}:${service.port}'
                                : service.host,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        //Napomene se prikazuju samo ako postoje i nisu prazne
                        if (service.notes != null &&
                            service.notes!.trim().isNotEmpty) ...[
                          Divider(height: 1, indent: 16, endIndent: 16),
                          ListTile(
                            leading: Icon(
                              Icons.notes_rounded,
                              color: primaryColor,
                            ),
                            title: const Text(
                              'Napomene',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              service.notes!,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                //Resource kartica — prikazuje se samo za proxmox i docker
                if (service.serviceType != ServiceType.generic) ...[
                  const SizedBox(height: 12),
                  _ResourceCard(
                    stats: _stats,
                    loading: _statsLoading,
                    isReachable: _isReachable,
                    onRefresh: _fetchStats,
                  ),
                ],

                //Akcije
                const SizedBox(height: 20),
                Text(
                  'Akcije',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(height: 8),

                //Gumb za otvaranje web sučelja servisa u eksternom browseru
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final url = Uri.parse(
                        service.port != null
                            ? 'http://${service.host}:${service.port}/'
                            : 'http://${service.host}/',
                      );
                      try {
                        //LaunchMode.externalApplication otvara sistemski browser umjesto WebView unutar aplikacije
                        await launchUrl(
                          url,
                          mode: LaunchMode.externalApplication,
                        );
                      } catch (_) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Ne mogu otvoriti web sučelje.'),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.open_in_browser_rounded),
                    label: const Text('Posjeti web sučelje'),
                  ),
                ),

                //Gumbi za upravljanje servisom — prikazuju se samo za Docker kontejnere i Proxmox VMove.
                //Dok je _isReachable null (još pingamo), gumbi se ne prikazuju.
                //Kad je servis ugašen, prikazuje se samo gumb za paljenje.
                //Kad je servis upaljen, prikazuju se gumbi za gašenje i restart.
                if (_hasActionSupport && _isReachable != null) ...[
                  const SizedBox(height: 8),
                  if (_isReachable == false)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isActionLoading
                            ? null
                            : () => _performAction('start'),
                        icon: _isActionLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.play_arrow_rounded),
                        label: Text(
                          _isActionLoading ? 'Pokretanje...' : 'Pokreni',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[600],
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    )
                  else ...[
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isActionLoading
                                ? null
                                : () => _performAction('stop'),
                            icon: _isActionLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.stop_rounded),
                            label: const Text('Zaustavi'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red[600],
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isActionLoading
                                ? null
                                //Proxmox koristi 'reboot', Glances/Docker koristi 'restart'
                                : () => _performAction(
                                    service.serviceType == ServiceType.proxmox
                                        ? 'reboot'
                                        : 'restart',
                                  ),
                            icon: _isActionLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.restart_alt_rounded),
                            label: const Text('Restart'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange[700],
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
                const SizedBox(height: 16),
              ],
            ),
    );
  }
}

//Prikazuje CPU, RAM i Disk statistike kao progress barove.
class _ResourceCard extends StatelessWidget {
  final ResourceStats? stats;
  final bool loading;

  final bool? isReachable;

  final VoidCallback onRefresh;

  const _ResourceCard({
    required this.stats,
    required this.loading,
    required this.isReachable,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            //Header reda: naslov "Resursi" i refresh ikona/spinner
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.monitor_heart_rounded,
                      color: primaryColor,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Resursi',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: primaryColor,
                      ),
                    ),
                  ],
                ),
                //Prikazuje spinner dok traje dohvat, inače refresh ikonu
                loading
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: primaryColor,
                        ),
                      )
                    : IconButton(
                        icon: Icon(
                          Icons.refresh_rounded,
                          size: 20,
                          color: primaryColor,
                        ),
                        onPressed: onRefresh,
                        tooltip: 'Osvježi',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
              ],
            ),
            const SizedBox(height: 12),
            if (isReachable == false) ...[
              const Row(
                children: [
                  Icon(Icons.wifi_off_rounded, color: Colors.red, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Servis je nedostupan.',
                    style: TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ],
              ),
            ] else if (stats == null && !loading)
              const Text(
                'Dohvaćanje podataka...',
                style: TextStyle(color: Colors.grey),
              )
            else if (stats?.error != null)
              Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      stats!.error!,
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              )
            else if (stats != null) ...[
              //CPU, samo postotak, bez detalja MB/GB
              _StatRow(
                label: 'CPU',
                percent: stats!.cpuPercent,
                color: _barColor(stats!.cpuPercent),
              ),
              const SizedBox(height: 12),
              //RAM, postotak i detalj
              _StatRow(
                label: 'RAM',
                percent: stats!.ramPercent,
                color: _barColor(stats!.ramPercent),
                detail: _fmtRam(stats!.ramUsedMb, stats!.ramTotalMb),
              ),
              const SizedBox(height: 12),
              //Disk, postotak i detalj. Null za Docker kontejnere jer Glances ne izlaže disk podatke po kontejneru
              _StatRow(
                label: 'Disk',
                percent: stats!.diskPercent,
                color: _barColor(stats!.diskPercent),
                detail: _fmtDisk(stats!.diskUsedGb, stats!.diskTotalGb),
              ),
            ],
          ],
        ),
      ),
    );
  }

  //Određuje boju progress bara na temelju postotka iskorištenosti.
  Color _barColor(double? percent) {
    if (percent == null) return Colors.grey;
    if (percent >= 90) return Colors.red;
    if (percent >= 70) return Colors.orange;
    return Colors.green;
  }

  //Formatira RAM vrijednosti, automatski odabire MB ili GB prikaz. Ako je ukupni RAM >= 1024 MB, prikazuje u GB za čitljivost.
  String _fmtRam(double? used, double? total) {
    if (used == null || total == null) return '';
    if (total >= 1024) {
      return '${(used / 1024).toStringAsFixed(1)} / ${(total / 1024).toStringAsFixed(1)} GB';
    }
    return '${used.toStringAsFixed(0)} / ${total.toStringAsFixed(0)} MB';
  }

  //Formatira disk vrijednosti, uvijek u GB s jednom decimalom
  String _fmtDisk(double? used, double? total) {
    if (used == null || total == null) return '';
    return '${used.toStringAsFixed(1)} / ${total.toStringAsFixed(1)} GB';
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final double? percent;
  final Color color;
  final String? detail;

  const _StatRow({
    required this.label,
    required this.percent,
    required this.color,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final p = percent ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            Text(
              percent != null
                  ? '${p.toStringAsFixed(1)}%${detail != null ? '  ($detail)' : ''}'
                  : '—',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: p / 100,
            backgroundColor: color.withOpacity(0.15),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 10,
          ),
        ),
      ],
    );
  }
}
