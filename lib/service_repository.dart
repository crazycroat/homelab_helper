import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'database.dart';
import 'service.dart';

//Sloj između UI-a i baze podataka — UI ne komunicira direktno s AppDatabase klasom
class ServiceRepository {
  final AppDatabase _database;

  ServiceRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  Future<List<Service>> getAllServices() => _database.getAllServices();

  Future<Service?> getServiceById(int id) => _database.getServiceById(id);

  Future<Service> addService(Service service) async {
    final id = await _database.insertService(service);
    return service.copyWith(id: id);
  }

  Future<void> updateService(Service service) async {
    if (service.id == null) throw ArgumentError('Service ID potreban');
    await _database.updateService(service);
  }

  Future<void> deleteService(int id) async {
    await _database.deleteService(id);
  }

  //Pretvara sve servise u JSON string i sprema ga u privremenu datoteku
  //includeTokens određuje hoće li se API tokeni uključiti u export
  //Vraća File koji se zatim dijeli kroz Android Share sheet
  Future<File> exportServices({required bool includeTokens}) async {
    final services = await getAllServices();

    final data = services.map((s) {
      final map = s.toMap();
      //Uvijek uklanjamo interni ID jer pri importu dobiva novi
      map.remove('id');
      if (!includeTokens) {
        //Uklanjamo tokene iz glavnog polja i iz configJson-a
        map.remove('api_token');
        if (map['config_json'] != null) {
          try {
            final config =
                jsonDecode(map['config_json'] as String)
                    as Map<String, dynamic>;
            config.remove('portainer_token');
            map['config_json'] = jsonEncode(config);
          } catch (_) {}
        }
      }
      return map;
    }).toList();

    final json = const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'includes_tokens': includeTokens,
      'services': data,
    });

    //Sprema u privremeni direktorij aplikacije
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/homelab_helper_backup.json');
    await file.writeAsString(json);
    return file;
  }

  //Čita JSON datoteku i ubacuje servise u bazu
  //Preskače servise koji već postoje (isti naziv i host) da izbjegne duplikate
  //Vraća broj uspješno uvezenih servisa
  Future<int> importServices(String jsonContent) async {
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(jsonContent) as Map<String, dynamic>;
    } catch (_) {
      throw FormatException('Datoteka nije ispravni JSON');
    }

    final servicesList = data['services'] as List?;
    if (servicesList == null)
      throw FormatException('Neispravan format backup datoteke');

    //Dohvati postojeće servise za provjeru duplikata
    final existing = await getAllServices();
    final existingKeys = existing
        .map((s) => '${s.name.toLowerCase()}_${s.host.toLowerCase()}')
        .toSet();

    int count = 0;
    for (final item in servicesList) {
      try {
        final map = Map<String, dynamic>.from(item as Map);
        map.remove('id');

        final service = Service.fromMap({
          'id': null,
          'status': 'pokrenuto',
          'port': null,
          'notes': null,
          'api_token': null,
          'config_json': null,
          ...map,
        });

        //Preskoči ako servis s istim imenom i hostom već postoji
        final key =
            '${service.name.toLowerCase()}_${service.host.toLowerCase()}';
        if (existingKeys.contains(key)) continue;

        await _database.insertService(service);
        existingKeys.add(key);
        count++;
      } catch (_) {
        continue;
      }
    }
    return count;
  }
}
