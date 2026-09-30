import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('settings'); // Para el usuario y categorías
  await Hive.openBox('expenses'); // Para los gastos
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ExpenseProvider()),
      ],
      child: const SmartSpendApp(),
    ),
  );
}

// --- COLORES Y ESTILO ---
class AppColors {
  static const bgColor = Color(0xFF0F172A);
  static const cardColor = Color(0xFF1E293B);
  static const accent = Color(0xFF22D3EE); // Cyan
  static const textMain = Colors.white;
  static const textSec = Color(0xFF94A3B8);
  static const danger = Color(0xFFFB7185);

  static final chartPalette = [
    const Color(0xFF22D3EE),
    const Color(0xFF818CF8),
    const Color(0xFFF472B6),
    const Color(0xFF34D399),
    const Color(0xFFFBBF24),
    const Color(0xFFF87171),
  ];
}

// --- MODELO Y PROVIDERS ---
class ExpenseProvider with ChangeNotifier {
  final _box = Hive.box('expenses');
  final _settings = Hive.box('settings');

  List<dynamic>? _cachedExpenses;
  double? _cachedTotal;
  Map<String, double>? _cachedCategories;

  void _invalidateCache() {
    _cachedExpenses = null;
    _cachedTotal = null;
    _cachedCategories = null;
  }

  List<dynamic> get expenses {
    _cachedExpenses ??= _box.values.toList().reversed.toList();
    return _cachedExpenses!;
  }

  double get total {
    _cachedTotal ??= _box.values.fold<double>(
      0.0,
      (double sum, item) => sum + (item['amount'] as num).toDouble(),
    );
    return _cachedTotal!;
  }

  Map<String, double> get expensesByCategory {
    if (_cachedCategories == null) {
      _cachedCategories = {};
      for (var item in expenses) {
        final String category = item['category'] ?? 'General';
        final double amount = (item['amount'] as num).toDouble();
        final double currentTotal = _cachedCategories![category] ?? 0.0;
        _cachedCategories![category] = currentTotal + amount;
      }
    }
    return _cachedCategories!;
  }

  List<String> get categories {
    final defaultCats = ['General', 'Comida', 'Transporte', 'Entretenimiento'];
    final customCats =
        _settings.get('custom_categories', defaultValue: <dynamic>[])
            as List<dynamic>;
    final cats = [...defaultCats, ...customCats.map((e) => e.toString())];
    return cats.toSet().toList(); // eliminar duplicados
  }

  void addCategory(String category) {
    final trimmed = category.trim();
    if (trimmed.isEmpty) return;

    final customCats =
        _settings.get('custom_categories', defaultValue: <dynamic>[])
            as List<dynamic>;
    if (!categories.contains(trimmed)) {
      customCats.add(trimmed);
      _settings.put('custom_categories', customCats);
      notifyListeners();
    }
  }

  void addExpense(String title, double amount, String category) {
    _box.add({
      'title': title,
      'amount': amount,
      'category': category,
      'date': DateTime.now().toIso8601String(),
    });
    _invalidateCache();
    notifyListeners();
  }

  void deleteExpenses(List<int> reversedIndices) {
    final length = _box.length;
    List<int> realIndices = reversedIndices.map((r) => length - 1 - r).toList();
    realIndices.sort((a, b) => b.compareTo(a));
    for (var idx in realIndices) {
      if (idx >= 0 && idx < _box.length) {
        _box.deleteAt(idx);
      }
    }
    _invalidateCache();
    notifyListeners();
  }

  Future<bool> sendReportToN8n(String email) async {
  // 1. Reemplaza con tu URL real de n8n
  const webhookUrl = "https://samnochon.app.n8n.cloud/webhook-test/analizar-datos";
  try {
    
    final List<Map<String, dynamic>> expensesData = expenses.map((e) {
      return Map<String, dynamic>.from(e as Map);
    }).toList();

    final response = await http.post(
      Uri.parse(webhookUrl),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "email": email,
        "total_spent": total,
        "expenses": expensesData, // Datos limpios
        "timestamp": DateTime.now().toIso8601String(),
      }),
    ).timeout(const Duration(seconds: 15));

    return response.statusCode == 200;
  } catch (e) {
    debugPrint("Error en n8n: $e");
    return false;
  }
}
}

class AuthProvider with ChangeNotifier {
  final _box = Hive.box('settings');

  String? get email => _box.get('email');

  bool get isLoggedIn => email != null;

  void login(String email) {
    _box.put('email', email);
    notifyListeners();
  }

  void logout() {
    _box.delete('email');
    notifyListeners();
  }
}

// --- INTERFAZ ---
class SmartSpendApp extends StatelessWidget {
  const SmartSpendApp({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.bgColor,
        textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
      ),
      home: auth.isLoggedIn ? const MainTabScreen() : const LoginScreen(),
    );
  }
}

