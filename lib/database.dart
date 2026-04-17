import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'service.dart';

class AppDatabase {
  AppDatabase._internal();
  static final AppDatabase instance = AppDatabase._internal();
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase('homelab_helper.db');
    return _database!;
  }

  Future<Database> _initDatabase(String fileName) async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, fileName);
    return await openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  //Kreira tablicu pri prvom pokretanju aplikacije
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE services (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        host TEXT NOT NULL,
        port INTEGER,
        status TEXT NOT NULL DEFAULT 'pokrenuto',
        notes TEXT,
        service_type TEXT NOT NULL DEFAULT 'generic',
        api_token TEXT,
        config_json TEXT
      )
    ''');
  }

  //Migracije između verzija sheme baze podataka
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      //v2 dodaje podršku za praćenje resursa
      await db.execute(
        "ALTER TABLE services ADD COLUMN service_type TEXT NOT NULL DEFAULT 'generic'",
      );
      await db.execute('ALTER TABLE services ADD COLUMN api_token TEXT');
      await db.execute('ALTER TABLE services ADD COLUMN config_json TEXT');
    }
    if (oldVersion < 3) {
      //v3 mijenja port kolonu iz NOT NULL u nullable
      //SQLite ne podržava ALTER COLUMN pa se tablica rekreira
      await db.execute('''
        CREATE TABLE services_new (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          host TEXT NOT NULL,
          port INTEGER,
          status TEXT NOT NULL DEFAULT 'pokrenuto',
          notes TEXT,
          service_type TEXT NOT NULL DEFAULT 'generic',
          api_token TEXT,
          config_json TEXT
        )
      ''');
      await db.execute('''
        INSERT INTO services_new
        SELECT id, name, host, port, status, notes, service_type, api_token, config_json
        FROM services
      ''');
      await db.execute('DROP TABLE services');
      await db.execute('ALTER TABLE services_new RENAME TO services');
    }
  }

  Future<int> insertService(Service service) async {
    final db = await database;
    return await db.insert(
      'services',
      service.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Service>> getAllServices() async {
    final db = await database;
    final maps = await db.query('services', orderBy: 'name ASC');
    return maps.map((m) => Service.fromMap(m)).toList();
  }

  Future<Service?> getServiceById(int id) async {
    final db = await database;
    final maps = await db.query(
      'services',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Service.fromMap(maps.first);
  }

  Future<int> updateService(Service service) async {
    final db = await database;
    return await db.update(
      'services',
      service.toMap(),
      where: 'id = ?',
      whereArgs: [service.id],
    );
  }

  Future<int> deleteService(int id) async {
    final db = await database;
    return await db.delete('services', where: 'id = ?', whereArgs: [id]);
  }
}
