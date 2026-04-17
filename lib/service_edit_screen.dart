import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'service_repository.dart';
import 'service.dart';

class ServiceEditArgs {
  final Service? existingService;
  ServiceEditArgs({this.existingService});
}

//StatefulWidget jer ekran ima stanje koje se mijenja
class ServiceEditScreen extends StatefulWidget {
  static const String routeName = '/service-edit';

  final ServiceRepository repository;

  //null = dodavanje novog servisa, nije null = uređivanje postojećeg
  final Service? existingService;

  const ServiceEditScreen({
    super.key,
    required this.repository,
    this.existingService,
  });

  @override
  State<ServiceEditScreen> createState() => _ServiceEditScreenState();
}

class _ServiceEditScreenState extends State<ServiceEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _notesController;
  late TextEditingController _apiTokenController;
  late TextEditingController _nodeController;
  late TextEditingController _vmidController;

  //Proxmox host za API pozive — koristi se samo kad je unesen VMID, jer service.host tada pokazuje na IP VM-a, a ne na Proxmox host
  late TextEditingController _proxmoxHostController;

  //Portainer API token za upravljanje Docker kontejnerima (start/stop/restart) — sprema se u configJson
  late TextEditingController _portainerTokenController;

  //MAC adresa uređaja — koristi se za Wake-on-LAN kad je servis ugašen
  late TextEditingController _macController;

  //Odabrana ikona servisa — sprema se u configJson kao 'icon'
  String? _selectedIcon;

  //Trenutno odabrani tip servisa u dropdownu (generic/proxmox/docker)
  late String _selectedType;

  bool _isSaving = false;

  //Getter koji određuje je li korisnik uređuje postojeći ili dodaje novi servis.
  bool get _isEditing => widget.existingService != null;

  //Kontrolira vidljivost Proxmox API tokena
  bool _obscureToken = true;

  //Kontrolira vidljivost Portainer API tokena
  bool _obscurePortainerToken = true;

  //Lista imena kontejnera dohvaćenih s Glances API-a
  List<String> _containers = [];

  //Trenutno odabrani kontejner u dropdownu (null = cijeli sustav)
  String? _selectedContainer;

  //Prikazuje loading spinner dok traje dohvat kontejnera
  bool _loadingContainers = false;

  //Poruka greške ako dohvat kontejnera ne uspije
  String? _containersError;

  //Pokreće se jednom kad se widget kreira.
  @override
  void initState() {
    super.initState();
    final s = widget.existingService;

    final config = s?.parsedConfig ?? {};

    _nameController = TextEditingController(text: s?.name ?? '');
    _hostController = TextEditingController(text: s?.host ?? '');
    _portController = TextEditingController(
      text: s?.port != null ? s!.port.toString() : '',
    );
    _notesController = TextEditingController(text: s?.notes ?? '');
    _apiTokenController = TextEditingController(text: s?.apiToken ?? '');
    _nodeController = TextEditingController(text: config['node'] ?? '');
    _vmidController = TextEditingController(text: config['vmid'] ?? '');
    _proxmoxHostController = TextEditingController(
      text: config['proxmox_host'] ?? '',
    );
    _portainerTokenController = TextEditingController(
      text: config['portainer_token'] ?? '',
    );
    _macController = TextEditingController(text: config['mac_address'] ?? '');
    _selectedIcon = config['icon'];
    _selectedType = s?.serviceType ?? ServiceType.generic;

    final savedContainer = config['container'];
    if (savedContainer != null && savedContainer.isNotEmpty) {
      _selectedContainer = savedContainer;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _notesController.dispose();
    _apiTokenController.dispose();
    _nodeController.dispose();
    _vmidController.dispose();
    _proxmoxHostController.dispose();
    _portainerTokenController.dispose();
    _macController.dispose();
    super.dispose();
  }

  //Dohvaća listu Docker kontejnera s Portainer API-a — vraća i pokrenute i ugašene
  //Portainer token je opcionalan; ako nije unesen, pokušava dohvat preko Glancesa koji vraća samo pokrenute
  Future<void> _fetchContainers() async {
    final host = _hostController.text.trim();
    if (host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unijeti IP adresu prije učitavanja.')),
      );
      return;
    }

    //Resetira stanje prije novog dohvata — čisti staru listu i grešku (dropdown ne smije imati value koji nije u items listi)
    setState(() {
      _loadingContainers = true;
      _containersError = null;
      _containers = [];
      _selectedContainer = null;
    });

    try {
      final portainerToken = _portainerTokenController.text.trim();

      if (portainerToken.isNotEmpty) {
        //Portainer API — vraća sve kontejnere uključujući ugašene
        final response = await http
            .get(
              Uri.parse(
                'http://$host:9000/api/endpoints/3/docker/containers/json?all=true',
              ),
              headers: {'X-API-Key': portainerToken},
            )
            .timeout(const Duration(seconds: 6));

        if (response.statusCode == 200) {
          final list = jsonDecode(response.body) as List;
          final names = list
              .map((c) {
                //Docker vraća Names kao listu
                final namesList = c['Names'] as List?;
                if (namesList == null || namesList.isEmpty) return '';
                return (namesList.first as String).replaceFirst('/', '');
              })
              .where((n) => n.isNotEmpty)
              .toList();
          setState(() => _containers = names);
        } else {
          setState(
            () => _containersError = 'Greška: HTTP ${response.statusCode}',
          );
        }
      } else {
        //Fallback na Glances ako Portainer token nije unesen — vraća samo pokrenute
        final response = await http
            .get(Uri.parse('http://$host:61208/api/4/containers'))
            .timeout(const Duration(seconds: 6));

        if (response.statusCode == 200) {
          //Glances vraća JSON array objekata — izvlači samo 'name' polje
          final list = jsonDecode(response.body) as List;
          final names = list
              .map((c) => c['name']?.toString() ?? '')
              .where((n) => n.isNotEmpty)
              .toList();
          setState(() => _containers = names);
        } else {
          setState(
            () => _containersError = 'Greška: HTTP ${response.statusCode}',
          );
        }
      }
    } catch (e) {
      //Hvata timeout, SocketException i ostale mrežne greške
      setState(() => _containersError = 'Spajanje na sustav neuspješno.');
    } finally {
      setState(() => _loadingContainers = false);
    }
  }

  //Gradi JSON string koji se sprema u config_json kolonu baze, format ovisi o tipu servisa:
  //glances: {"container": "homeassistant", "portainer_token": "ptr_...", "mac_address": "AA:BB:CC:DD:EE:FF", "icon": "dns"}
  //proxmox: {"node": "pve", "mac_address": "AA:BB:CC:DD:EE:FF", "icon": "server"} ili s vmid i proxmox_host za VM
  //generic: {"icon": "home"} ili null ako nema ništa odabrano
  String? _buildConfigJson() {
    if (_selectedType == ServiceType.glances) {
      final portainerToken = _portainerTokenController.text.trim();
      final mac = _macController.text.trim();

      //Gradi config s bilo kojom kombinacijom podataka koji su uneseni
      final Map<String, String> config = {};
      if (_selectedContainer != null && _selectedContainer!.isNotEmpty) {
        config['container'] = _selectedContainer!;
      }
      //Portainer token se sprema samo ako je unesen — opcionalno
      if (portainerToken.isNotEmpty) config['portainer_token'] = portainerToken;
      //MAC adresa se sprema samo ako je unesena — opcionalno
      if (mac.isNotEmpty) config['mac_address'] = mac;
      //Ikona se sprema ako je odabrana
      if (_selectedIcon != null) config['icon'] = _selectedIcon!;

      //Spremi config ako ima barem jedan podatak, inače null
      if (config.isEmpty) return null;
      return jsonEncode(config);
    }
    if (_selectedType == ServiceType.proxmox) {
      final vmid = _vmidController.text.trim();
      final proxmoxHost = _proxmoxHostController.text.trim();
      final mac = _macController.text.trim();
      return jsonEncode({
        'node': _nodeController.text.trim(),
        if (vmid.isNotEmpty) 'vmid': vmid,
        if (vmid.isNotEmpty && proxmoxHost.isNotEmpty)
          'proxmox_host': proxmoxHost,
        //MAC adresa se sprema samo ako je unesena — opcionalno
        if (mac.isNotEmpty) 'mac_address': mac,
        //Ikona se sprema ako je odabrana
        if (_selectedIcon != null) 'icon': _selectedIcon!,
      });
    }
    //Generic — spremi samo ako je odabrana ikona
    if (_selectedIcon != null) return jsonEncode({'icon': _selectedIcon!});
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    //Port parsira kao nullable int — prazno polje = null, broj = int
    final int? port = _portController.text.trim().isEmpty
        ? null
        : int.tryParse(_portController.text.trim());

    final service = Service(
      id: widget.existingService?.id,
      name: _nameController.text.trim(),
      host: _hostController.text.trim(),
      port: port,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      serviceType: _selectedType,
      apiToken: _apiTokenController.text.trim().isEmpty
          ? null
          : _apiTokenController.text.trim(),
      configJson: _buildConfigJson(),
    );

    try {
      if (_isEditing) {
        await widget.repository.updateService(service);
      } else {
        await widget.repository.addService(service);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Greška pri spremanju: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  //getteri za čitljiviji kod u build metodi
  bool get _isProxmox => _selectedType == ServiceType.proxmox;
  bool get _isGlances => _selectedType == ServiceType.glances;

  //getter koji prati je li VMID polje popunjeno, koristi se za uvjetno prikazivanje Proxmox host IP polja
  bool get _hasVmid => _vmidController.text.trim().isNotEmpty;

  //Gradi listu opcija za dropdown kontejnera
  //Koristi Set da garantira jedinstvenost, sprječava duplikate koji bi nastali kad je _selectedContainer već u _containers listi.
  List<DropdownMenuItem<String>> _buildContainerItems() {
    final items = <DropdownMenuItem<String>>[
      //Prva opcija uvijek je "Cijeli sustav" s null vrijednošću
      const DropdownMenuItem<String>(value: null, child: Text('Cijeli sustav')),
    ];
    final allNames = {
      if (_selectedContainer != null) _selectedContainer!,
      ..._containers,
    }.toList();
    for (final name in allNames) {
      items.add(DropdownMenuItem(value: name, child: Text(name)));
    }
    return items;
  }

  //Gradi widget za odabir ikone servisa — prikazuje grid od dostupnih ikona
  Widget _buildIconPicker(Color primaryColor) {
    return DropdownButtonFormField<String>(
      value: _selectedIcon,
      decoration: InputDecoration(
        labelText: 'Ikona servisa',
        prefixIcon: Icon(serviceIconData(_selectedIcon), color: primaryColor),
      ),
      items: kServiceIcons.entries.map((entry) {
        return DropdownMenuItem<String>(
          value: entry.key,
          child: Row(
            children: [
              Icon(entry.value, size: 20, color: primaryColor),
              const SizedBox(width: 10),
              Text(kServiceIconLabels[entry.key] ?? entry.key),
            ],
          ),
        );
      }).toList(),
      onChanged: (v) => setState(() {
        _selectedIcon = v;
      }),
      hint: const Text('Odabrati ikonu'),
    );
  }

  //Gradi UI ekrana. Poziva se svaki put kad setState() promijeni stanje
  @override
  Widget build(BuildContext context) {
    final title = _isEditing ? 'Uredi servis' : 'Dodaj servis';
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      //sprječava dvostruko slanje forme ili navigaciju dok traje spremanje
      body: AbsorbPointer(
        absorbing: _isSaving,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: ListView(
              clipBehavior: Clip.none,
              children: [
                //Odabir ikone servisa — prikazuje se na vrhu forme
                _buildIconPicker(primaryColor),

                const SizedBox(height: 20),

                //Sekcija naslov — Osnovne informacije
                Text(
                  'Informacije o servisu',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(height: 10),

                //Osnovne informacije o servisu
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Naziv servisa',
                    prefixIcon: Icon(Icons.label_rounded),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Unijeti naziv.' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _hostController,
                  decoration: const InputDecoration(
                    labelText: 'IP adresa',
                    prefixIcon: Icon(Icons.lan_rounded),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Unijeti IP adresu.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _portController,
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    prefixIcon: Icon(Icons.numbers_rounded),
                    helperText: 'Ostaviti prazno ako servis nema port.',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    if (int.tryParse(v.trim()) == null) {
                      return 'Unijeti ispravan broj.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Napomene',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                  maxLines: 3,
                ),

                //Odabir tipa praćenja resursa
                const SizedBox(height: 24),
                Text(
                  'Praćenje resursa',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Tip servisa',
                    prefixIcon: Icon(Icons.category_rounded),
                  ),
                  //ServiceType.all vraća generic, proxmox, docker
                  items: ServiceType.all
                      .map(
                        (t) => DropdownMenuItem(
                          value: t,
                          child: Text(ServiceType.label(t)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      //Resetira container stanje pri promjeni tipa da ne ostanu podaci od prethodnog odabira
                      setState(() {
                        _selectedType = v;
                        _selectedContainer = null;
                        _containers = [];
                        _containersError = null;
                      });
                    }
                  },
                ),

                //Docker praćenje preko Glances aplikacije
                if (_isGlances) ...[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _selectedContainer,
                          decoration: const InputDecoration(
                            labelText: 'Kontejner (opcionalno)',
                            helperText: 'Ostaviti prazno za cijeli sustav.',
                            prefixIcon: Icon(Icons.inventory_2_rounded),
                          ),
                          items: _buildContainerItems(),
                          onChanged: (v) =>
                              setState(() => _selectedContainer = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        //Uvjetno prikazuje spinner ili refresh ikonu
                        child: _loadingContainers
                            ? const SizedBox(
                                width: 40,
                                height: 40,
                                child: Padding(
                                  padding: EdgeInsets.all(8),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : IconButton(
                                icon: const Icon(Icons.refresh_rounded),
                                tooltip: 'Učitati kontejnere',
                                onPressed: _fetchContainers,
                              ),
                      ),
                    ],
                  ),
                  //Prikazuje se samo ako postoji poruka greške
                  if (_containersError != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _containersError!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ],
                  //Portainer API token — opcionalan, potreban za start/stop/restart kontejnera
                  //Bez tokena praćenje resursa i dalje radi, samo akcije nisu dostupne
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _portainerTokenController,
                    obscureText: _obscurePortainerToken,
                    decoration: InputDecoration(
                      labelText: 'Portainer API token (opcionalno)',
                      prefixIcon: const Icon(Icons.vpn_key_rounded),
                      helperText:
                          'Potreban za pokretanje i zaustavljanje kontejnera.',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePortainerToken
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                        ),
                        onPressed: () => setState(
                          () =>
                              _obscurePortainerToken = !_obscurePortainerToken,
                        ),
                      ),
                    ),
                  ),
                  //MAC adresa za Wake-on-LAN — koristi se za paljenje cijelog CasaOS sustava
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _macController,
                    decoration: const InputDecoration(
                      labelText: 'MAC adresa (opcionalno)',
                      prefixIcon: Icon(Icons.power_settings_new_rounded),
                      helperText: 'Potrebna za Wake-on-LAN paljenje sustava.',
                    ),
                  ),
                ],

                //Proxmox praćenje resursa preko REST API-a
                if (_isProxmox) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _apiTokenController,
                    //obscureText skriva znakove kao kod unosa lozinke
                    obscureText: _obscureToken,
                    decoration: InputDecoration(
                      labelText: 'Proxmox API Token',
                      prefixIcon: const Icon(Icons.vpn_key_rounded),
                      //Ikona za toggle vidljivosti polja
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureToken
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                        ),
                        onPressed: () =>
                            setState(() => _obscureToken = !_obscureToken),
                      ),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Unijeti API token.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nodeController,
                    decoration: const InputDecoration(
                      labelText: 'Naziv noda',
                      prefixIcon: Icon(Icons.dns_rounded),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Unijeti naziv noda.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  // onChanged poziva setState() pri svakom unosu znaka
                  // ovo triggera rebuild koji provjerava _hasVmid getter i uvjetno prikazuje/skriva Proxmox host IP polje ispod
                  TextFormField(
                    controller: _vmidController,
                    decoration: const InputDecoration(
                      labelText: 'VM/LXC ID (opcionalno)',
                      prefixIcon: Icon(Icons.computer_rounded),
                      helperText: 'Ostaviti prazno za praćenje cijelog noda.',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                  //Proxmox host IP polje — vidljivo samo kad je unesen VMID
                  if (_hasVmid) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _proxmoxHostController,
                      decoration: const InputDecoration(
                        labelText: 'Proxmox host IP',
                        hintText: '192.168.1.200',
                        prefixIcon: Icon(Icons.lan_rounded),
                        helperText:
                            'IP adresa Proxmox hosta za dohvat resursa VM-a.',
                      ),
                      keyboardType: TextInputType.text,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Unijeti IP Proxmox hosta.'
                          : null,
                    ),
                  ],
                  //MAC adresa za Wake-on-LAN — koristi se za paljenje Proxmox noda ili VM-a
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _macController,
                    decoration: const InputDecoration(
                      labelText: 'MAC adresa (opcionalno)',
                      prefixIcon: Icon(Icons.power_settings_new_rounded),
                      helperText: 'Potrebna za Wake-on-LAN paljenje.',
                    ),
                  ),
                ],

                const SizedBox(height: 28),
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _save,
                  //Uvjetno prikazuje spinner ili save ikonu
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(_isSaving ? 'Spremanje...' : 'Spremi'),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
