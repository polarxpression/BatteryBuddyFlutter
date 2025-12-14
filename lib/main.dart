import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:async';

// -----------------------------------------------------------------------------
// 0. CONFIGURATION & CONSTANTS
// -----------------------------------------------------------------------------

// Global keys for navigation
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// App Colors - "Polar" Theme
class AppColors {
  static const Color primary = Color(0xFF06B6D4); // Cyan 500
  static const Color secondary = Color(0xFF3B82F6); // Blue 500
  static const Color accent = Color(0xFFF43F5E); // Rose 500
  
  static const Color backgroundDark = Color(0xFF0F172A); // Slate 900
  static const Color surfaceDark = Color(0xFF1E293B); // Slate 800
  static const Color surfaceHighlight = Color(0xFF334155); // Slate 700
  
  static const Color textPrimary = Color(0xFFF1F5F9); // Slate 100
  static const Color textSecondary = Color(0xFF94A3B8); // Slate 400
}

// -----------------------------------------------------------------------------
// 1. MODELS
// -----------------------------------------------------------------------------

class BatteryItem {
  final String id;
  String brand;
  String model;
  String type; 
  String location;
  int quantity;
  int minStockThreshold;
  DateTime lastUpdated;

  BatteryItem({
    required this.id,
    required this.brand,
    required this.model,
    required this.type,
    required this.location,
    required this.quantity,
    this.minStockThreshold = 5,
    required this.lastUpdated,
  });

  Map<String, dynamic> toMap() {
    return {
      'brand': brand,
      'model': model,
      'type': type,
      'location': location,
      'quantity': quantity,
      'minStockThreshold': minStockThreshold,
      'lastUpdated': Timestamp.fromDate(lastUpdated),
    };
  }

