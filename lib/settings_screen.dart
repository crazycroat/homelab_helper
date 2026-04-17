import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'service_repository.dart';

class SettingsScreen extends StatefulWidget {
  static const String routeName = '/settings';

  final ThemeMode currentThemeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final ServiceRepository repository;

  const SettingsScreen({
    super.key,
    required this.currentThemeMode,
    required this.onThemeModeChanged,
    required this.repository,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  //Kontrolira hoće li se tokeni uključiti u export
  bool _exportTokens = false;
  bool _isExporting = false;
  bool _isImporting = false;

  //Sprema backup JSON datoteku direktno u Downloads folder
  Future<void> _export() async {
    setState(() => _isExporting = true);
    try {
      final file = await widget.repository.exportServices(
        includeTokens: _exportTokens,
      );

      final fileName =
          'homelab_helper_backup_${DateTime.now().millisecondsSinceEpoch}.json';
      final destination = File('/storage/emulated/0/Download/$fileName');
      await file.copy(destination.path);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backup spremljen u Downloads/$fileName')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Greška pri exportu: $e')));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  //Otvara file picker, čita odabranu JSON datoteku i uvozi servise u bazu
  //Servisi koji već postoje (isti naziv i host) se preskače
  Future<void> _import() async {
    setState(() => _isImporting = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _isImporting = false);
        return;
      }

      final path = result.files.single.path;
      if (path == null) throw Exception('Čitanje datoteke neuspješno.');

      final content = await File(path).readAsString();
      final count = await widget.repository.importServices(content);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Uvezeno $count servisa')));
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Greška: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Greška pri importu: $e')));
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(title: const Text('Postavke')),
      body: ListView(
        children: [
          //Odabir teme
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              'Izgled',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ),
          RadioListTile<ThemeMode>(
            title: const Text('Prema sustavu'),
            secondary: const Icon(Icons.brightness_auto),
            value: ThemeMode.system,
            groupValue: widget.currentThemeMode,
            onChanged: (v) => widget.onThemeModeChanged(v!),
          ),
          RadioListTile<ThemeMode>(
            title: const Text('Svijetla tema'),
            secondary: const Icon(Icons.light_mode),
            value: ThemeMode.light,
            groupValue: widget.currentThemeMode,
            onChanged: (v) => widget.onThemeModeChanged(v!),
          ),
          RadioListTile<ThemeMode>(
            title: const Text('Tamna tema'),
            secondary: const Icon(Icons.dark_mode),
            value: ThemeMode.dark,
            groupValue: widget.currentThemeMode,
            onChanged: (v) => widget.onThemeModeChanged(v!),
          ),

          const Divider(height: 32),

          //Backup i restore
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Uvoz i izvoz servisa',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ),

          //Opcija za uključivanje tokena u export
          SwitchListTile(
            title: const Text('Uključiti API tokene u izvoz'),
            subtitle: const Text(
              'API tokeni biti će vidljivi u izvezenoj datoteci',
            ),
            secondary: Icon(Icons.vpn_key_rounded, color: primaryColor),
            value: _exportTokens,
            onChanged: (v) => setState(() => _exportTokens = v),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: ElevatedButton.icon(
              onPressed: _isExporting ? null : _export,
              icon: _isExporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.upload_rounded),
              label: Text(_isExporting ? 'Izvoz...' : 'Izvoz servisa'),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: ElevatedButton.icon(
              onPressed: _isImporting ? null : _import,
              icon: _isImporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.download_rounded),
              label: Text(_isImporting ? 'Uvoz...' : 'Uvoz servisa'),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
