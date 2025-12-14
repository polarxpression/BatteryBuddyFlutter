import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart'; // Import Font Awesome
import 'firebase_options.dart';

// -----------------------------------------------------------------------------
// 1. MODELS
// The BatteryType enum has been removed to allow dynamic type selection from Firestore.
// -----------------------------------------------------------------------------

class BatteryItem {
  final String id;
  String brand;
  String model;
  String type; // Now a String fetched from Firebase categories
  String barcode;
  String packaging;
  int quantity;
  int minStockThreshold;
  String location;

  BatteryItem({
    required this.id,
    required this.brand,
    required this.model,
    required this.type,
    this.barcode = '',
    this.packaging = 'Unit',
    required this.quantity,
    this.minStockThreshold = 5,
    required this.location,
  });

  // Convert to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'brand': brand,
      'model': model,
      'type': type,
      'barcode': barcode,
      'packaging': packaging,
      'quantity': quantity,
      'minStockThreshold': minStockThreshold,
      'location': location,
    };
  }

  // Create from Firestore Map
  factory BatteryItem.fromMap(String id, Map<String, dynamic> map) {
    return BatteryItem(
      id: id,
      brand: map['brand'] ?? '',
      model: map['model'] ?? '',
      // The type is now stored and retrieved as a simple string
      type: map['type'] ?? 'Other',
      barcode: map['barcode'] ?? '',
      packaging: map['packaging'] ?? 'Unit',
      quantity: map['quantity'] ?? 0,
      minStockThreshold: map['minStockThreshold'] ?? 5,
      location: map['location'] ?? '',
    );
  }

  bool get isLowStock => quantity <= minStockThreshold;
}

// -----------------------------------------------------------------------------
// 2. STATE MANAGEMENT (PROVIDER)
// -----------------------------------------------------------------------------

class InventoryProvider extends ChangeNotifier {
  final CollectionReference _collection =
      FirebaseFirestore.instance.collection('batteries');
  
  List<BatteryItem> _items = [];
  
  // Dynamic Categories from Firestore (e.g., settings/battery_types -> {types: [...]})
  List<String> _categories = [];
  List<String> get categories => _categories;
  
  // Default categories to use as a fallback if Firestore fails or is empty
  final List<String> _defaultCategories = ['AA', 'AAA', 'C', 'D', '9V', 'CR2032', 'Other'];

  InventoryProvider() {
    _fetchCategories(); // Start fetching categories immediately

    // Listen to real-time updates from Inventory (batteries)
    _collection.snapshots().listen((snapshot) {
      _items = snapshot.docs.map((doc) {
        return BatteryItem.fromMap(doc.id, doc.data() as Map<String, dynamic>);
      }).toList();
      notifyListeners();
    });
  }

  // New method to fetch categories from Firestore
  Future<void> _fetchCategories() async {
    try {
      // Fetch a single document where the battery types are stored
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('battery_types')
          .get();

      if (doc.exists && doc.data() is Map<String, dynamic>) {
        final data = doc.data() as Map<String, dynamic>;
        
        // Assuming the types are stored in a field called 'types' as an array of strings
        if (data.containsKey('types') && data['types'] is List) {
          _categories = List<String>.from(data['types']);
          // Ensure 'Other' is always available as a fallback option
          if (!_categories.contains('Other')) {
             _categories.add('Other');
          }
        } else {
            // Use default if document exists but format is wrong
            _categories = _defaultCategories;
        }
      } else {
        // Use default if document does not exist
        _categories = _defaultCategories;
        // Optionally, create the default document if it doesn't exist to seed data
        await FirebaseFirestore.instance.collection('settings').doc('battery_types').set({'types': _defaultCategories});
      }
    } catch (e) {
      // Fallback on any error during fetching
      print('Error fetching battery categories: $e');
      _categories = _defaultCategories;
    }
    notifyListeners();
  }

  bool _showLowStockOnly = false;

  List<BatteryItem> get items {
    if (_showLowStockOnly) {
      return _items.where((i) => i.isLowStock).toList();
    }
    return _items;
  }

  // Dashboard Stats
  int get totalItems => _items.length;
  int get lowStockCount => _items.where((i) => i.isLowStock).length;
  int get totalBatteriesCount => _items.fold(0, (sum, item) => sum + item.quantity);

  bool get showLowStockOnly => _showLowStockOnly;

