import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'service.dart';

class ResourceStats {
  final double? cpuPercent;
  final double? ramUsedMb;
  final double? ramTotalMb;
  final double? diskUsedGb;
  final double? diskTotalGb;
  final String? error;

  const ResourceStats({
    this.cpuPercent,
    this.ramUsedMb,
    this.ramTotalMb,
    this.diskUsedGb,
    this.diskTotalGb,
    this.error,
  });

  //Izračunava postotak RAM-a iz apsolutnih vrijednosti
  double? get ramPercent =>
      (ramUsedMb != null && ramTotalMb != null && ramTotalMb! > 0)
      ? (ramUsedMb! / ramTotalMb!) * 100
      : null;

  //Izračunava postotak diska iz apsolutnih vrijednosti
  double? get diskPercent =>
      (diskUsedGb != null && diskTotalGb != null && diskTotalGb! > 0)
      ? (diskUsedGb! / diskTotalGb!) * 100
      : null;

  bool get hasData => error == null && cpuPercent != null;
}

class ResourceFetcher {
  //HTTP klijent koji ignorira SSL greške — Proxmox koristi self-signed certifikat
  static http.Client _insecureClient() {
    final ioClient = HttpClient();
    ioClient.badCertificateCallback = (cert, host, port) => true;
    ioClient.connectionTimeout = const Duration(seconds: 6);
    return IOClient(ioClient);
  }

  //Javna metoda koja poziva odgovarajući API ovisno o tipu servisa
  static Future<ResourceStats> fetchStats(Service service) async {
    try {
      switch (service.serviceType) {
        case ServiceType.proxmox:
          return await _fetchProxmox(service);
        case ServiceType.glances:
          return await _fetchGlances(service);
        default:
          return const ResourceStats(
            error: 'Tip praćenja resursa nije konfiguriran',
          );
      }
    } on SocketException catch (e) {
      return ResourceStats(error: 'Nema veze: ${e.message}');
    } on HttpException catch (e) {
      return ResourceStats(error: 'HTTP greška: ${e.message}');
    } catch (e) {
      return ResourceStats(error: 'Greška: $e');
    }
  }

  //Wake-on-LAN

  //Šalje WoL magic packet na broadcast adresu lokalne mreže
  //Magic packet = 6x 0xFF + MAC adresa ponovljena 16 puta (102 bajta ukupno)
  //Prihvaća formate: AA:BB:CC:DD:EE:FF, AA-BB-CC-DD-EE-FF ili AABBCCDDEEFF
  static Future<String?> sendWakeOnLan(String macAddress) async {
    try {
      final mac = macAddress.replaceAll(RegExp(r'[:\-\.]'), '').toUpperCase();
      if (mac.length != 12) return 'Neispravan format MAC adrese';

      final macBytes = <int>[];
      for (int i = 0; i < 12; i += 2) {
        macBytes.add(int.parse(mac.substring(i, i + 2), radix: 16));
      }

      final packet = <int>[
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        0xFF,
        ...List.generate(16, (_) => macBytes).expand((b) => b),
      ];

      //Direktni subnet broadcast za WoL
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      socket.send(packet, InternetAddress('192.168.1.255'), 9);
      socket.close();
      return null;
    } catch (e) {
      return 'Greška pri slanju WoL paketa: $e';
    }
  }

  //Proxmox

  //Router metoda — ako nema vmid-a prati cijeli node, inače traži VM ili LXC
  static Future<ResourceStats> _fetchProxmox(Service service) async {
    final config = service.parsedConfig;
    final node = config['node'] ?? 'pve';
    final vmid = config['vmid'] ?? '';

    if (vmid.isEmpty) return await _fetchProxmoxNode(service, node);

    //Prvo pokušava QEMU tip, pa LXC ako QEMU ne odgovori
    final vmResult = await _fetchProxmoxVmOrLxc(service, node, vmid, 'qemu');
    if (vmResult.error == null) return vmResult;
    return await _fetchProxmoxVmOrLxc(service, node, vmid, 'lxc');
  }

  //Određuje host i port za Proxmox API pozive
  //Kad je unesen VMID, service.host pokazuje na VM pa se koristi proxmox_host iz configJson
  static (String host, int port) _proxmoxApiTarget(Service service) {
    final config = service.parsedConfig;
    final proxmoxHost = config['proxmox_host'] ?? '';
    final host = proxmoxHost.isNotEmpty ? proxmoxHost : service.host;
    final port = service.port ?? 8006;
    return (host, port);
  }