  factory BatteryItem.fromMap(String id, Map<String, dynamic> map) {
    return BatteryItem(
      id: id,
      brand: map['brand'] ?? 'Unknown',
      model: map['model'] ?? 'Unknown',
      type: map['type'] ?? 'Other',
      location: map['location'] ?? 'Unsorted',
      quantity: map['quantity'] ?? 0,
      minStockThreshold: map['minStockThreshold'] ?? 5,
      lastUpdated: (map['lastUpdated'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  bool get isLowStock => quantity <= minStockThreshold;
}

class ActivityLog {
  final String id;
  final String action; // "Add", "Remove", "Update"
  final String description;
  final DateTime timestamp;

  ActivityLog({required this.id, required this.action, required this.description, required this.timestamp});
}

// -----------------------------------------------------------------------------
// 2. PROVIDERS & STATE
// -----------------------------------------------------------------------------

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  User? _user;
  bool _isLoading = true;

  User? get user => _user;
  bool get isLoading => _isLoading;

  AuthProvider() {
    _init();
  }

  Future<void> _init() async {
    // Check for custom token from environment (Canvas specific)
    // In a real app, this might just be onAuthStateChanged
    try {
      // NOTE: In the Canvas environment, we check for __initial_auth_token.
      // Since we can't access global JS vars directly in Dart easily without js_interop, 
      // we'll assume the standard flow or anonymous login for this demo.
      // For this "rebuild", we prioritize Anonymous login if no user is found to ensure it works immediately.
      
      _auth.authStateChanges().listen((User? user) {
        _user = user;
        _isLoading = false;
        notifyListeners();
      });

      if (_auth.currentUser == null) {
         // Auto-login anonymously for demo purposes if not logged in
         await _auth.signInAnonymously();
      }
    } catch (e) {
      print("Auth Error: $e");
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signInAnonymously() async {
    try {
      _isLoading = true;
      notifyListeners();
      await _auth.signInAnonymously();
    } catch (e) {
      print(e);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}

class InventoryProvider extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String? _userId;

  List<BatteryItem> _items = [];
  List<BatteryItem> _filteredItems = [];
  List<ActivityLog> _recentActivity = []; // Local session log for demo
  
  // Search & Filter State
  String _searchQuery = '';
  String? _filterType;
  bool _showLowStockOnly = false;

  InventoryProvider(this._userId) {
    if (_userId != null) {
      _subscribe();
    }
  }

  List<BatteryItem> get items => _filteredItems;
  List<ActivityLog> get activities => _recentActivity;
  
  // Dashboard Stats
  int get totalItems => _items.fold(0, (sum, item) => sum + item.quantity);
  int get lowStockCount => _items.where((i) => i.isLowStock).length;
  int get totalSKUs => _items.length;
  Map<String, int> get typeDistribution {
    final map = <String, int>{};
    for (var item in _items) {
      map[item.type] = (map[item.type] ?? 0) + item.quantity;
    }
    return map;
  }

  void _subscribe() {
    // NOTE: Using a public collection path for this demo so users can share data
    // In a real private app, use users/{userId}/batteries
    // We are using 'artifacts/battery_buddy_v2/public/data' pattern
    final collectionPath = 'artifacts/battery_buddy_v2/public/data';
    
    _db.collection(collectionPath).snapshots().listen((snapshot) {
      _items = snapshot.docs.map((doc) => BatteryItem.fromMap(doc.id, doc.data())).toList();
      _applyFilters();
    });
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    _applyFilters();
  }

  void setTypeFilter(String? type) {
    _filterType = type;
    _applyFilters();
  }

  void toggleLowStockFilter() {
    _showLowStockOnly = !_showLowStockOnly;
    _applyFilters();
  }

  void _applyFilters() {
    _filteredItems = _items.where((item) {
      final matchesSearch = item.brand.toLowerCase().contains(_searchQuery.toLowerCase()) || 
                            item.model.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesType = _filterType == null || item.type == _filterType;
      final matchesLowStock = !_showLowStockOnly || item.isLowStock;

      return matchesSearch && matchesType && matchesLowStock;
    }).toList();
    
    // Sort: Low stock first, then alphabetically
    _filteredItems.sort((a, b) {
       if (a.isLowStock && !b.isLowStock) return -1;
       if (!a.isLowStock && b.isLowStock) return 1;
       return a.brand.compareTo(b.brand);
    });

    notifyListeners();
  }

  Future<void> addItem(BatteryItem item) async {
    if (_userId == null) return;
    final collectionPath = 'artifacts/battery_buddy_v2/public/data';
    await _db.collection(collectionPath).add(item.toMap());
    _logActivity("Added", "${item.brand} ${item.model}");
  }

  Future<void> updateItem(BatteryItem item) async {
    if (_userId == null) return;
    final collectionPath = 'artifacts/battery_buddy_v2/public/data';
    await _db.collection(collectionPath).doc(item.id).update(item.toMap());
    _logActivity("Updated", "${item.brand} ${item.model}");
  }

  Future<void> deleteItem(String id) async {
    if (_userId == null) return;
    final collectionPath = 'artifacts/battery_buddy_v2/public/data';
    await _db.collection(collectionPath).doc(id).delete();
    _logActivity("Deleted", "Item removed from inventory");
  }

  Future<void> adjustQuantity(String id, int delta) async {
    if (_userId == null) return;
    final index = _items.indexWhere((i) => i.id == id);
    if (index != -1) {
      final item = _items[index];
      final newQty = item.quantity + delta;
      if (newQty >= 0) {
        final collectionPath = 'artifacts/battery_buddy_v2/public/data';
        await _db.collection(collectionPath).doc(id).update({
          'quantity': newQty,
          'lastUpdated': Timestamp.now(),
        });
        _logActivity(delta > 0 ? "Stock In" : "Stock Out", "${item.brand} ${item.model} (${delta > 0 ? '+' : ''}$delta)");
      }
    }
  }

  void _logActivity(String action, String desc) {
    _recentActivity.insert(0, ActivityLog(
      id: DateTime.now().toString(),
      action: action,
      description: desc,
      timestamp: DateTime.now(),
    ));
    if (_recentActivity.length > 20) _recentActivity.removeLast();
    notifyListeners();
  }
}

// -----------------------------------------------------------------------------
// 3. MAIN APP ENTRY POINT
// -----------------------------------------------------------------------------

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Use the __firebase_config from the environment
  const firebaseConfigStr = String.fromEnvironment('FIREBASE_CONFIG');
  // For this environment, we rely on the `index.html` (which we simulate here) to have initialized, 
  // but in Flutter Web we must initialize explicitly.
  // We will try standard init. If it fails (already exists), we catch it.
  try {
     await Firebase.initializeApp(
       options: DefaultFirebaseOptions.currentPlatform,
     );
  } catch (e) {
    // likely already initialized
  }

  runApp(const BatteryBuddyApp());
}

class BatteryBuddyApp extends StatelessWidget {
  const BatteryBuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProxyProvider<AuthProvider, InventoryProvider>(
          create: (context) => InventoryProvider(context.read<AuthProvider>().user?.uid),
          update: (context, auth, previous) => InventoryProvider(auth.user?.uid),
        ),
      ],
      child: MaterialApp(
        title: 'BatteryBuddy',
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark, // Enforce Dark/Polar Theme
        theme: ThemeData.light(), // Fallback
        darkTheme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: AppColors.backgroundDark,
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            secondary: AppColors.secondary,
            surface: AppColors.surfaceDark,
            background: AppColors.backgroundDark,
            error: AppColors.accent,
            onSurface: AppColors.textPrimary,
          ),
          textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).apply(
            bodyColor: AppColors.textPrimary,
            displayColor: AppColors.textPrimary,
          ),
          cardTheme: CardTheme(
            color: AppColors.surfaceDark,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppColors.surfaceHighlight.withOpacity(0.5)),
            ),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: AppColors.backgroundDark,
            elevation: 0,
            centerTitle: false,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: AppColors.surfaceHighlight.withOpacity(0.3),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
            labelStyle: const TextStyle(color: AppColors.textSecondary),
            prefixIconColor: AppColors.textSecondary,
          ),
        ),
        home: const AuthWrapper(),
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (auth.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (auth.user == null) {
      return const LoginScreen();
    }
    return const MainLayout();
  }
}