  void toggleFilter() {
    _showLowStockOnly = !_showLowStockOnly;
    notifyListeners();
  }

  Future<void> addItem(BatteryItem item) async {
    await _collection.add(item.toMap());
  }

  Future<void> updateItem(String id, BatteryItem newItem) async {
    await _collection.doc(id).update(newItem.toMap());
  }

  Future<void> deleteItem(String id) async {
    await _collection.doc(id).delete();
  }

  // Quick action to adjust quantity
  Future<void> adjustQuantity(String id, int delta) async {
    final index = _items.indexWhere((i) => i.id == id);
    if (index != -1) {
      final current = _items[index].quantity;
      if (current + delta >= 0) {
        await _collection.doc(id).update({'quantity': current + delta});
      }
    }
  }
}

// -----------------------------------------------------------------------------
// 3. MAIN APP
// -----------------------------------------------------------------------------

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform, 
  ); // Ensure you have configured your firebase project
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => InventoryProvider()),
      ],
      child: const BatteryBuddyApp(),
    ),
  );
}

class BatteryBuddyApp extends StatelessWidget {
  const BatteryBuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Battery Buddy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueAccent,
          brightness: Brightness.light,
        ),
        textTheme: GoogleFonts.interTextTheme(),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueAccent,
          brightness: Brightness.dark,
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      ),
      home: const DashboardScreen(),
    );
  }
}