// --- PANTALLA DE LOGIN ---
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Bienvenido a \nFinanceToday",
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              "Tus finanzas, analizadas por IA",
              style: TextStyle(color: AppColors.textSec),
            ),
            const SizedBox(height: 40),
            TextField(
              controller: _emailController,
              decoration: InputDecoration(
                hintText: "Tu correo electrónico",
                filled: true,
                fillColor: AppColors.cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                onPressed: () {
                  if (_emailController.text.contains("@")) {
                    Provider.of<AuthProvider>(
                      context,
                      listen: false,
                    ).login(_emailController.text);
                  }
                },
                child: const Text(
                  "Entrar",
                  style: TextStyle(
                    color: AppColors.bgColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- PANTALLA PRINCIPAL CON TABS ---
class MainTabScreen extends StatefulWidget {
  const MainTabScreen({super.key});

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final authProv = Provider.of<AuthProvider>(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _currentIndex == 0 ? "Mis Gastos" : "Estadísticas",
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: () => authProv.logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _currentIndex == 0 ? const ExpensesListTab() : const StatsTab(),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: AppColors.cardColor,
        selectedItemColor: AppColors.accent,
        unselectedItemColor: AppColors.textSec,
        currentIndex: _currentIndex,
        onTap: (idx) => setState(() => _currentIndex = idx),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: "Gastos"),
          BottomNavigationBarItem(
            icon: Icon(Icons.pie_chart),
            label: "Gráficos",
          ),
        ],
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
              backgroundColor: AppColors.accent,
              onPressed: () => _showAddExpense(context),
              child: const Icon(Icons.add, color: AppColors.bgColor),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  void _showAddExpense(BuildContext context) {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.cardColor,
      builder: (context) {
        final prov = Provider.of<ExpenseProvider>(context, listen: false);
        String selectedCategory = prov.categories.first;
        final newCategoryCtrl = TextEditingController();
        bool isAddingCategory = false;

        return StatefulBuilder(
          builder: (context, setModalState) {
            final catList = prov.categories;
            if (!catList.contains(selectedCategory) && catList.isNotEmpty) {
              selectedCategory = catList.first;
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                top: 20,
                left: 20,
                right: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Nuevo Gasto",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      hintText: "Concepto (ej. Netflix)",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: amountCtrl,
                    decoration: const InputDecoration(
                      hintText: "Monto (ej. 12.50)",
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 10),

                  if (!isAddingCategory) ...[
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: selectedCategory,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                            ),
                            dropdownColor: AppColors.cardColor,
                            items: catList
                                .map(
                                  (cat) => DropdownMenuItem(
                                    value: cat,
                                    child: Text(cat),
                                  ),
                                )
                                .toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setModalState(() => selectedCategory = val);
                              }
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.add_circle,
                            color: AppColors.accent,
                          ),
                          onPressed: () =>
                              setModalState(() => isAddingCategory = true),
                        ),
                      ],
                    ),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: newCategoryCtrl,
                            decoration: const InputDecoration(
                              hintText: "Nombre de nueva categoría",
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.check,
                            color: AppColors.accent,
                          ),
                          onPressed: () {
                            if (newCategoryCtrl.text.isNotEmpty) {
                              prov.addCategory(newCategoryCtrl.text);
                              setModalState(() {
                                selectedCategory = newCategoryCtrl.text.trim();
                                isAddingCategory = false;
                              });
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: AppColors.danger,
                          ),
                          onPressed: () =>
                              setModalState(() => isAddingCategory = false),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    onPressed: () {
                      if (titleCtrl.text.trim().isEmpty ||
                          amountCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Por favor, llena ambos campos."),
                          ),
                        );
                        return;
                      }

                      final parsedAmount = double.tryParse(
                        amountCtrl.text.replaceAll(',', '.'),
                      );
                      if (parsedAmount == null) {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: AppColors.cardColor,
                            title: const Text(
                              "Valor inválido",
                              style: TextStyle(color: AppColors.danger),
                            ),
                            content: const Text(
                              "Por favor, ingresa solo números en el campo de monto (ejemplo: 15.50). Las letras no son permitidas.",
                              style: TextStyle(color: Colors.white),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text(
                                  "Entendido",
                                  style: TextStyle(color: AppColors.accent),
                                ),
                              ),
                            ],
                          ),
                        );
                        return;
                      }

                      prov.addExpense(
                        titleCtrl.text.trim(),
                        parsedAmount,
                        selectedCategory,
                      );
                      Navigator.pop(context);
                    },
                    child: const Text(
                      "Guardar Gasto",
                      style: TextStyle(
                        color: AppColors.bgColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// --- TAB: GASTOS ---
class ExpensesListTab extends StatefulWidget {
  const ExpensesListTab({super.key});

  @override
  State<ExpensesListTab> createState() => _ExpensesListTabState();
}

class _ExpensesListTabState extends State<ExpensesListTab> {
  bool _isLoadingN8n = false;
  final Set<int> _selectedIndices = {};

  void _toggleSelection(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  void _deleteSelected() {
    final prov = Provider.of<ExpenseProvider>(context, listen: false);
    prov.deleteExpenses(_selectedIndices.toList());
    setState(() {
      _selectedIndices.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final expenseProv = Provider.of<ExpenseProvider>(context);
    final authProv = Provider.of<AuthProvider>(context);

    return Column(
      children: [
        // Resumen superior o barra de selección
        _selectedIndices.isEmpty
            ? Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Gasto Mensual",
                            style: TextStyle(color: AppColors.textSec),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              "\$${expenseProv.total.toStringAsFixed(2)}",
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white10,
                      ),
                      onPressed: _isLoadingN8n
                          ? null
                          : () async {
                              setState(() => _isLoadingN8n = true);
                              final success = await expenseProv.sendReportToN8n(
                                authProv.email!,
                              );
                              if (!context.mounted) return;
                              setState(() => _isLoadingN8n = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    success
                                        ? "Reporte enviado con AI"
                                        : "Error de red al conectar con n8n",
                                  ),
                                ),
                              );
                            },
                      icon: _isLoadingN8n
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.accent,
                              ),
                            )
                          : const Icon(Icons.email_outlined, size: 16),
                      label: Text(
                        _isLoadingN8n ? "Procesando..." : "AI Report",
                      ),
                    ),
                  ],
                ),
              )
            : Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 15,
                ),
                color: AppColors.cardColor.withValues(alpha: 0.5),
                margin: const EdgeInsets.only(bottom: 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () =>
                              setState(() => _selectedIndices.clear()),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          "${_selectedIndices.length} seleccionados",
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete,
                        color: AppColors.danger,
                        size: 28,
                      ),
                      onPressed: _deleteSelected,
                    ),
                  ],
                ),
              ),

        // Lista de Gastos
        Expanded(
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.cardColor,
              borderRadius: BorderRadius.vertical(top: Radius.circular(35)),
            ),
            child: expenseProv.expenses.isEmpty
                ? const Center(
                    child: Text(
                      "No hay gastos registrados.",
                      style: TextStyle(color: AppColors.textSec),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(
                      top: 25,
                      left: 15,
                      right: 15,
                      bottom: 80,
                    ),
                    itemCount: expenseProv.expenses.length,
                    itemBuilder: (context, index) {
                      final item = expenseProv.expenses[index];
                      final isSelected = _selectedIndices.contains(index);

                      return Card(
                        color: isSelected
                            ? AppColors.accent.withValues(alpha: 0.1)
                            : Colors.transparent,
                        elevation: 0,
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isSelected
                                ? AppColors.accent
                                : Colors.transparent,
                            width: 1,
                          ),
                        ),
                        child: ListTile(
                          onLongPress: () => _toggleSelection(index),
                          onTap: () {
                            if (_selectedIndices.isNotEmpty) {
                              _toggleSelection(index);
                            }
                          },
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                          ),
                          leading: isSelected
                              ? const Icon(
                                  Icons.check_circle,
                                  color: AppColors.accent,
                                  size: 40,
                                )
                              : Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.account_balance_wallet,
                                    color: AppColors.accent,
                                  ),
                                ),
                          title: Text(
                            item['title'],
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            item['category'],
                            style: const TextStyle(color: AppColors.textSec),
                          ),
                          trailing: Text(
                            "-\$${(item['amount'] as num).toDouble().toStringAsFixed(2)}",
                            style: const TextStyle(
                              color: AppColors.danger,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

// --- TAB: ESTADÍSTICAS ---
class StatsTab extends StatelessWidget {
  const StatsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final expenseProv = Provider.of<ExpenseProvider>(context);
    final categoryMap = expenseProv.expensesByCategory;

    if (expenseProv.expenses.isEmpty || expenseProv.total == 0) {
      return const Center(
        child: Text(
          "No hay datos suficientes para el gráfico.",
          style: TextStyle(color: AppColors.textSec),
        ),
      );
    }

    return Column(
      children: [
        const SizedBox(height: 20),
        SizedBox(
          height: 250,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 50,
              sections: categoryMap.entries.toList().asMap().entries.map((
                entry,
              ) {
                final index = entry.key;
                final e = entry.value;
                final percentage = (e.value / expenseProv.total) * 100;
                return PieChartSectionData(
                  value: e.value,
                  color: AppColors
                      .chartPalette[index % AppColors.chartPalette.length],
                  title: "${percentage.toStringAsFixed(1)}%",
                  titleStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  radius: 60,
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 30),
        Expanded(
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.cardColor,
              borderRadius: BorderRadius.vertical(top: Radius.circular(35)),
            ),
            padding: const EdgeInsets.all(25),
            child: ListView.builder(
              itemCount: categoryMap.length,
              itemBuilder: (context, index) {
                final cat = categoryMap.keys.elementAt(index);
                final val = categoryMap[cat]!;
                final color = AppColors
                    .chartPalette[index % AppColors.chartPalette.length];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(cat, style: const TextStyle(fontSize: 16)),
                        ],
                      ),
                      Text(
                        "\$${val.toStringAsFixed(2)}",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