// -----------------------------------------------------------------------------
// 4. SCREENS
// -----------------------------------------------------------------------------

// --- LOGIN SCREEN ---
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(FontAwesomeIcons.batteryFull, size: 64, color: AppColors.primary),
                const SizedBox(height: 24),
                Text(
                  'BatteryBuddy',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'Power your inventory.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 48),
                FilledButton.icon(
                  onPressed: () => context.read<AuthProvider>().signInAnonymously(),
                  icon: const Icon(FontAwesomeIcons.userSecret),
                  label: const Text('Enter as Guest'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(20),
                    backgroundColor: AppColors.surfaceHighlight,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                // Visual Divider
                Row(
                  children: [
                    Expanded(child: Divider(color: AppColors.surfaceHighlight)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text("OR", style: TextStyle(color: AppColors.textSecondary)),
                    ),
                    Expanded(child: Divider(color: AppColors.surfaceHighlight)),
                  ],
                ),
                const SizedBox(height: 16),
                // Mock Input fields just for visuals (Not functional in this demo)
                const TextField(
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.email_outlined),
                    labelText: 'Email Address',
                  ),
                ),
                const SizedBox(height: 12),
                const TextField(
                  obscureText: true,
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.lock_outline),
                    labelText: 'Password',
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () {}, // Mock login
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.all(20),
                    backgroundColor: AppColors.primary,
                  ),
                  child: const Text('Sign In'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- MAIN LAYOUT (Responsive) ---
class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const DashboardView(),
    const InventoryView(),
    const SettingsView(),
  ];

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      body: Row(
        children: [
          if (isDesktop)
            NavigationRail(
              backgroundColor: AppColors.surfaceDark,
              selectedIndex: _selectedIndex,
              onDestinationSelected: (int index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.all(24.0),
                child: const Icon(FontAwesomeIcons.batteryBolt, color: AppColors.primary, size: 32),
              ),
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(FontAwesomeIcons.chartSimple),
                  label: Text('Dashboard'),
                ),
                NavigationRailDestination(
                  icon: Icon(FontAwesomeIcons.boxesStacked),
                  label: Text('Inventory'),
                ),
                NavigationRailDestination(
                  icon: Icon(FontAwesomeIcons.gear),
                  label: Text('Settings'),
                ),
              ],
            ),
          
          if (isDesktop) const VerticalDivider(thickness: 1, width: 1, color: AppColors.surfaceHighlight),

          Expanded(
            child: _screens[_selectedIndex],
          ),
        ],
      ),
      bottomNavigationBar: isDesktop
          ? null
          : NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) => setState(() => _selectedIndex = index),
              backgroundColor: AppColors.surfaceDark,
              indicatorColor: AppColors.primary.withOpacity(0.2),
              destinations: const [
                NavigationDestination(
                  icon: Icon(FontAwesomeIcons.chartSimple),
                  label: 'Dashboard',
                ),
                NavigationDestination(
                  icon: Icon(FontAwesomeIcons.boxesStacked),
                  label: 'Inventory',
                ),
                NavigationDestination(
                  icon: Icon(FontAwesomeIcons.gear),
                  label: 'Settings',
                ),
              ],
            ),
      floatingActionButton: _selectedIndex == 1 // Only show FAB on Inventory screen
          ? FloatingActionButton.extended(
              onPressed: () => _showAddEditDialog(context),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              icon: const Icon(FontAwesomeIcons.plus),
              label: const Text("Add Item"),
            )
          : null,
    );
  }

  void _showAddEditDialog(BuildContext context, [BatteryItem? item]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceDark,
      builder: (ctx) => AddEditSheet(item: item),
    );
  }
}