// -----------------------------------------------------------------------------
// 4. SCREENS & WIDGETS
// -----------------------------------------------------------------------------

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Battery Buddy'),
        actions: [
          IconButton(
            // Use FaIcon with appropriate Font Awesome icons
            icon: FaIcon(
              inventory.showLowStockOnly ? FontAwesomeIcons.filterCircleXmark : FontAwesomeIcons.filter,
              size: 20,
            ),
            onPressed: inventory.toggleFilter,
            tooltip: 'Filter Low Stock',
          ),
          IconButton(
            icon: const FaIcon(FontAwesomeIcons.gear, size: 20),
            onPressed: () {
               ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Settings not implemented in demo')),
                );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Dashboard Stats Header
          _buildStatsCards(context, inventory),
          
          const Divider(height: 1),

          // Inventory List
          Expanded(
            child: inventory.items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Font Awesome empty state
                        const FaIcon(FontAwesomeIcons.batteryEmpty, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          'No batteries found.',
                          style: TextStyle(color: Colors.grey[600], fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: inventory.items.length,
                    itemBuilder: (context, index) {
                      final item = inventory.items[index];
                      return BatteryCard(item: item);
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _navigateToAddEdit(context),
        icon: const FaIcon(FontAwesomeIcons.plus),
        label: const Text('Add Battery'),
      ),
    );
  }

  Widget _buildStatsCards(BuildContext context, InventoryProvider inventory) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              title: 'Need Restock',
              value: inventory.lowStockCount.toString(),
              icon: FontAwesomeIcons.triangleExclamation,
              color: Colors.orange,
              isAlert: inventory.lowStockCount > 0,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              title: 'Total Units',
              value: inventory.totalBatteriesCount.toString(),
              icon: FontAwesomeIcons.batteryFull,
              color: Colors.blue,
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToAddEdit(BuildContext context, [BatteryItem? item]) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddEditScreen(item: item)),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon; // Accepts FontAwesomeIcons data
  final Color color;
  final bool isAlert;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.isAlert = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      color: isAlert ? color.withOpacity(0.1) : Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        side: isAlert ? BorderSide(color: color, width: 2) : BorderSide.none,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FaIcon(icon, color: color), // Using FaIcon
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class BatteryCard extends StatelessWidget {
  final BatteryItem item;

  const BatteryCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<InventoryProvider>();
    final isLow = item.isLowStock;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      elevation: 1,
      child: InkWell(
        onTap: () {
             Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AddEditScreen(item: item)),
            );
        },
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              // Icon Container
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: isLow ? Colors.red.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    // Now uses the string type
                    item.type.toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isLow ? Colors.red : Colors.blue,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item.brand} ${item.model}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        FaIcon(FontAwesomeIcons.locationDot, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          item.location,
                          style: TextStyle(color: Colors.grey[600], fontSize: 13),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Quantity Controls
              Row(
                children: [
                  IconButton(
                    icon: const FaIcon(FontAwesomeIcons.circleMinus, size: 20),
                    color: Colors.grey,
                    onPressed: () => provider.adjustQuantity(item.id, -1),
                  ),
                  Text(
                    '${item.quantity}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isLow ? Colors.red : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  IconButton(
                    icon: const FaIcon(FontAwesomeIcons.circlePlus, size: 20),
                    color: Theme.of(context).primaryColor,
                    onPressed: () => provider.adjustQuantity(item.id, 1),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 5. ADD / EDIT SCREEN
// -----------------------------------------------------------------------------

class AddEditScreen extends StatefulWidget {
  final BatteryItem? item;

  const AddEditScreen({super.key, this.item});

  @override
  State<AddEditScreen> createState() => _AddEditScreenState();
}

class _AddEditScreenState extends State<AddEditScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late String _brand;
  late String _model;
  late String _type; // Changed from BatteryType to String
  late int _quantity;
  late String _location;
  late int _minThreshold;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _brand = item?.brand ?? '';
    _model = item?.model ?? '';
    // Use the stored type string, defaulting to 'AA' or the first available category if needed
    _type = item?.type ?? 'AA'; 
    _quantity = item?.quantity ?? 0;
    _location = item?.location ?? '';
    _minThreshold = item?.minStockThreshold ?? 5;
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      final provider = context.read<InventoryProvider>();

      final newItem = BatteryItem(
        id: widget.item?.id ?? DateTime.now().toIso8601String(),
        brand: _brand,
        model: _model,
        type: _type, // Saved as string
        quantity: _quantity,
        location: _location,
        minStockThreshold: _minThreshold,
      );

      if (widget.item == null) {
        provider.addItem(newItem);
      } else {
        provider.updateItem(widget.item!.id, newItem);
      }
      Navigator.pop(context);
    }
  }

  void _delete() {
    if (widget.item != null) {
      context.read<InventoryProvider>().deleteItem(widget.item!.id);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.item != null;
    final inventoryProvider = context.watch<InventoryProvider>();
    final availableTypes = inventoryProvider.categories;
    
    // Ensure the currently selected type is one of the available types, or fall back to the first one.
    if (!availableTypes.contains(_type) && availableTypes.isNotEmpty) {
      _type = availableTypes.first;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Battery' : 'Add Battery'),
        actions: [
          if (isEditing)
            IconButton(
              icon: const FaIcon(FontAwesomeIcons.trashCan, color: Colors.red, size: 20),
              onPressed: _delete,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                initialValue: _brand,
                decoration: const InputDecoration(labelText: 'Brand', border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? 'Required' : null,
                onSaved: (v) => _brand = v!,
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: _model,
                decoration: const InputDecoration(labelText: 'Model', border: OutlineInputBorder()),
                validator: (v) => v!.isEmpty ? 'Required' : null,
                onSaved: (v) => _model = v!,
              ),
              const SizedBox(height: 16),
              // Dropdown now uses the dynamic list of category strings
              DropdownButtonFormField<String>(
                // Ensure a valid initial value is set from the dynamic list
                value: availableTypes.isNotEmpty ? _type : null,
                decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                items: availableTypes.map((t) {
                  return DropdownMenuItem(value: t, child: Text(t.toUpperCase()));
                }).toList(),
                onChanged: (v) => setState(() => _type = v!),
                validator: (v) => v == null ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: _quantity.toString(),
                      decoration: const InputDecoration(labelText: 'Quantity', border: OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                      validator: (v) => int.tryParse(v!) == null ? 'Invalid' : null,
                      onSaved: (v) => _quantity = int.parse(v!),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      initialValue: _minThreshold.toString(),
                      decoration: const InputDecoration(labelText: 'Low Stock Alert At', border: OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                      validator: (v) => int.tryParse(v!) == null ? 'Invalid' : null,
                      onSaved: (v) => _minThreshold = int.parse(v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                initialValue: _location,
                decoration: const InputDecoration(
                  labelText: 'Location / Container', 
                  border: OutlineInputBorder(), 
                  prefixIcon: Padding(
                    padding: EdgeInsets.all(12.0),
                    child: FaIcon(FontAwesomeIcons.locationDot, size: 16),
                  )
                ),
                onSaved: (v) => _location = v ?? '',
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
                child: Text(isEditing ? 'Save Changes' : 'Add to Inventory'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}