  //Dohvaća CPU, RAM i disk cijelog Proxmox noda
  //Proxmox vraća CPU kao decimalu 0-1 pa se množi s 100
  static Future<ResourceStats> _fetchProxmoxNode(
    Service service,
    String node,
  ) async {
    final (host, port) = _proxmoxApiTarget(service);
    final uri = Uri.parse('https://$host:$port/api2/json/nodes/$node/status');
    final client = _insecureClient();
    try {
      final response = await client
          .get(uri, headers: _proxmoxHeaders(service.apiToken))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        return ResourceStats(
          error: 'Proxmox API greška: HTTP ${response.statusCode}',
        );
      }

      final data = (jsonDecode(response.body) as Map)['data'] as Map;
      final cpu = (data['cpu'] as num?)?.toDouble() ?? 0;

      //RAM može biti u 'memory' mapi ili direktno kao 'mem'/'maxmem' ovisno o verziji
      final memMap = data['memory'] as Map?;
      final ramUsed =
          ((memMap?['used'] ?? data['mem']) as num?)?.toDouble() ?? 0;
      final ramTotal =
          ((memMap?['total'] ?? data['maxmem']) as num?)?.toDouble() ?? 0;

      final rootfs = data['rootfs'] as Map?;
      final diskUsed = (rootfs?['used'] as num?)?.toDouble() ?? 0;
      final diskTotal = (rootfs?['total'] as num?)?.toDouble() ?? 0;

      return ResourceStats(
        cpuPercent: cpu * 100,
        ramUsedMb: ramUsed / (1024 * 1024),
        ramTotalMb: ramTotal / (1024 * 1024),
        diskUsedGb: diskUsed / (1024 * 1024 * 1024),
        diskTotalGb: diskTotal / (1024 * 1024 * 1024),
      );
    } finally {
      client.close();
    }
  }

  //Dohvaća statistike pojedinog VM-a ili LXC kontejnera
  //Parametar type je 'qemu' za VM ili 'lxc' za kontejner
  static Future<ResourceStats> _fetchProxmoxVmOrLxc(
    Service service,
    String node,
    String vmid,
    String type,
  ) async {
    final (host, port) = _proxmoxApiTarget(service);
    final uri = Uri.parse(
      'https://$host:$port/api2/json/nodes/$node/$type/$vmid/status/current',
    );
    final client = _insecureClient();
    try {
      final response = await client
          .get(uri, headers: _proxmoxHeaders(service.apiToken))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        return ResourceStats(
          error: 'Proxmox API greška: HTTP ${response.statusCode}',
        );
      }

      final data = (jsonDecode(response.body) as Map)['data'] as Map;
      final cpu = (data['cpu'] as num?)?.toDouble() ?? 0;
      final ramUsed = (data['mem'] as num?)?.toDouble() ?? 0;
      final ramTotal = (data['maxmem'] as num?)?.toDouble() ?? 0;
      final diskUsed = (data['disk'] as num?)?.toDouble() ?? 0;
      final diskTotal = (data['maxdisk'] as num?)?.toDouble() ?? 0;

      return ResourceStats(
        cpuPercent: cpu * 100,
        ramUsedMb: ramUsed / (1024 * 1024),
        ramTotalMb: ramTotal / (1024 * 1024),
        diskUsedGb: diskUsed / (1024 * 1024 * 1024),
        diskTotalGb: diskTotal / (1024 * 1024 * 1024),
      );
    } finally {
      client.close();
    }
  }

  //Šalje akciju (start/stop/reboot) na Proxmox node ili VM
  //Ako nema vmid-a akcija se šalje na cijeli node, inače na VM ili LXC
  static Future<String?> performVmAction(Service service, String action) async {
    final config = service.parsedConfig;
    final node = config['node'] ?? 'pve';
    final vmid = config['vmid'] ?? '';
    final (host, port) = _proxmoxApiTarget(service);
    final client = _insecureClient();

    try {
      if (vmid.isEmpty) {
        //Proxmox node — 'stop' se prevodi u 'shutdown' jer node ne prima 'stop'
        final nodeAction = action == 'stop' ? 'shutdown' : action;
        final uri = Uri.parse(
          'https://$host:$port/api2/json/nodes/$node/status',
        );
        final response = await client
            .post(
              uri,
              headers: {
                ...(_proxmoxHeaders(service.apiToken)),
                'Content-Type': 'application/json',
              },
              body: jsonEncode({'command': nodeAction}),
            )
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) return null;
        return 'Greška pri akciji: HTTP ${response.statusCode}';
      }

      //VM ili LXC — pokušava qemu pa lxc
      for (final type in ['qemu', 'lxc']) {
        final uri = Uri.parse(
          'https://$host:$port/api2/json/nodes/$node/$type/$vmid/status/$action',
        );
        final response = await client
            .post(uri, headers: _proxmoxHeaders(service.apiToken))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) return null;
      }
      return 'Greška pri izvođenju akcije';
    } catch (e) {
      return 'Greška: $e';
    } finally {
      client.close();
    }
  }

  //Gradi Authorization header za Proxmox API
  //Format: 'PVEAPIToken=USER@REALM!TOKENID=UUID'
  static Map<String, String> _proxmoxHeaders(String? token) {
    if (token == null || token.isEmpty) return {};
    return {'Authorization': 'PVEAPIToken=$token'};
  }

  //Docker

  //Router metoda — ako je odabran kontejner dohvaća njegove statistike, inače sistemske
  static Future<ResourceStats> _fetchGlances(Service service) async {
    final config = service.parsedConfig;
    final container = config['container'] ?? '';
    final portainerToken = config['portainer_token'] ?? '';

    if (container.isNotEmpty) {
      //Ako postoji Portainer token koristi Portainer API, inače Glances
      if (portainerToken.isNotEmpty) {
        return await _fetchPortainerContainer(
          service,
          container,
          portainerToken,
        );
      }
      return await _fetchGlancesContainer(service, container);
    }
    return await _fetchGlancesSystem(service);
  }

  //Dohvaća statistike cijelog sustava putem Glances REST API-a
  //Tri zahtjeva se šalju paralelno radi brzine — cpu, mem i fs
  static Future<ResourceStats> _fetchGlancesSystem(Service service) async {
    final base = 'http://${service.host}:61208/api/4';
    final client = http.Client();
    try {
      final results = await Future.wait([
        client.get(Uri.parse('$base/cpu')).timeout(const Duration(seconds: 8)),
        client.get(Uri.parse('$base/mem')).timeout(const Duration(seconds: 8)),
        client.get(Uri.parse('$base/fs')).timeout(const Duration(seconds: 8)),
      ]);

      if (results[0].statusCode != 200) {
        return ResourceStats(
          error: 'Glances API greška: HTTP ${results[0].statusCode}',
        );
      }

      final cpuData = jsonDecode(results[0].body) as Map;
      final memData = jsonDecode(results[1].body) as Map;
      final fsList = jsonDecode(results[2].body) as List;

      final cpu = (cpuData['total'] as num?)?.toDouble() ?? 0;
      final ramUsed = (memData['used'] as num?)?.toDouble() ?? 0;
      final ramTotal = (memData['total'] as num?)?.toDouble() ?? 0;

      double diskUsed = 0, diskTotal = 0;
      if (fsList.isNotEmpty) {
        final root =
            fsList.firstWhere(
                  (fs) => fs['mnt_point'] == '/',
                  orElse: () => fsList.first,
                )
                as Map;
        diskUsed = (root['used'] as num?)?.toDouble() ?? 0;
        diskTotal = (root['size'] as num?)?.toDouble() ?? 0;
      }

      return ResourceStats(
        cpuPercent: cpu,
        ramUsedMb: ramUsed / (1024 * 1024),
        ramTotalMb: ramTotal / (1024 * 1024),
        diskUsedGb: diskUsed / (1024 * 1024 * 1024),
        diskTotalGb: diskTotal / (1024 * 1024 * 1024),
      );
    } finally {
      client.close();
    }
  }

  //Dohvaća statistike pojedinog kontejnera putem Glances API-a
  //Disk nije dostupan na razini kontejnera pa ostaje null
  static Future<ResourceStats> _fetchGlancesContainer(
    Service service,
    String containerName,
  ) async {
    final base = 'http://${service.host}:61208/api/4';
    final client = http.Client();
    try {
      final response = await client
          .get(Uri.parse('$base/containers'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        return ResourceStats(
          error: 'Glances API greška: HTTP ${response.statusCode}',
        );
      }

      final containers = jsonDecode(response.body) as List;
      final match = containers.cast<Map?>().firstWhere(
        (c) => c?['name'] == containerName,
        orElse: () => null,
      );

      if (match == null) {
        return ResourceStats(error: 'Kontejner "$containerName" nije pronađen');
      }

      final cpuMap = match['cpu'] as Map?;
      final cpu = (cpuMap?['total'] as num?)?.toDouble() ?? 0;
      final memMap = match['memory'] as Map?;
      final ramUsed = (memMap?['usage'] as num?)?.toDouble() ?? 0;
      final ramTotal = (memMap?['limit'] as num?)?.toDouble() ?? 0;

      return ResourceStats(
        cpuPercent: cpu,
        ramUsedMb: ramUsed / (1024 * 1024),
        ramTotalMb: ramTotal / (1024 * 1024),
        diskUsedGb: null,
        diskTotalGb: null,
      );
    } finally {
      client.close();
    }
  }

  //Dohvaća statistike kontejnera putem Portainer REST API-a
  //Docker vraća kumulativne CPU vrijednosti pa se postotak izračunava kao delta
  static Future<ResourceStats> _fetchPortainerContainer(
    Service service,
    String containerName,
    String portainerToken,
  ) async {
    final client = http.Client();
    try {
      final response = await client
          .get(
            Uri.parse(
              'http://${service.host}:9000/api/endpoints/3/docker/containers/$containerName/stats?stream=false',
            ),
            headers: {'X-API-Key': portainerToken},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return ResourceStats(
          error: 'Portainer stats greška: HTTP ${response.statusCode}',
        );
      }

      final data = jsonDecode(response.body) as Map;

      final cpuStats = data['cpu_stats'] as Map?;
      final preCpuStats = data['precpu_stats'] as Map?;
      double cpuPercent = 0;
      if (cpuStats != null && preCpuStats != null) {
        final cpuUsage = cpuStats['cpu_usage'] as Map?;
        final preCpuUsage = preCpuStats['cpu_usage'] as Map?;
        final cpuDelta =
            ((cpuUsage?['total_usage'] as num?)?.toDouble() ?? 0) -
            ((preCpuUsage?['total_usage'] as num?)?.toDouble() ?? 0);
        final systemDelta =
            ((cpuStats['system_cpu_usage'] as num?)?.toDouble() ?? 0) -
            ((preCpuStats['system_cpu_usage'] as num?)?.toDouble() ?? 0);
        final numCpus =
            (cpuStats['online_cpus'] as num?)?.toDouble() ??
            ((cpuUsage?['percpu_usage'] as List?)?.length.toDouble() ?? 1);
        if (systemDelta > 0) {
          cpuPercent = (cpuDelta / systemDelta) * numCpus * 100;
        }
      }

      final memStats = data['memory_stats'] as Map?;
      final ramUsed = (memStats?['usage'] as num?)?.toDouble() ?? 0;
      final ramLimit = (memStats?['limit'] as num?)?.toDouble() ?? 0;

      return ResourceStats(
        cpuPercent: cpuPercent,
        ramUsedMb: ramUsed / (1024 * 1024),
        ramTotalMb: ramLimit / (1024 * 1024),
        diskUsedGb: null,
        diskTotalGb: null,
      );
    } catch (e) {
      return ResourceStats(error: 'Greška: $e');
    } finally {
      client.close();
    }
  }

  //Šalje akciju start/stop/restart na Docker kontejner putem Portainer API-a
  //Stop i restart imaju duži timeout jer čekaju da se kontejner uredno ugasi
  static Future<String?> performContainerAction(
    Service service,
    String containerName,
    String action,
  ) async {
    final config = service.parsedConfig;
    final portainerToken = config['portainer_token'] ?? '';
    if (portainerToken.isEmpty) return 'Portainer API token nije konfiguriran';

    final client = http.Client();
    try {
      final timeout = action == 'start'
          ? const Duration(seconds: 10)
          : const Duration(seconds: 35);

      final response = await client
          .post(
            Uri.parse(
              'http://${service.host}:9000/api/endpoints/3/docker/containers/$containerName/$action',
            ),
            headers: {'X-API-Key': portainerToken},
          )
          .timeout(timeout);

      if (response.statusCode == 204 || response.statusCode == 200) return null;
      return 'Greška pri akciji: HTTP ${response.statusCode}';
    } catch (e) {
      return 'Greška: $e';
    } finally {
      client.close();
    }
  }
}