// --- DASHBOARD VIEW ---
class DashboardView extends StatelessWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Overview', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Stats Row
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final isWide = width > 600;
              return Flex(
                direction: isWide ? Axis.horizontal : Axis.vertical,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    flex: isWide ? 1 : 0,
                    child: StatCard(
                      title: 'Total Stock',
                      value: '${inventory.totalItems}',
                      icon: FontAwesomeIcons.layerGroup,
                      color: AppColors.secondary,
                      trend: '+12%', // Mock trend
                    ),
                  ),
                  SizedBox(width: isWide ? 16 : 0, height: isWide ? 0 : 16),
                  Flexible(
                    flex: isWide ? 1 : 0,
                    child: StatCard(
                      title: 'Low Stock Alerts',
                      value: '${inventory.lowStockCount}',
                      icon: FontAwesomeIcons.triangleExclamation,
                      color: AppColors.accent,
                      isAlert: inventory.lowStockCount > 0,
                    ),
                  ),
                  SizedBox(width: isWide ? 16 : 0, height: isWide ? 0 : 16),
                  Flexible(
                    flex: isWide ? 1 : 0,
                    child: StatCard(
                      title: 'Unique SKUs',
                      value: '${inventory.totalSKUs}',
                      icon: FontAwesomeIcons.tag,
                      color: Colors.greenAccent,
                    ),
                  ),
                ],
              );
            },
          ),
          
          const SizedBox(height: 24),
          
          Text("Distribution by Type", style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          
          // 2. Simple Distribution Visualizer
          Container(
            height: 20,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: AppColors.surfaceHighlight,
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: inventory.typeDistribution.entries.map((e) {
                final color = _getColorForType(e.key);
                final flex = e.value;
                return Expanded(
                  flex: flex,
                  child: Container(color: color, child: Tooltip(message: "${e.key}: ${e.value}", child: const SizedBox())),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            children: inventory.typeDistribution.entries.map((e) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(color: _getColorForType(e.key), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Text("${e.key} (${e.value})", style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              );
            }).toList(),
          ),

          const SizedBox(height: 32),
          
          // 3. Recent Activity Log
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Recent Activity", style: Theme.of(context).textTheme.titleMedium),
              TextButton(onPressed: () {}, child: const Text("View All"))
            ],
          ),
          const SizedBox(height: 8),
          if (inventory.activities.isEmpty)
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.surfaceHighlight),
              ),
              child: const Center(child: Text("No recent activity recorded locally.", style: TextStyle(color: AppColors.textSecondary))),
            )
          else
            ...inventory.activities.map((log) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: AppColors.surfaceHighlight,
                child: Icon(
                  log.action == "Added" ? FontAwesomeIcons.plus : 
                  log.action.contains("Stock In") ? FontAwesomeIcons.arrowUp :
                  log.action.contains("Stock Out") ? FontAwesomeIcons.arrowDown :
                  FontAwesomeIcons.pen,
                  size: 14,
                  color: AppColors.textPrimary,
                ),
              ),
              title: Text(log.description, style: const TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text(log.action, style: const TextStyle(fontSize: 12, color: AppColors.primary)),
              trailing: Text(
                DateFormat('HH:mm').format(log.timestamp),
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            )),
        ],
      ),
    );
  }
  
  Color _getColorForType(String type) {
    switch (type) {
      case 'AA': return Colors.purpleAccent;
      case 'AAA': return Colors.blueAccent;
      case '9V': return Colors.orangeAccent;
      case 'C': return Colors.greenAccent;
      case 'D': return Colors.tealAccent;
      default: return Colors.grey;
    }
  }
}

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final bool isAlert;
  final String? trend;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.isAlert = false,
    this.trend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: isAlert ? Border.all(color: color.withOpacity(0.5), width: 1) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              if (trend != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(trend!, style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                )
            ],
          ),
          const SizedBox(height: 16),
          Text(value, style: GoogleFonts.spaceGrotesk(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          Text(title, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        ],
      ),
    );
  }
}

