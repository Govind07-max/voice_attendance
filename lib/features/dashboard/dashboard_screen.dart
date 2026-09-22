import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../alerts/alerts_screen.dart';
import '../attendance/attendance_screen.dart';
import '../classes/classes_screen.dart';
import '../profile/profile_screen.dart';
import '../reports/reports_screen.dart';
import '../students/student_import_screen.dart';

class DashboardShell extends StatefulWidget {
  const DashboardShell({super.key});

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    DashboardHomeScreen(),
    ClassesScreen(),
    AttendanceScreen(),
    ReportsScreen(),
    AlertsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    if (isDesktop) {
      // Responsive Web/Desktop Layout with Left Sidebar
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) => setState(() => _selectedIndex = index),
              labelType: NavigationRailLabelType.all,
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Icon(Icons.record_voice_over, size: 36, color: AppColors.primary),
              ),
              destinations: const [
                NavigationRailDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: Text('Dashboard')),
                NavigationRailDestination(icon: Icon(Icons.class_outlined), selectedIcon: Icon(Icons.class_), label: Text('Classes')),
                NavigationRailDestination(icon: Icon(Icons.mic_none), selectedIcon: Icon(Icons.mic), label: Text('Attendance')),
                NavigationRailDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: Text('Reports')),
                NavigationRailDestination(icon: Icon(Icons.warning_amber_outlined), selectedIcon: Icon(Icons.warning), label: Text('Alerts')),
                NavigationRailDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: Text('Profile')),
              ],
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(child: _screens[_selectedIndex]),
          ],
        ),
      );
    }

    // Mobile Navigation Layout with Bottom Navigation Bar
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex > 4 ? 4 : _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.class_outlined), activeIcon: Icon(Icons.class_), label: 'Classes'),
          BottomNavigationBarItem(icon: Icon(Icons.mic_none), activeIcon: Icon(Icons.mic), label: 'Attendance'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart_outlined), activeIcon: Icon(Icons.bar_chart), label: 'Reports'),
          BottomNavigationBarItem(icon: Icon(Icons.warning_amber_outlined), activeIcon: Icon(Icons.warning), label: 'Alerts'),
        ],
      ),
    );
  }
}

class DashboardHomeScreen extends StatelessWidget {
  const DashboardHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Attendance System'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Header Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.accent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Welcome back, Teacher!',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Voice-assisted attendance, cumulative subject reports, and automated 75% low-attendance monitoring.',
                    style: TextStyle(fontSize: 14, color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                    ),
                    icon: const Icon(Icons.mic),
                    label: const Text('Take Attendance Now'),
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceScreen()));
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Quick Stats Row
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    title: 'Active Classes',
                    value: '3',
                    icon: Icons.class_,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    title: 'Total Students',
                    value: '120',
                    icon: Icons.people,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard(
                    title: 'Below 75%',
                    value: '4',
                    icon: Icons.warning,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Quick Actions List
            const Text(
              'Quick Actions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.file_upload_outlined, color: AppColors.primary),
                    title: const Text('Import Student Roster (Excel XLSX)'),
                    subtitle: const Text('Upload PRN, Name, Email spreadsheet'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const StudentImportScreen()));
                    },
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.table_chart_outlined, color: AppColors.accent),
                    title: const Text('View Cumulative Reports'),
                    subtitle: const Text('Export XLSX and PDF cumulative matrices'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen()));
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