// --- INVENTORY VIEW ---
class InventoryView extends StatelessWidget {
  const InventoryView({super.key});

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryProvider>();

    return Scaffold(
      body: Column(
        children: [
          // Header & Search
          Container(
            padding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
            color: AppColors.backgroundDark,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: inventory.setSearchQuery,
                        decoration: const InputDecoration(
                          hintText: 'Search brand, model...',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: Icon(
                        inventory._showLowStockOnly ? Icons.filter_alt_off : Icons.filter_alt, 
                        color: inventory._showLowStockOnly ? AppColors.accent : AppColors.textSecondary
                      ),
                      onPressed: inventory.toggleLowStockFilter,
                      tooltip: "Filter Low Stock",
                      style: IconButton.styleFrom(backgroundColor: AppColors.surfaceHighlight),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'All', 
                        isSelected: inventory._filterType == null, 
                        onTap: () => inventory.setTypeFilter(null)
                      ),
                      ...['AA', 'AAA', '9V', 'C', 'D', 'CR2032', '18650', 'Other'].map(
                        (type) => _FilterChip(
                          label: type, 
                          isSelected: inventory._filterType == type,
                          onTap: () => inventory.setTypeFilter(type),
                        )
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // List
          Expanded(
            child: inventory.items.isEmpty 
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: inventory.items.length,
                  itemBuilder: (context, index) {
                    return BatteryListItem(item: inventory.items[index]);
                  },
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(FontAwesomeIcons.boxOpen, size: 64, color: AppColors.surfaceHighlight),
          const SizedBox(height: 16),
          Text("No items found", style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => onTap(),
        backgroundColor: AppColors.surfaceHighlight,
        selectedColor: AppColors.primary.withOpacity(0.2),
        checkmarkColor: AppColors.primary,
        labelStyle: TextStyle(
          color: isSelected ? AppColors.primary : AppColors.textSecondary,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide.none,
        ),
      ),
    );
  }
}

class BatteryListItem extends StatelessWidget {
  final BatteryItem item;

  const BatteryListItem({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<InventoryProvider>();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: AppColors.surfaceDark,
            builder: (ctx) => AddEditSheet(item: item),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              // 1. Type Icon
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: item.isLowStock ? AppColors.accent.withOpacity(0.1) : AppColors.secondary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    item.type,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: item.isLowStock ? AppColors.accent : AppColors.secondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              
              // 2. Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item.brand} ${item.model}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(FontAwesomeIcons.locationDot, size: 12, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(item.location, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        if (item.isLowStock) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(4)),
                            child: const Text("LOW STOCK", style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
                          )
                        ]
                      ],
                    ),
                  ],
                ),
              ),

              // 3. Quick Actions
              Row(
                children: [
                  _QuickActionButton(
                    icon: FontAwesomeIcons.minus,
                    onTap: () => provider.adjustQuantity(item.id, -1),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${item.quantity}',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 18, 
                        fontWeight: FontWeight.bold,
                        color: item.isLowStock ? AppColors.accent : AppColors.textPrimary
                      ),
                    ),
                  ),
                  _QuickActionButton(
                    icon: FontAwesomeIcons.plus,
                    onTap: () => provider.adjustQuantity(item.id, 1),
                    isPositive: true,
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

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isPositive;

  const _QuickActionButton({required this.icon, required this.onTap, this.isPositive = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.surfaceHighlight),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 12, color: isPositive ? AppColors.primary : AppColors.textSecondary),
        ),
      ),
    );
  }
}

// --- SETTINGS VIEW ---
class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Settings", style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionHeader(title: "Account"),
          ListTile(
            leading: const Icon(FontAwesomeIcons.userAstronaut, color: AppColors.textPrimary),
            title: const Text("Profile"),
            subtitle: Text("Guest User", style: TextStyle(color: AppColors.textSecondary)),
            trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(FontAwesomeIcons.rightFromBracket, color: AppColors.accent),
            title: const Text("Sign Out", style: TextStyle(color: AppColors.accent)),
            onTap: () => context.read<AuthProvider>().signOut(),
          ),
          
          const SizedBox(height: 24),
          const _SectionHeader(title: "Preferences"),
          SwitchListTile(
            value: true, 
            onChanged: (v) {},
            activeColor: AppColors.primary,
            title: const Text("Dark Mode"),
            secondary: const Icon(FontAwesomeIcons.moon, color: AppColors.textPrimary),
          ),
          SwitchListTile(
            value: false, 
            onChanged: (v) {},
            activeColor: AppColors.primary,
            title: const Text("Low Stock Notifications"),
            secondary: const Icon(FontAwesomeIcons.bell, color: AppColors.textPrimary),
          ),

          const SizedBox(height: 24),
          const _SectionHeader(title: "Data"),
          ListTile(
            leading: const Icon(FontAwesomeIcons.fileCsv, color: AppColors.textPrimary),
            title: const Text("Export CSV"),
            onTap: () {
               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Export started...")));
            },
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// --- ADD / EDIT SHEET ---
class AddEditSheet extends StatefulWidget {
  final BatteryItem? item;
  const AddEditSheet({super.key, this.item});

  @override
  State<AddEditSheet> createState() => _AddEditSheetState();
}

class _AddEditSheetState extends State<AddEditSheet> {
  final _formKey = GlobalKey<FormState>();
  
  late String _brand;
  late String _model;
  late String _type;
  late int _quantity;
  late int _minThreshold;
  late String _location;

  @override
  void initState() {
    super.initState();
    final i = widget.item;
    _brand = i?.brand ?? '';
    _model = i?.model ?? '';
    _type = i?.type ?? 'AA';
    _quantity = i?.quantity ?? 0;
    _minThreshold = i?.minStockThreshold ?? 5;
    _location = i?.location ?? '';
  }

  void _save() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      final provider = context.read<InventoryProvider>();
      
      final item = BatteryItem(
        id: widget.item?.id ?? '', // ID handled by add() if empty
        brand: _brand,
        model: _model,
        type: _type,
        location: _location,
        quantity: _quantity,
        minStockThreshold: _minThreshold,
        lastUpdated: DateTime.now(),
      );

      if (widget.item == null) {
        provider.addItem(item);
      } else {
        provider.updateItem(item);
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
    final keyboardSpace = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + keyboardSpace),
      decoration: const BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEditing ? 'Edit Item' : 'New Battery',
                    style: GoogleFonts.spaceGrotesk(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  if (isEditing)
                    IconButton(
                      icon: const Icon(FontAwesomeIcons.trash, color: AppColors.accent),
                      onPressed: _delete,
                    )
                ],
              ),
              const SizedBox(height: 24),
              
              // Row 1: Brand & Model
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: _brand,
                      decoration: const InputDecoration(labelText: 'Brand'),
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                      onSaved: (v) => _brand = v!,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      initialValue: _model,
                      decoration: const InputDecoration(labelText: 'Model'),
                      validator: (v) => v!.isEmpty ? 'Required' : null,
                      onSaved: (v) => _model = v!,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Type Dropdown
              DropdownButtonFormField<String>(
                value: _type,
                dropdownColor: AppColors.surfaceHighlight,
                decoration: const InputDecoration(labelText: 'Type'),
                items: ['AA', 'AAA', '9V', 'C', 'D', 'CR2032', '18650', 'Other'].map((t) {
                  return DropdownMenuItem(value: t, child: Text(t));
                }).toList(),
                onChanged: (v) => setState(() => _type = v!),
              ),
              const SizedBox(height: 16),

              // Row 2: Qty & Threshold
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: _quantity.toString(),
                      decoration: const InputDecoration(labelText: 'Quantity'),
                      keyboardType: TextInputType.number,
                      validator: (v) => int.tryParse(v!) == null ? 'Invalid' : null,
                      onSaved: (v) => _quantity = int.parse(v!),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      initialValue: _minThreshold.toString(),
                      decoration: const InputDecoration(labelText: 'Low Alert At'),
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
                  labelText: 'Location',
                  prefixIcon: Icon(FontAwesomeIcons.mapPin, size: 16),
                ),
                onSaved: (v) => _location = v ?? 'Unsorted',
              ),
              
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  backgroundColor: AppColors.primary,
                ),
                child: Text(isEditing ? 'Save Changes' : 'Add Item'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    // This is a placeholder. 
    // In the actual environment, options are passed via __firebase_config 
    // or initialized automatically in the index.html wrapper.
    // If you are running this locally, you must fill this with your Firebase setup.
    // For this specific environment, we return a dummy or rely on the global init.
    
    // Attempt to parse global config if available (not possible in pure Dart without interop).
    // Returning dummy data to satisfy the compiler; the actual init happens in main() via try/catch
    return const FirebaseOptions(
      apiKey: "demo-key",
      appId: "demo-app-id",
      messagingSenderId: "demo-sender-id",
      projectId: "demo-project-id",
    );
  }
}